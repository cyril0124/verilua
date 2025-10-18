#include "fmt/core.h"
#include "libassert/assert.hpp"
#include "slang/ast/ASTVisitor.h"
#include "slang/ast/Compilation.h"
#include "slang/ast/Symbol.h"
#include "slang/ast/symbols/InstanceSymbols.h"
#include "slang/ast/symbols/VariableSymbols.h"
#include "slang/diagnostics/TextDiagnosticClient.h"
#include "slang/driver/Driver.h"
#include "slang/syntax/SyntaxTree.h"
#include "slang/util/Util.h"
#include "sol/sol.hpp"
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>
#include <string_view>
#include <vector>

// For file locking
#include <cerrno>     // For errno
#include <cstring>    // For strerror()
#include <fcntl.h>    // For open()
#include <sys/file.h> // For flock()
#include <unistd.h>   // For close()

#ifndef VERILUA_VERSION
#define VERILUA_VERSION "Unknown"
#endif

#define DEFAULT_OUTPUT_FILE "./signal_db.ldb"

using namespace slang;
using namespace slang::ast;

using json = nlohmann::json;

class FileLock {
  public:
    FileLock(const std::string &path) : lock_path_(path) {
        fd_ = open(path.c_str(), O_RDWR | O_CREAT, 0666);
        if (fd_ < 0) {
            throw std::runtime_error("Failed to create lock file");
        }
        if (flock(fd_, LOCK_EX) == -1) {
            close(fd_);
            throw std::runtime_error("Failed to lock file: " + std::string(strerror(errno)));
        }
    }

    ~FileLock() {
        if (fd_ >= 0) {
            flock(fd_, LOCK_UN);
            close(fd_);
        }
    }

    // Disable copy and assign
    FileLock(const FileLock &)            = delete;
    FileLock &operator=(const FileLock &) = delete;

  private:
    int fd_ = -1;
    std::string lock_path_;
};

bool isFileNewer(const std::string &file1, const std::string &file2) {
    try {
        auto time1 = std::filesystem::last_write_time(file1);
        auto time2 = std::filesystem::last_write_time(file2);

        return time1 > time2;
    } catch (const std::filesystem::filesystem_error &e) {
        std::cerr << "[isFileNewer] Error: " << e.what() << std::endl;
        return false;
    }
}

std::string get_current_time_as_string() {
    auto now = std::chrono::system_clock::now();

    std::time_t now_time_t = std::chrono::system_clock::to_time_t(now);

    std::tm now_tm = *std::localtime(&now_time_t);

    std::ostringstream oss;
    oss << std::put_time(&now_tm, "%Y-%m-%d %H:%M:%S");

    return oss.str();
}

std::vector<std::string> splitString(std::string_view input, char delimiter) {
    std::vector<std::string> tokens;

    size_t tokenCount = std::count(input.begin(), input.end(), delimiter) + 1;
    tokens.reserve(tokenCount);

    const char *ptr        = input.data();
    const char *endPtr     = ptr + input.size();
    const char *tokenStart = ptr;

    while (ptr < endPtr) {
        if (*ptr == delimiter) {
            tokens.emplace_back(tokenStart, ptr - tokenStart);
            tokenStart = ptr + 1;
        }
        ptr++;
    }
    tokens.emplace_back(tokenStart, ptr - tokenStart);

    return tokens;
}

class SignalGetter : public ASTVisitor<SignalGetter, false, false> {
  public:
    std::vector<std::string> hierPathVec;
    std::vector<size_t> bitWidthVec;
    std::vector<std::string> typeStrVec;

    SignalGetter(std::vector<std::string> enableModules, std::vector<std::string> disableModules, bool ignoreTrivialSignals = true, bool ignoreUnderscoreSignals = true, bool verbose = false) : enableModules(enableModules), disableModules(disableModules), ignoreTrivialSignals(ignoreTrivialSignals), ignoreUnderscoreSignals(ignoreUnderscoreSignals), verbose(verbose) {}

    void handle(const InstanceBodySymbol &ast) {
        auto moduleName = ast.getDefinition().name;
        if (verbose) {
            fmt::println("[SignalGetter] handle module {}", moduleName);
            fflush(stdout);
        }

        if (!enableModules.empty() && std::find(enableModules.begin(), enableModules.end(), moduleName) == enableModules.end()) {
            if (verbose) {
                fmt::println("[SignalGetter] [whitelist] skip module {}", moduleName);
                fflush(stdout);
            }
            visitDefault(ast);
            return;
        }
        if (!disableModules.empty() && std::find(disableModules.begin(), disableModules.end(), moduleName) != disableModules.end()) {
            if (verbose) {
                fmt::println("[SignalGetter] [blacklist] skip module {}", moduleName);
                fflush(stdout);
            }
            visitDefault(ast);
            return;
        }

        auto varIter = ast.membersOfType<VariableSymbol>();
        for (const auto &var : varIter) {
            std::string hierPath = var.getHierarchicalPath();

            auto bitWidth = var.getType().getBitWidth();
            auto typeStr  = var.getType().toString();

            collectSignalInfo(hierPath, bitWidth, typeStr);

            if (verbose) {
                fmt::println("[InstanceBodySymbol] [VAR] {} bitwidth: {} type: {}", hierPath, bitWidth, typeStr);
            }
        }

        auto netIter = ast.membersOfType<NetSymbol>();
        for (const auto &net : netIter) {
            std::string hierPath = net.getHierarchicalPath();

            auto bitWidth = net.getType().getBitWidth();
            auto dataType = net.netType.getDataType().toString();
            auto typeStr  = net.getType().toString();

            collectSignalInfo(hierPath, bitWidth, typeStr);

            if (verbose) {
                fmt::println("[InstanceBodySymbol] [NET] {} bitwidth: {} dataType: {} type: {}", hierPath, bitWidth, dataType, typeStr);
            }
        }

        visitDefault(ast);
    }

  private:
    std::vector<std::string> enableModules;
    std::vector<std::string> disableModules;
    bool verbose                 = false;
    bool ignoreTrivialSignals    = true;
    bool ignoreUnderscoreSignals = true;

    void collectSignalInfo(std::string_view hierPath, size_t bitWidth, std::string typeStr) {
        if (hierPath.starts_with(".")) {
            // TODO: Handle this case
            return;
        }

        std::string_view signalName = getSignalName(hierPath);
        if (checkValid(signalName, typeStr)) {
            if (verbose) {
                fmt::println("==> {} {}", hierPath, signalName);
                std::vector<std::string> result = splitString(hierPath, '.');
                for (auto const &r : result) {
                    fmt::println("\t {} {}", r, typeStr);
                }
            }

            hierPathVec.emplace_back(hierPath);
            bitWidthVec.emplace_back(bitWidth);
            typeStrVec.emplace_back(typeStr);
        }
    }

    std::string_view getSignalName(std::string_view hierPath) {
        size_t lastDotPos = hierPath.rfind('.');
        if (lastDotPos != std::string::npos) {
            return hierPath.substr(lastDotPos + 1);
        }
        UNREACHABLE("signal name not found in hierPath: {}", hierPath);
    }

    bool checkValid(std::string_view signalName, std::string_view typeStr) {
        // Ignore some special signals which are automatically generated by Chisel
        if (ignoreTrivialSignals) {
            if (signalName.starts_with("_GEN_") || signalName.starts_with("_T_") || signalName.find("_WIRE_") != std::string::npos) {
                return false;
            }
        }

        if (ignoreUnderscoreSignals) {
            if (signalName.starts_with("_")) {
                return false;
            }
        }

        static constexpr std::string_view invalidTypePrefixes[] = {"void", "string", "integer", "int", "struct", "cg"};
        for (const auto &prefix : invalidTypePrefixes) {
            if (typeStr.starts_with(prefix)) {
                return false;
            }
        }

        return true;
    }
};

class WrappedDriver {
  public:
    sol::state lua;
    slang::driver::Driver driver;
    std::optional<bool> showHelp;
    std::optional<bool> quiet;
    std::optional<bool> ignoreTrivialSignals;
    std::optional<bool> ignoreUnderscoreSignals;
    std::optional<bool> verbose;
    std::optional<std::string> outfile;
    std::optional<std::string> signalDBFile;
    std::optional<bool> nocache;
    std::vector<std::string> enableModules;
    std::vector<std::string> disableModules;

    std::string cmdLineStr;
    std::string outputDir;
    std::vector<std::string> files;

    json metaInfoJson;
    std::string metaInfoFilePath;

    bool alreadyParsedCmdLine = false;

    WrappedDriver() {
        start = std::chrono::high_resolution_clock::now();

        const char *_veriluaHome = std::getenv("VERILUA_HOME");
        ASSERT(_veriluaHome != nullptr, "VERILUA_HOME is not set");
        std::string veriluaHome = _veriluaHome;

        lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::math, sol::lib::string, sol::lib::table, sol::lib::io, sol::lib::os);
        lua.safe_script_file(veriluaHome + "/src/signal_db_gen/signal_db_gen.lua");

        driver.addStandardArgs();
        driver.cmdLine.add("-h,--help", showHelp, "Display available options");
        driver.cmdLine.add("-o,--out", outfile, "Output file name", "<file>");
        driver.cmdLine.add("-s,--signal-db", signalDBFile, "Input signalDB file", "<file>");
        driver.cmdLine.add("-q,--quiet", quiet, "Quiet mode");
        driver.cmdLine.add("--it,--ignore-trivial-signals", ignoreTrivialSignals, "Ignore trivial signals");
        driver.cmdLine.add("--iu,--ignore-underscore-signals", ignoreUnderscoreSignals, "Ignore underscore signals");
        driver.cmdLine.add("--vb,--verbose", verbose, "Verbose mode");
        driver.cmdLine.add("--nc,--no-cache", nocache, "No cache");
        driver.cmdLine.add("--em,--enable-module", enableModules, "Enable modules(whitelist)", "<module>");
        driver.cmdLine.add("--dm,--disable-module", disableModules, "Disable modules(blacklist)", "<module>");
    }

    int parseCmdLine(int argc, char **argv) {
        if (!alreadyParsedCmdLine) {
            ASSERT(driver.parseCommandLine(argc, argv));
            alreadyParsedCmdLine = true;
        }

        if (showHelp) {
            std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText(fmt::format("dpi_exporter(verilua@{})", VERILUA_VERSION).c_str()));
            return 0;
        }

        // Get command line into string
        cmdLineStr.clear();
        for (int i = 0; i < argc; i++) {
            cmdLineStr += argv[i];
            cmdLineStr += " ";
        }

        // Can only have one of `--em` and `--dm`
        if (!enableModules.empty() && !disableModules.empty()) {
            PANIC("Can only have one of --em(--enable-modules) and --dm(--disable-modules)");
        }

        if (!checkForRegenerate()) {
            return 0;
        }

        return this->doParseCmdLine();
    }

    int parseCmdLine(std::string_view argList) {
        if (!alreadyParsedCmdLine) {
            ASSERT(driver.parseCommandLine(argList));
            alreadyParsedCmdLine = true;
        }

        if (showHelp) {
            std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText("dpi_exporter for verilua").c_str());
            return 0;
        }

        cmdLineStr = std::string(argList);

        if (!checkForRegenerate()) {
            return 0;
        }

        return this->doParseCmdLine();
    }

    void generateSignalDB() {
        ASSERT(alreadyParsed, "You must call `parseCmdLine` first!");

        SignalGetter getter(enableModules, disableModules, ignoreTrivialSignals.value_or(false), ignoreUnderscoreSignals.value_or(false), verbose.value_or(false));
        this->getCompilelation()->getRoot().visit(getter);

        auto ret = lua["insert_signal_db"](getter.hierPathVec.size(), getter.hierPathVec, getter.bitWidthVec, getter.typeStrVec);
        if (!ret.valid()) {
            sol::error err = ret;
            PANIC("[signal_db_gen] Failed to call lua function `insert_signal_db", err.what());
        }

        auto ret2 = lua["encode_signal_db"](outfile.value_or(DEFAULT_OUTPUT_FILE));
        if (!ret2.valid()) {
            sol::error err = ret2;
            PANIC("[signal_db_gen] Failed to call lua function `encode_signal_db", err.what());
        }

        auto end      = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
        fmt::println("[signal_db_gen] Time taken: {} ms", duration.count());

        metaInfoJson["outfile"]   = outfile.value_or(DEFAULT_OUTPUT_FILE);
        metaInfoJson["cmdLine"]   = cmdLineStr;
        metaInfoJson["filelist"]  = files;
        metaInfoJson["buildTime"] = get_current_time_as_string();

        // Write meta info into a json file, which can be used next time to check if the output is up to date
        std::ofstream o(metaInfoFilePath);
        o << metaInfoJson.dump(4) << std::endl;
        o.close();
    }

  private:
    bool alreadyParsed = false;
    std::chrono::high_resolution_clock::time_point start;

    bool checkForRegenerate() {
        outputDir        = std::filesystem::path(outfile.value_or(DEFAULT_OUTPUT_FILE)).parent_path();
        metaInfoFilePath = outputDir + "/signal_db_gen.meta.json";

        // Get files
        for (auto buffer : driver.sourceLoader.loadSources()) {
            auto fullpathName = driver.sourceManager.getFullPath(buffer.id);
            files.push_back(fullpathName.string());
        }

        if (nocache.value_or(false)) {
            fmt::println("[signal_db_gen] `--no-cache` is set, regenerating...");
            return true;
        }

        if (!std::filesystem::exists(outputDir)) {
            std::filesystem::create_directories(outputDir);
            fmt::println("[signal_db_gen] output dir not found, creating and regenerating...");
            return true;
        }

        if (!std::filesystem::exists(metaInfoFilePath)) {
            fmt::println("[signal_db_gen] meta info file not found, regenerating...");
            return true;
        }

        if (!std::filesystem::exists(outfile.value_or(DEFAULT_OUTPUT_FILE))) {
            fmt::println("[signal_db_gen] output file not found, regenerating...");
            return true;
        }

        std::ifstream metaInfoFile(metaInfoFilePath);
        if (!metaInfoFile.is_open()) {
            fmt::println("[signal_db_gen] failed to open meta info file, regenerating...");
            return true;
        }
        metaInfoJson = json::parse(metaInfoFile);
        metaInfoFile.close();

        std::string _outfile = metaInfoJson["outfile"];
        if (_outfile != outfile.value_or(DEFAULT_OUTPUT_FILE)) {
            fmt::println("[signal_db_gen] outfile changed, regenerating...");
            return true;
        }

        if (metaInfoJson["cmdLine"] != cmdLineStr) {
            fmt::println("[signal_db_gen] cmdLine changed, regenerating...");
            return true;
        }

        for (const auto &file : files) {
            if (isFileNewer(file, outfile.value_or(DEFAULT_OUTPUT_FILE))) {
                fmt::println("[signal_db_gen] `{}` is newer than `{}`, regenerating...", file, outfile.value_or(DEFAULT_OUTPUT_FILE));
                return true;
            }
        }

        if (metaInfoJson["filelist"].get<std::vector<std::string>>() != files) {
            fmt::println("[signal_db_gen] filelist changed, regenerating...");
            return true;
        }

        fmt::println("[signal_db_gen] up to date, skipping...");
        return false;
    }

    int doParseCmdLine() {
        if (signalDBFile.has_value()) {
            // Read signal db file and print it
            auto ret = lua["print_signal_db"](signalDBFile.value());
            if (!ret.valid()) {
                sol::error err = ret;
                PANIC("Failed to call lua function `print_signal_db", err.what());
            }
            return 0;
        }

        size_t fileCount = 0;
        for (auto buffer : driver.sourceLoader.loadSources()) {
            fileCount++;
            auto fullpathName = driver.sourceManager.getFullPath(buffer.id);

            if (!quiet.has_value() || !quiet.value()) {
                fmt::println("[signal_db_gen] [{}] get file: {}", fileCount, fullpathName.string());
                fflush(stdout);
            }
        }

        ASSERT(driver.processOptions());
        ASSERT(driver.parseAllSources());
        ASSERT(driver.reportParseDiags());

        alreadyParsed = true;

        return 1;
    }

    std::unique_ptr<slang::ast::Compilation> getCompilelation() {
        ASSERT(alreadyParsed, "You must call `parseCmdLine` first!");
        bool compileSuccess = driver.runFullCompilation(quiet.value_or(false));
        ASSERT(compileSuccess);
        return driver.createCompilation();
    }
};

extern "C" void signal_db_gen_main(const char *argList) {
    try {
        WrappedDriver wDriver;

        // Parse command line to get `outfile` option
        ASSERT(wDriver.driver.parseCommandLine(std::string_view(argList)));
        wDriver.alreadyParsedCmdLine = true;

        std::string lockfilePath = wDriver.outfile.value_or(DEFAULT_OUTPUT_FILE) + ".lock";
        try {
            FileLock lock(lockfilePath);
            int ret = wDriver.parseCmdLine(std::string_view(argList));
            if (ret == 1) {
                wDriver.generateSignalDB();
            }
        } catch (const std::exception &e) {
            PANIC("[signal_db_gen] Failed to lock file", lockfilePath, e.what());
        };
    } catch (const std::exception &e) {
        fmt::println(stderr, "[signal_db_gen] {}", e.what());
    }
}

#ifndef SO_LIB
int main(int argc, char **argv) {
    try {
        OS::setupConsole();
        WrappedDriver wDriver;

        // Parse command line to get `outfile` option
        ASSERT(wDriver.driver.parseCommandLine(argc, argv));
        wDriver.alreadyParsedCmdLine = true;

        std::string lockfilePath = wDriver.outfile.value_or(DEFAULT_OUTPUT_FILE) + ".lock";
        try {
            FileLock lock(lockfilePath);
            int ret = wDriver.parseCmdLine(argc, argv);
            if (ret == 1) {
                wDriver.generateSignalDB();
            }
        } catch (const std::exception &e) {
            PANIC("[signal_db_gen] Failed to lock file", lockfilePath, e.what());
        };
    } catch (const std::exception &e) {
        fmt::println(stderr, "[signal_db_gen] {}", e.what());
        return -1;
    }
    return 0;
}
#endif

#include "dpi_exporter.h"
#include "exporter_rewriter.h"
#include "render_dpi_file.h"
#include "signal_info_getter.h"

using json   = nlohmann::json;
namespace fs = std::filesystem;

class DPIExporter {
  private:
    slang_common::Driver driver;

    std::vector<std::string> files;
    std::vector<std::string> tmpFiles;
    std::vector<std::string> _files;
    std::optional<std::string> _configFile;
    std::optional<std::string> _outdir;
    std::optional<std::string> _workdir;
    std::optional<std::string> _dpiFile;
    std::optional<std::string> _topClock;
    std::optional<std::string> _sampleEdge;
    std::optional<std::string> insertModuleName;
    std::optional<bool> _distributeDPI;
    std::optional<bool> _quiet;
    std::optional<bool> nocache;
    std::optional<bool> showHelp;

    std::string configFile;
    std::string configFileContent;
    std::string outdir;
    std::string workdir;
    std::string dpiFilePath;
    std::string topModuleName;
    std::string topClock;
    std::string sampleEdge;
    std::string cmdLineStr;
    bool distributeDPI;
    bool quiet;

    json metaInfoJson;
    std::string metaInfoFilePath;

    bool checkForRegenerate() {
        if (!std::filesystem::exists(workdir)) {
            std::filesystem::create_directories(workdir);
            fmt::println("[dpi_exporter] workdir not found, creating and regenerating...");
            return true;
        }

        if (nocache.value_or(false)) {
            return true;
        }

        if (!std::filesystem::exists(metaInfoFilePath)) {
            fmt::println("[dpi_exporter] meta info file not found, regenerating...");
            return true;
        }

        if (!std::filesystem::exists(dpiFilePath)) {
            fmt::println("[dpi_exporter] dpi file not found, regenerating...");
            return true;
        }

        std::ifstream metaInfoFile(metaInfoFilePath);
        if (!metaInfoFile.is_open()) {
            fmt::println("[dpi_exporter] failed to open meta info file, regenerating...");
            return true;
        } else {
            metaInfoJson = json::parse(metaInfoFile);
            metaInfoFile.close();
        }

        std::string _dpiFilePath = metaInfoJson["dpiFilePath"];
        if (_dpiFilePath != dpiFilePath) {
            fmt::println("[dpi_exporter] dpi file path changed, regenerating...");
            return true;
        }

        if (metaInfoJson["cmdLine"] != cmdLineStr) {
            fmt::println("[dpi_exporter] cmdLine changed, regenerating...");
            return true;
        }

        for (const auto &file : files) {
            if (slang_common::file_manage::isFileNewer(file, _dpiFilePath)) {
                fmt::println("[dpi_exporter] `{}` is newer than `{}`, regenerating...", file, _dpiFilePath);
                return true;
            }
        }

        if (metaInfoJson["filelist"].get<std::vector<std::string>>() != files) {
            fmt::println("[dpi_exporter] filelist changed, regenerating...");
            return true;
        }

        if (metaInfoJson["configFileContent"] != configFileContent) {
            fmt::println("[dpi_exporter] config file changed, regenerating...");
            return true;
        }

        return false;
    }

    std::vector<ConciseSignalPattern> extractConfigInfo() {
        sol::state lua;
        lua.open_libraries(sol::lib::base);
        lua.open_libraries(sol::lib::string);
        lua.open_libraries(sol::lib::table);
        lua.open_libraries(sol::lib::math);
        lua.open_libraries(sol::lib::io);
        lua.script(R"(
local append = table.insert
local count = 0
patterns_data = {}

function add_pattern(params)
    local name = params.name or "UNKNOWN_" .. count
    local module = assert(params.module, "[add_pattern] module is nil")
    local signals = params.signals or ""
    local writable_signals = params.writable_signals or ""
    local disable_signals = params.disable_signals or ""
    local sensitive_signals = params.sensitive_signals or ""
    local clock = params.clock or ""
    local writable = params.writable or false
    local disable = params.disable or false

    assert(not(disable and writable), "[add_pattern] disable and writable cannot be both `true`")

    -- replace ` ` with `_` in the name
    name = name:gsub(" ", "_")

    append(patterns_data, {
        name = name,
        module = module,
        signals = signals,
        writable_signals = writable_signals,
        disable_signals = disable_signals,
        sensitive_signals = sensitive_signals,
        clock = clock,
        writable = writable,
        disable = disable
    })
    count = count + 1
end

)");
        lua.script_file(configFile);

        std::vector<ConciseSignalPattern> conciseSignalPatternVec;

        sol::table patternsData = lua["patterns_data"];
        patternsData.for_each([&](sol::object key, sol::object value) {
            sol::table patternData       = value.as<sol::table>();
            std::string name             = patternData["name"].get<std::string>();
            std::string module           = patternData["module"].get<std::string>();
            std::string clock            = patternData["clock"].get<std::string>();
            std::string signals          = patternData["signals"].get<std::string>();
            std::string writableSignals  = patternData["writable_signals"].get<std::string>();
            std::string disableSignals   = patternData["disable_signals"].get<std::string>();
            std::string sensitiveSignals = patternData["sensitive_signals"].get<std::string>(); // TODO:

            if (!quiet) {
                fmt::println("[dpi_exporter] get pattern:");
                fmt::println("\tname: {}", name);
                fmt::println("\tmodule: {}", module);
                fmt::println("\tclock: {}", clock);
                fmt::println("\tsignals: {}", signals);
                fmt::println("\twritable_signals: {}", writableSignals);
                fmt::println("\tdisable_signals: {}", disableSignals);
                fmt::println("\tsensitive_signals: {}", sensitiveSignals);
                fmt::println("\n");
                fflush(stdout);
            }

            conciseSignalPatternVec.emplace_back(ConciseSignalPattern{name, module, clock == "" ? DEFAULT_CLOCK_NAME : clock, signals, writableSignals, disableSignals, sensitiveSignals});
        });

        return conciseSignalPatternVec;
    }

  public:
    DPIExporter() : driver("dpi_exporter") {
        driver.addStandardArgs();

        driver.cmdLine.add("--fl,--filelist", _files, "input file or filelist", "<file/filelist>");
        driver.cmdLine.add("-c,--config", _configFile, "`Lua` file that contains the module info and the corresponding signal info", "<lua file>");
        driver.cmdLine.add("--od,--out-dir", _outdir, "output directory", "<directory>");
        driver.cmdLine.add("--wd,--work-dir", _workdir, "working directory", "<directory>");
        driver.cmdLine.add("--df,--dpi-file", _dpiFile, "name of the generated DPI file", "<file name>");
        driver.cmdLine.add("--tc,--top-clock", _topClock, "clock signal of the top-level module", "<name>");
        driver.cmdLine.add("--dd,--distribute-dpi", _distributeDPI, "distribute DPI functions"); // TODO: not supported yet
        driver.cmdLine.add("--se,--sample-edge", _sampleEdge, "sample edge of the clock signal");
        driver.cmdLine.add("-q,--quiet", _quiet, "quiet mode, print only necessary info");
        driver.cmdLine.add("--nc,--no-cache", nocache, "do not use cache files");
        driver.cmdLine.add("--im,--insert-module-name", insertModuleName, "module namne of the DPI function(available when distributeDPI is FALSE)", "<name>"); // ! make sure tha the inserted module has only one instance
    }

    int parseCommandLine(int argc, char **argv) {
        ASSERT(driver.parseCommandLine(argc, argv));

        if (_configFile->empty()) {
            PANIC("No config file specified! please use -c/--config <lua file>");
        }

        configFile       = fs::absolute(_configFile.value()).string();
        outdir           = fs::absolute(_outdir.value_or(DEFAULT_OUTPUT_DIR)).string();
        workdir          = fs::absolute(_workdir.value_or(DEFAULT_WORK_DIR)).string();
        topClock         = _topClock.value_or(DEFAULT_CLOCK_NAME);
        sampleEdge       = _sampleEdge.value_or(DEFAULT_SAMPLE_EDGE);
        distributeDPI    = _distributeDPI.value_or(false);
        quiet            = _quiet.value_or(false);
        metaInfoFilePath = outdir + "/dpi_exporter.meta.json";
        dpiFilePath      = outdir + "/" + _dpiFile.value_or(DEFAULT_DPI_FILE_NAME);
        fmt::println("[dpi_exporter]\n\tconfigFile: {}\n\tdpiFileName: {}\n\toutdir: {}\n\tworkdir: {}\n\tdistributeDPI: {}\n\tquiet: {}\n", configFile, _dpiFile.value_or(DEFAULT_DPI_FILE_NAME), outdir, workdir, distributeDPI, quiet);

        driver.setVerbose(!quiet);

        configFileContent = [&]() {
            std::ifstream configFileStream(configFile);
            if (!configFileStream.is_open()) {
                PANIC("Failed to open config file: {}", configFile);
            }
            std::stringstream buffer;
            buffer << configFileStream.rdbuf();
            std::string content = buffer.str();
            // Replace newlines with spaces
            std::replace(content.begin(), content.end(), '\n', ' ');
            return content;
        }();

        if (distributeDPI) {
            ASSERT(insertModuleName->empty(), "`insertModuleName` should be empty when `distributeDPI` is TRUE");
        }

        topModuleName = driver.tryGetTopModuleName().value_or("");

        ASSERT(sampleEdge == "posedge" || sampleEdge == "negedge", "Invalid sample edge '{}', should be either 'posedge' or 'negedge'", sampleEdge);

        for (const auto &file : _files) {
            if (file.ends_with(".f")) {
                // Parse filelist
                std::vector<std::string> fileList = parseFileList(file);
                for (const auto &listedFile : fileList) {
                    driver.addFile(listedFile);
                }
            } else {
                driver.addFile(file);
            }
        }

        // Get command line into string
        cmdLineStr.clear();
        for (int i = 0; i < argc; i++) {
            cmdLineStr += argv[i];
            cmdLineStr += " ";
        }

        return 1;
    }

    void generate() {
        if (!this->checkForRegenerate()) {
            fmt::println("[dpi_exporter] No need to regenerate, using cache files");
            return;
        }

        driver.loadAllSources([this](std::string_view file) -> std::string {
            auto f = fs::absolute(slang_common::file_manage::backupFile(file, this->workdir)).string();
            this->tmpFiles.push_back(f);
            return f;
        });

        ASSERT(driver.processOptions());
        ASSERT(driver.parseAllSources());
        ASSERT(driver.reportParseDiags());

        std::shared_ptr<SyntaxTree> tree = driver.getSingleSyntaxTree();

        auto compilation = driver.createAndReportCompilation(false);
        if (topModuleName == "") {
            topModuleName = compilation->getRoot().topInstances[0]->name;
            fmt::println("[dpi_exporter] `--top` is not set, use `{}` as top module name", topModuleName);
        }
        fmt::println("[dpi_exporter] topModuleName: {}", topModuleName);

        Config::getInstance().quietEnabled  = quiet;
        Config::getInstance().topModuleName = topModuleName;
        Config::getInstance().sampleEdge    = sampleEdge;

        // Get DPIExporterInfoVec from the provided lua config file
        auto conciseSignalPatternVec = this->extractConfigInfo();
        ASSERT(!conciseSignalPatternVec.empty(), "No signal pattern found in the config file");

        // Get SignalGroupVec from the provided conciseSignalPatternVec
        std::vector<SignalGroup> signalGroupVec;
        for (auto &cpattern : conciseSignalPatternVec) {
            fmt::println("\n[dpi_exporter] SignalGroup.name: {}, SignalGroup.moduleName: {}", cpattern.name, cpattern.module);
            auto isTopModule = cpattern.module == topModuleName;
            auto getter      = SignalInfoGetter(cpattern, compilation.get(), isTopModule);
            tree->root().visit(getter);

            for (auto &hierPath : getter.shouldRemoveHierPaths) {
                fmt::println("\t\tshouldRemove: {}", hierPath);
                for (auto &sg : signalGroupVec) {
                    for (int i = 0; i < sg.signalInfoVec.size(); i++) {
                        if (sg.signalInfoVec[i].hierPath == hierPath) {
                            sg.signalInfoVec.erase(sg.signalInfoVec.begin() + i);
                            break;
                        }
                    }
                }
            }

            signalGroupVec.push_back(getter.signalGroup);
        }
        fmt::println("");

        // Rewrite the syntax tree(insert `dpi_exporter_tick` function into the top module)
        if (!distributeDPI) {
            auto rewriter = ExporterRewriter(insertModuleName.value_or(topModuleName), sampleEdge, topModuleName, topClock, signalGroupVec);
            auto newTree  = rewriter.transform(tree);

            fmt::println("[dpi_exporter] start rebuilding syntax tree");
            fflush(stdout);

            tree = driver.rebuildSyntaxTree(*newTree, !quiet);

            fmt::println("[dpi_exporter] done rebuilding syntax tree");
            fflush(stdout);
        } else {
            ASSERT(false, "TODO: distributeDPI is not supported yet!");
        }

        std::string dpiFileContent = renderDpiFile(signalGroupVec, topModuleName, distributeDPI, metaInfoFilePath);

        {
            fmt::println("[dpi_exporter] start generating dpi file, outdir: {}, dpiFilePath: {}", outdir, dpiFilePath);
            fflush(stdout);

            std::fstream dpiFuncFile;
            dpiFuncFile.open(dpiFilePath, std::ios::out);
            dpiFuncFile << dpiFileContent;
            dpiFuncFile.close();

            fmt::println("[dpi_exporter] finish generating dpi file, outdir: {}, dpiFilePath: {}", outdir, dpiFilePath);
            fflush(stdout);
        }

        {
            // The syntaxtree of the input rtl files has been changed, so we need to regenerate the new rtl files.
            fmt::println("[dpi_exporter] start generating new rtl files, outdir: {}", outdir);
            fflush(stdout);

            slang_common::file_manage::generateNewFile(SyntaxPrinter::printFile(*tree), outdir);

            fmt::println("[dpi_exporter] finish generating new rtl files, outdir: {}", outdir);
            fflush(stdout);
        }

        // Delete temporary files
        for (auto &file : tmpFiles) {
            DELETE_FILE(file);
        }

        // Print all valid signals
        int idx = 0;
        std::vector<std::string> portHierPathVec;
        for (auto &sg : signalGroupVec) {
            for (auto &s : sg.signalInfoVec) {
                idx++;

                if (!quiet) {
                    fmt::println("[{}] handleId:<{}> hierPath:<{}> signalName:<{}> typeStr:<{}> bitWidth:<{}>", idx, s.handleId, s.hierPath, s.signalName, s.vpiTypeStr, s.bitWidth);
                }

                portHierPathVec.emplace_back(s.hierPath);
            }
        }

        // Save the command line arguments and files into json file
        metaInfoJson["cmdLine"]           = cmdLineStr;
        metaInfoJson["filelist"]          = driver.getFiles();
        metaInfoJson["topModuleName"]     = topModuleName;
        metaInfoJson["dpiFilePath"]       = dpiFilePath;
        metaInfoJson["insertModuleName"]  = insertModuleName.value_or(topModuleName);
        metaInfoJson["configFileContent"] = configFileContent;
        metaInfoJson["exportedSignals"]   = portHierPathVec;

        // Write meta info into a json file, which can be used next time to check if the output is up to date
        std::ofstream o(metaInfoFilePath);
        o << metaInfoJson.dump(4) << std::endl;
        o.close();

        fmt::println("[dpi_exporter] FINISH!");
    }
};

int main(int argc, char **argv) {
    OS::setupConsole();
    DPIExporter dpiExporter;

    if (dpiExporter.parseCommandLine(argc, argv) == 0) {
        return 0;
    }

    dpiExporter.generate();

    return 0;
}

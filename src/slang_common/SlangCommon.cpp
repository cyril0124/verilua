#include "SlangCommon.h"

#include "slang/ast/ASTVisitor.h"
#include "slang/diagnostics/DiagnosticEngine.h"
#include "slang/diagnostics/TextDiagnosticClient.h"
#include "slang/numeric/Time.h"
#include "slang/parsing/Parser.h"
#include "slang/parsing/Preprocessor.h"
#include "slang/syntax/SyntaxPrinter.h"
#include <algorithm>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

using namespace slang;
using namespace slang::parsing;
using namespace slang::syntax;
using namespace slang::ast;

namespace slang_common {

// Print a syntax tree to text, re-parse it into a fresh SyntaxTree, and verify
// that no parse/compilation errors were introduced.  This is the core mechanism
// used by dpi_exporter and cov_exporter after rewriting RTL: the modified tree
// is serialized and re-parsed to produce a clean tree suitable for further
// processing or file output.
std::shared_ptr<SyntaxTree> rebuildSyntaxTree(const SyntaxTree &oldTree, bool printTree, int errorLimit, slang::SourceManager &sourceManager, const Bag &options) {
    auto oldTreeStr = SyntaxPrinter::printFile(oldTree);
    auto newTree    = SyntaxTree::fromFileInMemory(oldTreeStr, sourceManager, "slang_common::rebuildSyntaxTree"sv, "", options);

    auto reportAndAbort = [&](const slang::Diagnostics &diags, const char *phase) {
        auto hasError = std::any_of(diags.begin(), diags.end(), [](const auto &d) { return d.isError(); });
        if (!hasError)
            return false;

        DiagnosticEngine engine(sourceManager);
        engine.setErrorLimit(errorLimit);
        auto client = std::make_shared<TextDiagnosticClient>();
        engine.addClient(client);
        for (auto &diag : diags)
            engine.issue(diag);

        fmt::println(stderr, "[rebuildSyntaxTree] {} failed:", phase);
        fmt::println(stderr, "─────────────────────────────────────────────");
        fmt::println(stderr, "{}", client->getString());
        fmt::println(stderr, "─────────────────────────────────────────────");

        if (printTree) {
            fmt::println(stderr, "[rebuildSyntaxTree] source text that failed to rebuild:");
            fmt::println(stderr, "─────────────────────────────────────────────");
            fmt::println(stderr, "{}", oldTreeStr);
            fmt::println(stderr, "─────────────────────────────────────────────");
        }

        assert(false && "rebuildSyntaxTree() failed");
        return true; // unreachable
    };

    if (!newTree->diagnostics().empty()) {
        reportAndAbort(newTree->diagnostics(), "parse");
    } else {
        Compilation compilation(options);
        compilation.addSyntaxTree(newTree);
        auto diags = compilation.getAllDiagnostics();
        if (!diags.empty())
            reportAndAbort(diags, "compilation");
    }

    return newTree;
}

// ---------------------------------------------------------------------------
// file_manage — utilities for backing up and splitting RTL files
// ---------------------------------------------------------------------------
namespace file_manage {

// Create a backup copy of `inputFile` in `workdir`, wrapped with //BEGIN: and
// //END: markers so that generateNewFile() can later split it back out.
std::string backupFile(std::string_view inputFile, std::string workdir) {
    std::filesystem::path _workdir(workdir);
    std::filesystem::path path(inputFile);
    std::string targetFile = std::string(workdir) + "/" + path.filename().string() + ".bak";

    if (std::filesystem::exists(targetFile)) {
        std::filesystem::remove(targetFile);
    }
    std::filesystem::copy_file(inputFile, targetFile.c_str());

    // Insert marker before file head
    {
        std::ifstream inFile(targetFile);
        std::string content((std::istreambuf_iterator<char>(inFile)), std::istreambuf_iterator<char>());
        inFile.close();
        std::ofstream outFile(targetFile);
        outFile << fmt::format("//BEGIN:{}", inputFile) << "\n" << content;
    }
    // Insert marker after file end
    {
        std::ofstream outFile(targetFile, std::ios::app);
        outFile << "\n" << fmt::format("//END:{}", inputFile) << "\n";
    }

    return targetFile;
}

// Split a concatenated string (with //BEGIN: / //END: markers) into individual
// files under `newPath`.  Used after SyntaxPrinter::printFile() produces a
// single string containing multiple rewritten source files.
void generateNewFile(const std::string &content, const std::string &newPath) {
    std::istringstream stream(content);
    std::string line;
    std::string currentFile;
    std::ofstream outFile;
    std::vector<std::string> buffer;

    if (!newPath.empty()) {
        if (!std::filesystem::exists(newPath)) {
            std::filesystem::create_directories(newPath);
        }
    }

    auto flushBuffer = [&]() {
        if (!buffer.empty() && outFile.is_open()) {
            for (const auto &l : buffer) {
                outFile << l << '\n';
            }
            buffer.clear();
        }
    };

    while (std::getline(stream, line)) {
        if (line.find("//BEGIN:") == 0) {
            flushBuffer();
            currentFile = line.substr(8);

            std::filesystem::path path = currentFile;
            if (!newPath.empty()) {
                currentFile = newPath + "/" + path.filename().string();
            }

            outFile.open(currentFile, std::ios::out | std::ios::trunc);
            if (!outFile.is_open()) {
                std::cerr << "Failed to open file: " << currentFile << std::endl;
                assert(false);
            }
        } else if (line.find("//END:") == 0) {
            flushBuffer();
            if (outFile.is_open()) {
                outFile.close();
            }
        } else {
            if (outFile.is_open()) {
                buffer.push_back(line);
                if (buffer.size() >= 10000) {
                    flushBuffer();
                }
            }
        }
    }

    flushBuffer();
    if (outFile.is_open()) {
        outFile.close();
    }
}

// Return true if file1 has a newer modification time than file2.
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

} // namespace file_manage

// ---------------------------------------------------------------------------
// Driver — wraps slang::driver::Driver with Verilua-specific defaults
// ---------------------------------------------------------------------------

Driver::Driver(std::string name) : cmdLine(driver.cmdLine) {
    this->name = name;
    this->driver.cmdLine.add("-h,--help", showHelp, "Display available options");
}

Driver::~Driver() {}

// Register standard command-line arguments shared across all Verilua tools
// (include paths, positional file arguments, .f file-list expansion, etc.)
void Driver::addStandardArgs() {
    driver.addStandardArgs();

    // Override slang's default -I handler so that include dirs are also
    // registered on the empty source manager used by rebuildSyntaxTree().
    driver.cmdLine.add(
        "-I,--include-directory,+incdir",
        [this](std::string_view value) {
            if (auto ec = this->driver.sourceManager.addUserDirectories(value)) {
                fmt::println("include directory '{}': {}", value, ec.message());
            }
            this->emptySourceManager.addUserDirectories(value);
            return "";
        },
        "Additional include search paths", "<dir-pattern>[,...]", CommandLineFlags::CommaList);

    driver.cmdLine.add(
        "--isystem",
        [this](std::string_view value) {
            if (auto ec = this->driver.sourceManager.addSystemDirectories(value)) {
                fmt::println("system include directory '{}': {}", value, ec.message());
            }
            this->emptySourceManager.addSystemDirectories(value);
            return "";
        },
        "Additional system include search paths", "<dir-pattern>[,...]", CommandLineFlags::CommaList);

    // Positional args: source files and .f file-lists
    driver.cmdLine.setPositional(
        [this](std::string_view value) {
            // Skip files with excluded extensions
            if (!this->driver.options.excludeExts.empty()) {
                if (size_t extIndex = value.find_last_of('.'); extIndex != std::string_view::npos) {
                    if (driver.options.excludeExts.count(std::string(value.substr(extIndex + 1))))
                        return "";
                }
            }

            // Expand .f file-lists
            if (value.ends_with(".f")) {
                std::ifstream infile(value.data());
                if (!infile) {
                    fmt::println("Failed to open file: {}", value);
                    assert(false);
                } else {
                    std::string line;
                    while (std::getline(infile, line)) {
                        if (!line.empty()) {
                            this->files.push_back(line);
                        }
                    }
                    infile.close();
                }
            }

            this->files.push_back(std::string(value));
            return "";
        },
        "files", slang::bitmask<slang::CommandLineFlags>{}, true);

    driver.cmdLine.add("-h,--help", showHelp, "Display available options");
}

bool Driver::parseCommandLine(int argc, char **argv) {
    auto success = driver.parseCommandLine(argc, argv);
    if (showHelp) {
        std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText(name).c_str());
        exit(0);
    }
    return success;
}

// Feed all collected source files into slang's source loader.
// An optional fileTransform callback can rewrite paths before loading
// (e.g. to redirect into a work directory).
void Driver::loadAllSources(std::function<std::string(std::string_view)> fileTransform) {
    auto totalFileCount = files.size();

    if (!verbose) {
        fmt::println("[{}] Loading {} files... ", name, totalFileCount);
    }

    for (int i = 0; i < totalFileCount; i++) {
        auto file = files[i];

        if (verbose) {
            fmt::println("[{}] [{}/{}] get file: {}", name, i + 1, totalFileCount, file);
            fflush(stdout);
        } else {
            fmt::print("\t{}/{} {:.2f}%\r", i + 1, totalFileCount, (double)(i + 1) / (double)totalFileCount * 100);
            fflush(stdout);
        }

        if (fileTransform == nullptr) {
            driver.sourceLoader.addFiles(std::string_view(file));
        } else {
            driver.sourceLoader.addFiles(std::string_view(fileTransform(file)));
        }
    }

    if (!verbose) {
        fmt::println("");
    }

    loadAllSourcesDone = true;
}

// Translate slang driver options into a Bag of parser/compilation options.
// This mirrors slang's internal Driver::processOptions but stores the result
// in our own Bag so that rebuildSyntaxTree() can reuse the same settings.
bool Driver::processOptions(bool singleUnit) {
    driver.options.singleUnit = singleUnit;
    bool success              = driver.processOptions();

    auto &options = driver.options;

    // Parser options
    {
        slang::driver::SourceOptions soptions;
        soptions.numThreads             = options.numThreads;
        soptions.singleUnit             = options.singleUnit == true;
        soptions.onlyLint               = options.lintMode();
        soptions.librariesInheritMacros = options.librariesInheritMacros == true;

        slang::parsing::PreprocessorOptions ppoptions;
        ppoptions.predefines      = options.defines;
        ppoptions.undefines       = options.undefines;
        ppoptions.predefineSource = "<command-line>";
        ppoptions.languageVersion = driver.languageVersion;
        if (options.maxIncludeDepth.has_value())
            ppoptions.maxIncludeDepth = *options.maxIncludeDepth;
        for (const auto &d : options.ignoreDirectives)
            ppoptions.ignoreDirectives.emplace(d);

        slang::parsing::LexerOptions loptions;
        loptions.languageVersion     = driver.languageVersion;
        loptions.enableLegacyProtect = options.enableLegacyProtect == true;
        if (options.maxLexerErrors.has_value())
            loptions.maxErrors = *options.maxLexerErrors;

        if (loptions.enableLegacyProtect)
            loptions.commentHandlers["pragma"]["protect"] = {CommentHandler::Protect};

        slang::parsing::ParserOptions poptions;
        poptions.languageVersion = driver.languageVersion;
        if (options.maxParseDepth.has_value())
            poptions.maxRecursionDepth = *options.maxParseDepth;

        bag.set(soptions);
        bag.set(ppoptions);
        bag.set(loptions);
        bag.set(poptions);
    }

    // Compilation options (mirrors slang's Driver::addCompilationOptions)
    {
        slang::ast::CompilationOptions coptions;
        coptions.flags           = slang::ast::CompilationFlags::None;
        coptions.languageVersion = driver.languageVersion;
        if (options.maxInstanceDepth.has_value())
            coptions.maxInstanceDepth = *options.maxInstanceDepth;
        if (options.maxGenerateSteps.has_value())
            coptions.maxGenerateSteps = *options.maxGenerateSteps;
        if (options.maxConstexprDepth.has_value())
            coptions.maxConstexprDepth = *options.maxConstexprDepth;
        if (options.maxConstexprSteps.has_value())
            coptions.maxConstexprSteps = *options.maxConstexprSteps;
        if (options.maxConstexprBacktrace.has_value())
            coptions.maxConstexprBacktrace = *options.maxConstexprBacktrace;
        if (options.maxInstanceArray.has_value())
            coptions.maxInstanceArray = *options.maxInstanceArray;
        if (options.maxUDPCoverageNotes.has_value())
            coptions.maxUDPCoverageNotes = *options.maxUDPCoverageNotes;
        if (options.errorLimit.has_value())
            coptions.errorLimit = *options.errorLimit * 2;

        for (auto &[flag, value] : options.compilationFlags) {
            if (value == true)
                coptions.flags |= flag;
        }

        for (auto &name : options.topModules)
            coptions.topModules.emplace(name);
        for (auto &opt : options.paramOverrides)
            coptions.paramOverrides.emplace_back(opt);
        for (auto &lib : options.libraryOrder)
            coptions.defaultLiblist.emplace_back(lib);

        if (options.minTypMax.has_value()) {
            coptions.minTypMax = *options.minTypMax;
        }

        if (options.timeScale.has_value())
            coptions.defaultTimeScale = slang::TimeScale::fromString(*options.timeScale);

        bag.set(coptions);
    }

    return success;
}

bool Driver::parseAllSources() {
    if (!loadAllSourcesDone) {
        assert(false && "loadAllSources() must be called before parseAllSources()");
    }

    parseAllSourcesDone = true;
    return driver.parseAllSources();
}

bool Driver::reportParseDiags() { return driver.reportParseDiags(); }

std::unique_ptr<slang::ast::Compilation> Driver::createCompilation() { return driver.createCompilation(); }

std::unique_ptr<slang::ast::Compilation> Driver::createAndReportCompilation(bool quiet) {
    if (!this->driver.runFullCompilation(quiet)) {
        assert(false && "runFullCompilation() failed");
    };
    auto compilation = this->createCompilation();
    return compilation;
}

std::shared_ptr<SyntaxTree> Driver::rebuildSyntaxTree(const SyntaxTree &oldTree, bool printTree, int errorLimit) { return slang_common::rebuildSyntaxTree(oldTree, printTree, errorLimit, this->getEmptySourceManager(), this->getBag()); }

// ---------------------------------------------------------------------------
// Helpers — symbol lookup and hierarchy traversal
// ---------------------------------------------------------------------------

// Look up the DefinitionSymbol for a module declaration syntax node.
const DefinitionSymbol *getDefSymbol(std::shared_ptr<SyntaxTree> tree, const ModuleDeclarationSyntax &syntax) {
    Compilation compilation;
    compilation.addSyntaxTree(tree);

    return compilation.getDefinition(static_cast<const Scope &>(compilation.getRoot()), syntax);
}

// Create a default instance of the module described by `syntax`.
const InstanceSymbol *getInstSymbol(Compilation &compilation, const ModuleDeclarationSyntax &syntax) {
    auto def = compilation.getDefinition(static_cast<const Scope &>(compilation.getRoot()), syntax);
    return &InstanceSymbol::createDefault(compilation, def->as<DefinitionSymbol>());
}

// Walk the elaborated design and collect all hierarchical paths where
// `moduleName` is instantiated.
std::vector<std::string> getHierPaths(slang::ast::Compilation &compilation, std::string moduleName) {
    struct HierPathGetter : public slang::ast::ASTVisitor<HierPathGetter, false, false> {
        std::string moduleName;
        std::vector<std::string> hierPaths;
        HierPathGetter(std::string moduleName) : moduleName(moduleName) {}

        void handle(const InstanceSymbol &inst) {
            auto _moduleName = inst.getDefinition().name;

            if (_moduleName == moduleName) {
                std::string hierPath = inst.getHierarchicalPath();
                hierPaths.emplace_back(hierPath);
            } else {
                visitDefault(inst);
            }
        }
    };

    HierPathGetter visitor(moduleName);
    compilation.getRoot().visit(visitor);
    return visitor.hierPaths;
}

std::vector<std::string> getHierPaths(slang::ast::Compilation *compilation, std::string moduleName) { return getHierPaths(*compilation, moduleName); }

std::vector<std::string> getHierPaths(slang::ast::Compilation *compilation, std::string_view moduleName) { return getHierPaths(*compilation, std::string(moduleName)); }

} // namespace slang_common

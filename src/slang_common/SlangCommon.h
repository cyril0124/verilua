#pragma once

#include "fmt/core.h"
#include "slang/ast/Compilation.h"
#include "slang/ast/symbols/InstanceSymbols.h"
#include "slang/driver/Driver.h"
#include "slang/syntax/AllSyntax.h"
#include "slang/syntax/SyntaxTree.h"
#include "slang/syntax/SyntaxVisitor.h"
#include "slang/text/SourceManager.h"
#include "slang/util/Bag.h"
#include "slang/util/CommandLine.h"
#include <fmt/ranges.h>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

using namespace slang;
using namespace slang::parsing;
using namespace slang::syntax;
using namespace slang::ast;

namespace slang_common {

namespace file_manage {
std::string backupFile(std::string_view inputFile, std::string workdir);
bool isFileNewer(const std::string &file1, const std::string &file2);
void generateNewFile(const std::string &content, const std::string &newPath);
} // namespace file_manage

class Driver {
  private:
    slang::SourceManager emptySourceManager;
    slang::Bag bag;
    std::vector<std::string> files;
    std::optional<bool> showHelp;
    std::string name;
    bool loadAllSourcesDone  = false;
    bool parseAllSourcesDone = false;
    bool verbose             = false;

  public:
    slang::driver::Driver driver;
    slang::CommandLine &cmdLine;

    Driver(std::string name = "Unknown");
    ~Driver();

    void setName(std::string name) { this->name = name; }
    void setVerbose(bool verbose) { this->verbose = verbose; }
    void addFile(std::string_view file) { files.push_back(std::string(file)); }
    void addFiles(std::vector<std::string> files) {
        for (auto &file : files) {
            this->files.push_back(file);
        }
    }

    std::vector<std::string> &getFiles() { return files; }
    slang::SourceManager &getEmptySourceManager() { return emptySourceManager; }
    slang::driver::Driver &getInternalDriver() { return driver; }
    slang::Bag &getBag() { return bag; }

    std::optional<std::string> tryGetTopModuleName() {
        if (!driver.options.topModules.empty()) {
            if (driver.options.topModules.size() > 1) {
                fmt::println("topModules: {}", fmt::to_string(fmt::join(driver.options.topModules, ",")));
                assert(false && "Multiple top modules specified!");
            }
            return std::optional<std::string>(driver.options.topModules[0]);
        }
        return std::nullopt;
    }

    std::shared_ptr<slang::syntax::SyntaxTree> getSingleSyntaxTree() {
        assert(parseAllSourcesDone && "parseAllSources() must be called before getSingleSyntaxTree()");

        if (driver.syntaxTrees.size() != 1) {
            fmt::println("driver.syntaxTrees.size(): {}", driver.syntaxTrees.size());
            assert(false && "Multiple syntax trees found!");
        }
        return driver.syntaxTrees[0];
    }

    void addStandardArgs();
    bool parseCommandLine(int argc, char **argv);
    void loadAllSources(std::function<std::string(std::string_view)> fileTransform = nullptr);
    bool processOptions(bool singleUnit = true);
    bool parseAllSources();
    bool reportParseDiags();
    std::unique_ptr<slang::ast::Compilation> createCompilation();
    std::unique_ptr<slang::ast::Compilation> createAndReportCompilation(bool quiet = false);
    std::shared_ptr<SyntaxTree> rebuildSyntaxTree(const SyntaxTree &oldTree, bool printTree = false, int errorLimit = 0);
};

const DefinitionSymbol *getDefSymbol(std::shared_ptr<SyntaxTree> tree, const ModuleDeclarationSyntax &syntax);

const InstanceSymbol *getInstSymbol(Compilation &compilation, const ModuleDeclarationSyntax &syntax);

std::vector<std::string> getHierPaths(slang::ast::Compilation &compilation, std::string moduleName);

std::vector<std::string> getHierPaths(slang::ast::Compilation *compilation, std::string moduleName);

std::vector<std::string> getHierPaths(slang::ast::Compilation *compilation, std::string_view moduleName);

} // namespace slang_common

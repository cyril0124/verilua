#include "fmt/base.h"
#include "fmt/color.h"
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
#include <cstddef>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

using namespace slang;
using namespace slang::ast;

namespace fs = std::filesystem;

std::vector<std::string> splitString(std::string_view input, char delimiter) {
    std::vector<std::string> tokens;

    size_t tokenCount = std::count(input.begin(), input.end(), delimiter) + 1;
    tokens.reserve(tokenCount);

    const char* ptr = input.data();
    const char* endPtr = ptr + input.size();
    const char* tokenStart = ptr;

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
    std::vector<std::vector<std::string>> hierPathVec;

    SignalGetter() {}

    void handle(const NetSymbol &ast) {
        std::string hierPath;
        ast.getHierarchicalPath(hierPath);
        processHierPath(hierPath);
        // visitDefault(ast);
    }

    void handle(const VariableSymbol &ast) {
        std::string hierPath;
        ast.getHierarchicalPath(hierPath);
        processHierPath(hierPath);
        // visitDefault(ast);
    }
private:
    void processHierPath(std::string_view hierPath) {
        std::vector<std::string> result = splitString(hierPath, '.');
        if(checkValid(result.back())) {
            hierPathVec.emplace_back(result);
        }
    }

    bool checkValid(std::string_view signalName) {
        // Ignore some special signals which are automatically generated by Chisel
        if(signalName.starts_with("_GEN_") || signalName.starts_with("_T_") || signalName.find("_WIRE_") != std::string::npos) {
            return false;
        }
        return true;
    }
};

class WrappedDriver {
public:
    sol::state lua;
    slang::driver::Driver driver;
    std::optional<bool> showHelp;
    std::optional<std::string> outfile;

    WrappedDriver() {
        lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::math, sol::lib::string, sol::lib::table, sol::lib::io);

        driver.addStandardArgs();
        driver.cmdLine.add("-h,--help", showHelp, "Display available options");
        driver.cmdLine.add("-o,--out", outfile, "Output file name", "<file>");
    }

    int parseCmdLine(int argc, char **argv) {
        ASSERT(driver.parseCommandLine(argc, argv));

        if (showHelp) {
            std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText("dpi_exporter for verilua").c_str());
            return 0;
        }

        this->_parseCmdLine();

        return 1;
    }

    int parseCmdLine(std::string_view argList) {
        ASSERT(driver.parseCommandLine(argList));

        if (showHelp) {
            std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText("dpi_exporter for verilua").c_str());
            return 0;
        }

        this->_parseCmdLine();
        
        return 1;
    }

    std::unique_ptr<slang::ast::Compilation> getCompilelation() {
        ASSERT(alreadyParsed, "You must call `parseCmdLine` first!");
        auto compilation    = driver.createCompilation();
        bool compileSuccess = driver.reportCompilation(*compilation, false);
        ASSERT(compileSuccess);

        return compilation;
    }

    void generateSignalDB() {
        ASSERT(alreadyParsed, "You must call `parseCmdLine` first!");
        
        lua.script(R"(
            _G.sb = require "string.buffer"
            _G.signal_db_table = {}

            function insert_signal_db(hier_path_vec)
                local curr = signal_db_table
                local end_idx = #hier_path_vec

                for i, v in ipairs(hier_path_vec) do
                    if i == end_idx then
                        table.insert(curr, v)
                    else
                        if not curr[v] then
                            curr[v] = {}
                        end
                        curr = curr[v]
                    end
                end
            end
        )");

        SignalGetter getter;
        this->getCompilelation()->getRoot().visit(getter);
        for (auto const &hierPath : getter.hierPathVec) {
            lua["insert_signal_db"](hierPath);
        }

        std::string outFile = outfile.value_or("signal_db.ldb");

        lua.script(fmt::format(R"(
            local encoded_table = sb.encode(signal_db_table)
            local file = io.open("{}", "w")
            if file then
                file:write(encoded_table)
                file:close()
            else
                error("[encode] Failed to open '{}'")
            end
        )", outFile, outFile));
    }

private:
    bool alreadyParsed = false;

    void _parseCmdLine() {
        std::string topModuleName = "";

        if (!driver.options.topModules.empty()) {
            if (driver.options.topModules.size() > 1) {
                PANIC("Multiple top-level modules specified!", driver.options.topModules);
            }
            topModuleName = driver.options.topModules[0];
        }

        size_t fileCount = 0;
        for (auto buffer : driver.sourceLoader.loadSources()) {
            fileCount++;
            auto fullpathName = driver.sourceManager.getFullPath(buffer.id);

            fmt::println("[signal_db_gen] [{}] get file: {}", fileCount, fullpathName.string());
            fflush(stdout);
        }

        ASSERT(driver.processOptions());
        driver.options.singleUnit = true;

        ASSERT(driver.parseAllSources());
        ASSERT(driver.reportParseDiags());
        ASSERT(driver.syntaxTrees.size() == 1, "Only one SyntaxTree is expected", driver.syntaxTrees.size());
        
        alreadyParsed = true;
    }
};

#ifdef SO_LIB
extern "C" void signal_db_gen_main(const char *argList) {
#else
int main(int argc, char **argv) {
    OS::setupConsole();
#endif

    WrappedDriver driver;
#ifdef SO_LIB
    int ret = driver.parseCmdLine(std::string_view(argList));
#else
    int ret = driver.parseCmdLine(argc, argv);
#endif

    if(ret == 1) {
        driver.generateSignalDB();
    }

#ifndef SO_LIB
    return ret;
#endif
}
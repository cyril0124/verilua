#pragma once

#include "SemanticModel.h"
#include "SlangCommon.h"
#include "fmt/base.h"
#include "fmt/color.h"
#include "inja/inja.hpp"
#include "libassert/assert.hpp"
#include "slang/ast/ASTVisitor.h"
#include "slang/ast/Compilation.h"
#include "slang/ast/Symbol.h"
#include "slang/driver/Driver.h"
#include "slang/syntax/AllSyntax.h"
#include "slang/syntax/SyntaxPrinter.h"
#include "slang/syntax/SyntaxTree.h"
#include "slang/util/Util.h"
#include "sol/sol.hpp"
#include <cstddef>
#include <cstdio>
#include <filesystem>
#include <fmt/ranges.h>
#include <fstream>
#include <memory>
#include <nlohmann/json.hpp>
#include <regex>
#include <span>
#include <string>
#include <unordered_set>
#include <vector>

// ===========================================================
// Optimization configs
// ===========================================================
// #define NO_STD_COPY

#define DEFAULT_OUTPUT_DIR ".dpi_exporter"
#define DEFAULT_WORK_DIR ".dpi_exporter"
#define DEFAULT_DPI_FILE_NAME "dpi_func.cpp"

#define ANSI_COLOR_RED "\x1b[31m"
#define ANSI_COLOR_YELLOW "\x1b[33m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_GREEN "\x1b[32m"
#define ANSI_COLOR_RESET "\x1b[0m"

#define DELETE_FILE(filePath)                                                                                                                                                                                                                                                                                                                                                                                  \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        if (std::filesystem::exists(filePath)) {                                                                                                                                                                                                                                                                                                                                                               \
            std::filesystem::remove(filePath);                                                                                                                                                                                                                                                                                                                                                                 \
        }                                                                                                                                                                                                                                                                                                                                                                                                      \
    } while (0)

inline std::vector<std::string> parseFileList(const std::string &filePath) {
    std::vector<std::string> files;
    std::ifstream infile(filePath);
    std::string line;

    while (std::getline(infile, line)) {
        if (!line.empty()) {
            files.push_back(line);
        }
    }

    return files;
}

inline sol::object getLuaTableItemOrFailed(sol::table &table, const std::string &key) {
    sol::object obj = table[key];
    if (obj.get_type() == sol::type::nil) {
        throw std::runtime_error("[logic_fuzzer] (nil) Failed to get lua table entry: " + key);
    }
    return obj;
}

inline uint32_t coverWith32(uint32_t size) { return (size + 31) / 32; }
inline uint32_t coverWith4(uint32_t size) { return (size + 3) / 4; }

inline uint32_t log2Ceil(uint32_t x) {
    if (x == 0) {
        PANIC("log2Ceil(0)");
    }
    return std::ceil(std::log2(x));
}

using PortInfo = struct {
    std::string name;
    std::string direction;
    bitwidth_t bitWidth;
    uint64_t handleId;
    bool writable;
    std::string typeStr;
    std::string hierPathName;
    std::string hierPathNameDot;
};

using DPIExporterInfo = struct {
    std::string moduleName;
    std::string clock;
    std::vector<std::string> signalPatternVec;
    std::vector<std::string> writableSignalPatternVec;
    std::vector<std::string> disableSignalPatternVec;
    bool isTopModule;
};

class HierPathGetter : public ASTVisitor<HierPathGetter, false, false> {
  public:
    std::string moduleName;
    std::string instName;

  public:
    std::vector<std::string> hierPaths;

    HierPathGetter(std::string moduleName, std::string instName) : moduleName(moduleName), instName(instName) {}

    void handle(const InstanceSymbol &inst) {
        auto _moduleName = inst.getDefinition().name;
        auto _instName   = inst.name;

        if (_instName == instName && _moduleName == moduleName) {
            std::string hierPath = "";
            inst.getHierarchicalPath(hierPath);
            // fmt::println("[HierPathGetter] moduleName:<{}> instName:<{}> hierPath:<{}>", _moduleName, _instName, hierPath);

            hierPaths.emplace_back(hierPath);
        } else {
            visitDefault(inst);
        }
    }
};
#pragma once

#include "SlangCommon.h"
#include "fmt/base.h"
#include "fmt/color.h"
#include "inja/inja.hpp"
#include "libassert/assert.hpp"
#include "slang/ast/ASTVisitor.h"
#include "slang/ast/SemanticFacts.h"
#include "slang/ast/Symbol.h"
#include "slang/ast/symbols/InstanceSymbols.h"
#include "slang/ast/symbols/PortSymbols.h"
#include "slang/ast/symbols/VariableSymbols.h"
#include "slang/driver/Driver.h"
#include "slang/parsing/TokenKind.h"
#include "slang/syntax/AllSyntax.h"
#include <array>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <nlohmann/json.hpp>
#include <optional>
#include <ostream>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

#ifndef VERILUA_VERSION
#define VERILUA_VERSION "Unknown"
#endif

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

inline std::string replaceString(std::string str, const char *pattern, const char *replacement) {
    size_t pos = str.find(pattern);
    if (pos != std::string::npos) {
        return str.replace(pos, std::string(pattern).length(), replacement);
    }
    return str;
};

// clang-format off
inline bool containsString(std::string str, std::string pattern) {
    return str.find(pattern) != std::string::npos;
}

inline std::string replaceString(std::string str, std::string pattern, std::string replacement) {
    return replaceString(str, pattern.c_str(), replacement.c_str());
};

inline std::string replaceMultipleSpaces(std::string s) {
    return std::regex_replace(s, std::regex("\\s+"), " ");
}

inline std::string trim(std::string s) {
    return std::regex_replace(
        std::regex_replace(s, std::regex("\\s+"), " "), 
        std::regex("^\\s+|\\s+$"), ""
    );
}
// clang-format on

inline std::string joinStrVec(const std::vector<std::string> &vec, const std::string &delimiter) {
    if (vec.empty()) {
        return "";
    }
    return fmt::to_string(fmt::join(vec, delimiter));
}

inline bool isFileNewer(const std::string &file1, const std::string &file2) {
    try {
        auto time1 = std::filesystem::last_write_time(file1);
        auto time2 = std::filesystem::last_write_time(file2);

        return time1 > time2;
    } catch (const std::filesystem::filesystem_error &e) {
        std::cerr << "[isFileNewer] Error: " << e.what() << std::endl;
        return false;
    }
}

inline std::time_t to_time_t(const std::filesystem::file_time_type &ft) {
    auto sctp = std::chrono::time_point_cast<std::chrono::system_clock::duration>(ft - std::filesystem::file_time_type::clock::now() + std::chrono::system_clock::now());
    return std::chrono::system_clock::to_time_t(sctp);
}

inline std::string get_current_time_as_string() {
    auto now = std::chrono::system_clock::now();

    std::time_t now_time_t = std::chrono::system_clock::to_time_t(now);

    std::tm now_tm = *std::localtime(&now_time_t);

    std::ostringstream oss;
    oss << std::put_time(&now_tm, "%Y-%m-%d %H:%M:%S");

    return oss.str();
}

using PortInfo = struct {
    // <dir> <type> <name> [<dimensions>]
    // e.g.
    //      input logic [3:0] foo
    //      input logic [3:0] foo [7:0]
    //      output reg bar
    //      output reg bar [15:0][VAL-1:0][1:0]
    std::string dir; // "input" or "output"
    std::string type;
    std::string name;

    // e.g.
    //     dimensions = { "[7:0]", "[2:0]", "[VAL-1:0]" }
    //     dimSizes = { "7 - 0 + 1", "2 - 0 + 1", "VAL-1 - 0 + 1" }
    std::vector<std::string> dimensions;
    std::vector<std::string> dimSizes;

    bool isNet;
    int id; // port id

    bool isInput() { return dir == "input"; }
    bool isOutput() { return dir == "output"; }

    std::string toDeclString() {
        auto _type = type;
        if (isInput()) {
            // e.g. input reg <...>
            ASSERT(!containsString(toString(), "reg"), "Unexpected reg in input port", toString());

            // _type = replaceString(_type, "logic", "reg");
            _type = replaceString(_type, "wire", "reg");
            _type = replaceString(_type, "bit", "reg");
        } else { // output
            _type = replaceString(_type, "reg", "wire");
            _type = replaceString(_type, "bit", "wire");
        }
        auto ret = replaceMultipleSpaces(fmt::format("{} {} {}", _type, name, fmt::join(dimensions, "")));
        ret      = trim(ret);
        return ret + ";";
    }

    std::string toString() {
        std::string dimStr = "";
        for (auto &dim : dimensions) {
            dimStr = dimStr + dim;
        }
        auto ret = fmt::format("{} {} {} {}", dir, type, name, dimStr);
        ret      = replaceMultipleSpaces(ret);
        ret      = trim(ret);
        return ret;
    }
};

namespace nlohmann {
template <> struct adl_serializer<PortInfo> {
    static void to_json(json &j, const PortInfo &p) { j = json{{"dir", p.dir}, {"type", p.type}, {"name", p.name}, {"dimensions", p.dimensions}, {"dimSizes", p.dimSizes}, {"isNet", p.isNet}, {"id", p.id}}; }

    static void from_json(const json &j, PortInfo &p) {
        j.at("dir").get_to(p.dir);
        j.at("type").get_to(p.type);
        j.at("name").get_to(p.name);
        j.at("dimensions").get_to(p.dimensions);
        j.at("dimSizes").get_to(p.dimSizes);
        j.at("isNet").get_to(p.isNet);
        j.at("id").get_to(p.id);
    }
};
} // namespace nlohmann

class TestbenchGenParser : public ASTVisitor<TestbenchGenParser, false, false> {
  private:
    int portIdAllocator = 0;
    std::string topName;

  public:
    bool verbose;
    TestbenchGenParser(std::string topName, bool verbose) : topName(topName) { this->verbose = verbose; }

    std::vector<PortInfo> portInfos;

    // e.g.
    // {
    //     "parameter string foo = \"bar\"",
    //     "parameter int bar = 42",
    //     ...
    // }
    std::vector<std::string> portParamStmts;
    // e.g.
    // {
    //   ".foo(foo)",
    //   ".bar(bar)",
    //   ...
    // }
    std::vector<std::string> portParamInstStmts;

    void handle(const InstanceBodySymbol &ast);
};

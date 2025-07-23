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
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <nlohmann/json.hpp>
#include <optional>
#include <ostream>
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

inline std::string replaceString(std::string str, std::string pattern, std::string replacement) { return replaceString(str, pattern.c_str(), replacement.c_str()); };

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
    std::string name;
    std::string dir;
    std::string pType; // port type
    std::string declStr;
    int arraySize;
    int id; // port id

    bool isArray() { return arraySize != 0; }
    bool isInput() { return dir == "In"; }
    bool isOutput() { return dir == "Out"; }
};

class TestbenchGenParser : public ASTVisitor<TestbenchGenParser, false, false> {
  private:
    int portIdAllocator = 0;
    std::string topName;

  public:
    bool verbose;
    TestbenchGenParser(std::string topName, bool verbose) : topName(topName) { this->verbose = verbose; }

    std::vector<PortInfo> portInfos;

    void handle(const InstanceBodySymbol &ast);
};

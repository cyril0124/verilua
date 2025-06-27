#pragma once

#include "SemanticModel.h"
#include "SlangCommon.h"
#include "config.h"
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

#define DEFAULT_OUTPUT_DIR ".dpi_exporter"
#define DEFAULT_WORK_DIR ".dpi_exporter"
#define DEFAULT_DPI_FILE_NAME "dpi_func.cpp"
#define DEFAULT_CLOCK_NAME "clock"
#define DEFAULT_SAMPLE_EDGE "negedge"

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
            if(line.ends_with(".f")) {
                // If the line ends with `.f`, treat it as a file list and parse it
                auto fileList = parseFileList(line);
                files.insert(files.end(), fileList.begin(), fileList.end());
            } else {
                files.push_back(line);
            }
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

inline std::pair<std::string, std::string> spiltHierPath(const std::string &hierPath) {
    auto dotPos = hierPath.rfind('.');
    ASSERT(dotPos != std::string::npos, "Invalid hierPath", hierPath);

    auto modulePath = hierPath.substr(0, dotPos);
    auto signalName = hierPath.substr(dotPos + 1);
    return std::make_pair(modulePath, signalName);
}

struct ConciseSignalPattern {
    std::string name;
    std::string module;
    std::string clock;
    std::string signals;
    std::string writableSignals;
    std::string disableSignals;
    std::string sensitiveSignals;

    bool checkValidSignal(std::string_view signal) { return checkValidSignal(std::string(signal)); }

    bool checkValidSignal(std::string signal) {
        // Check invalid signal
        if (!disableSignals.empty()) {
            std::regex disablePattern(disableSignals);
            if (std::regex_match(signal, disablePattern)) {
                return false;
            }
        }

        if (signals.empty()) {
            return checkWritableSignal(signal);
        }

        std::regex signalPattern(signals);
        if (std::regex_match(signal, signalPattern)) {
            return true;
        }

        return checkWritableSignal(signal);
    }

    bool checkWritableSignal(std::string_view signal) { return checkWritableSignal(std::string(signal)); }

    bool checkWritableSignal(std::string signal) {
        if (writableSignals.empty()) {
            return false;
        }

        std::regex signalPattern(writableSignals);
        if (std::regex_match(signal, signalPattern)) {
            return true;
        }

        return false;
    }

    bool checkSensitiveSignal(std::string_view signal) { return checkSensitiveSignal(std::string(signal)); }

    bool checkSensitiveSignal(std::string signal) {
        if (sensitiveSignals.empty()) {
            return false;
        }

        std::regex signalPattern(sensitiveSignals);
        if (std::regex_match(signal, signalPattern)) {
            return true;
        }

        return false;
    }
};

struct SignalInfo {
    std::string hierPath;
    std::string modulePath;
    std::string signalName;
    std::string vpiTypeStr;
    bitwidth_t bitWidth;
    uint64_t handleId;
    bool isWritable;

    std::string hierPathName;
    size_t beatSize;
    SignalInfo(std::string hierPath, std::string modulePath, std::string signalName, std::string vpiTypeStr, bitwidth_t bitWidth, uint64_t handleId, bool isWritable) : hierPath(hierPath), modulePath(modulePath), signalName(signalName), vpiTypeStr(vpiTypeStr), bitWidth(bitWidth), handleId(handleId), isWritable(isWritable) {
        hierPathName = getHierPathName();
        beatSize     = coverWith32(bitWidth);
    }

    std::string getHierPathName() {
        std::string hierPathName = hierPath;
        std::replace(hierPathName.begin(), hierPathName.end(), '.', '_');
        return hierPathName;
    }
};

struct SignalGroup {
    std::string name;
    std::string moduleName;
    ConciseSignalPattern cpattern;
    std::vector<SignalInfo> signalInfoVec;
    std::vector<SignalInfo> sensitiveSignalInfoVec;
};

inline uint64_t getUniqueHandleId() {
    static uint64_t handleId = 0;
    return handleId++;
}

inline bool checkUniqueSignal(std::string signal) {
    static std::unordered_set<std::string> signalSet;

    if (signalSet.count(signal) != 0) {
        return false;
    }
    signalSet.insert(signal);
    return true;
}
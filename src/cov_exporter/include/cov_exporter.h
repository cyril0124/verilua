#pragma once

#include "SlangCommon.h"
#include "fmt/core.h"
#include "fmt/format.h"
#include "libassert/assert.hpp"
#include "nlohmann/json.hpp"
#include <cassert>
#include <chrono>
#include <fstream>
#include <memory>
#include <optional>
#include <regex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#define DELETE_FILE(filePath)                                                                                                                                                                                                                                                                                                                                                                                  \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        if (std::filesystem::exists(filePath)) {                                                                                                                                                                                                                                                                                                                                                               \
            std::filesystem::remove(filePath);                                                                                                                                                                                                                                                                                                                                                                 \
        }                                                                                                                                                                                                                                                                                                                                                                                                      \
    } while (0)

#define DEFAULT_CLOCK_NAME "clock"
#define ALTERNATIVE_CLOCK_NAME "tb_top.clock"

struct ModuleOption {
    std::string moduleName;
    std::vector<std::string> disablePatterns;
    std::string clockName;
    std::string altClockName;
    std::set<std::string> subModuleSet;

    ModuleOption(std::string moduleName, std::string clockName, std::string altClockName) : moduleName(moduleName), clockName(clockName), altClockName(altClockName) {
        this->disablePatterns.clear();
        this->subModuleSet.clear();
    }

    bool checkDisableSignal(std::string_view signalName) {
        for (const auto &pattern : disablePatterns) {
            std::regex re(pattern);
            if (std::regex_match(std::string(signalName), re)) {
                return true;
            }
        }
        return false;
    }
};

bool checkDisableSignal(std::vector<std::string> &disablePatterns, std::string_view signalName) {
    for (const auto &pattern : disablePatterns) {
        std::regex re(pattern);
        if (std::regex_match(std::string(signalName), re)) {
            return true;
        }
    }
    return false;
}

struct CoverageInfo {
    std::string moduleName;
    std::string clockName;
    std::vector<std::string> hierPaths;
    std::vector<std::string> netVec;
    std::vector<std::string> varVec;
    std::vector<std::string> binExprVec;
    std::set<std::string> subModuleSet;

    struct Statistic {
        uint64_t netCount;
        uint64_t varCount;
        uint64_t duplicateNetCount;
        uint64_t binExprCount;
        std::vector<std::string> literalEqualNetVec;
        std::vector<std::string> identifierEqualNetVec;
    } statistic;
};

struct CondInfo {
    int depth;
    std::string type;
    std::string expr;
};
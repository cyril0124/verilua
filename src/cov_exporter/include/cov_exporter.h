#pragma once

#include "SlangCommon.h"
#include "fmt/core.h"
#include "fmt/format.h"
#include "libassert/assert.hpp"
#include "nlohmann/json.hpp"
#include "slang/ast/ASTVisitor.h"
#include "slang/ast/symbols/CompilationUnitSymbols.h"
#include "slang/ast/symbols/MemberSymbols.h"
#include "slang/ast/symbols/VariableSymbols.h"
#include "slang/ast/types/AllTypes.h"
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

#ifndef VERILUA_VERSION
#define VERILUA_VERSION "Unknown"
#endif

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

inline std::string replaceString(std::string str, const char *pattern, const char *replacement) {
    size_t pos = str.find(pattern);
    if (pos != std::string::npos) {
        return str.replace(pos, std::string(pattern).length(), replacement);
    }
    return str;
};

inline std::string replaceString(std::string str, std::string pattern, std::string replacement) { return replaceString(str, pattern.c_str(), replacement.c_str()); };

// =====================================================================
// Coverage data model (per module)
// =====================================================================
//
//   CoverageInfo (one per module)
//   +---------------------------------------------------------------+
//   |  netMap     : signal name -> SignalInfo  (toggle coverage)    |
//   |  varMap     : signal name -> SignalInfo  (toggle coverage)    |
//   |  condPaths  : [CondPathInfo, ...]        (path coverage)      |
//   |  condPathIndex : guard string -> index in condPaths           |
//   |  condRewrites  : [CondPathTopRewrite, ...] (writer anchors)   |
//   +---------------------------------------------------------------+
//
//   CondPathInfo                CondPathTopRewrite
//   +------------------+        +----------------------+
//   | id        : 0..N |        | topStmt : void*      |  -> original
//   | guard     : str  |        |   (ConditionalStmt)  |     syntax
//   | locations : [..] |        | wrappedText : str    |  -> rewritten
//   +------------------+        +----------------------+     SV text
//      |                            |
//      |  emitted as                |  used by writer to
//      |  `int _<id>__COV_BIN_EXPR_CNT`                replace() in tree
//      |
//   each branch body in wrappedText contains:
//      `if(_COV_EN) _<id>__COV_BIN_EXPR_CNT++; <orig body>`
//
// =====================================================================

struct SignalInfo {
    std::string type;
    std::string typeStr;
    size_t line;
    std::string file;
};

// One control-flow path entry. Identified uniquely by its `guard` string
// (the conjunction of the path conditions needed to enter this branch body).
// Multiple source locations may share the same guard and counter when the
// same condition appears at different source positions.
struct CondPathInfo {
    // Stable counter id assigned during collection.
    uint64_t id = 0;
    // Canonical guard string used for dedup, e.g. `(a) && (!(b))`.
    std::string guard;
    // All source locations whose body bumps this counter.
    std::vector<SignalInfo> locations;
};

// Replacement description for a top-level ConditionalStatement: the original
// syntax node (used as the anchor for replace()) plus the fully-wrapped SV
// source text that already embeds counter increments for every nested branch.
struct CondPathTopRewrite {
    // Pointer is type-erased to avoid bringing slang headers into this file.
    // It points at slang::syntax::ConditionalStatementSyntax.
    const void *topStmt = nullptr;
    std::string wrappedText;
};

struct CoverageInfo {
    std::string moduleName;
    std::string clockName;
    std::vector<std::string> hierPaths;
    std::unordered_map<std::string, SignalInfo> netMap;
    std::unordered_map<std::string, SignalInfo> varMap;
    std::set<std::string> subModuleSet;

    // Cond-path entries discovered for this module. Order is preserved so the
    // counter ids assigned by the writer stay stable across reruns.
    std::vector<CondPathInfo> condPaths;
    // guard string -> index into `condPaths` for fast dedup during collection.
    std::unordered_map<std::string, size_t> condPathIndex;
    // Top-level conditional statements scheduled for source rewriting.
    std::vector<CondPathTopRewrite> condRewrites;

    struct Statistic {
        uint64_t netCount;
        uint64_t varCount;
        uint64_t duplicateNetCount;
        uint64_t binExprCount; // number of cond-path coverage points
        std::vector<std::string> literalEqualNetVec;
        std::vector<std::string> identifierEqualNetVec;
        // Unsupported cond statement warnings: free-form messages for reporting.
        std::vector<std::string> unsupportedCondStmts;
    } statistic;
};
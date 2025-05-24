#pragma once

#include "config.h"
#include "cov_exporter.h"

inline uint64_t getUniqueBinExprId() {
    static uint64_t binExprUniqueId = 0;
    return binExprUniqueId++;
}

struct CoverageInfoWritter : public slang::syntax::SyntaxRewriter<CoverageInfoWritter> {
    CoverageInfo &coverageInfo;

    CoverageInfoWritter(CoverageInfo &coverageInfo) : coverageInfo(coverageInfo) {}

    void handle(const slang::syntax::ModuleDeclarationSyntax &syntax) {
        if (syntax.header->name.rawText() == coverageInfo.moduleName) {
            std::vector<std::string> decls;
            std::vector<std::string> incrs;
            std::vector<std::string> tgtSignals;
            std::vector<std::string> incrSignals;
            std::vector<std::string> infoVec = {"\n\n`ifndef NO_COVERAGE", "bit _COVERGE_ENABLE = 1;"};
            std::vector<std::string> allCoverSignalVec;
            std::vector<std::string> allBinExprCntSignalVec;

            auto beforeInsertInfo = [&]() {
                decls.clear();
                incrs.clear();
                tgtSignals.clear();
                incrSignals.clear();
            };

            auto insertInfoForBinExpr = [&]() {
                if (decls.empty() && incrs.empty())
                    return;
                infoVec.emplace_back(fmt::format(R"(
{}

always @(posedge {}) begin
if(_COVERGE_ENABLE) begin
{}
end
end
)",
                                                 fmt::to_string(fmt::join(decls, "\n")), coverageInfo.clockName, fmt::to_string(fmt::join(incrs, "\n"))));
            };

            // TODO: Optimize performance
            // TODO: Delay cycles(delay for some clock cycles and then enable coverage collection)
            // TODO: Disable when reset
            // TODO: Merge some signal to reduce the total number of signal?
            auto insertInfo = [&]() {
                if (decls.empty() && incrs.empty())
                    return;
                if (Config::getInstance().sepAlwaysBlock) {
                    // Seperate always block usually has better performance
                    std::vector<std::string> wrappedAlwaysBlocks;
                    for (int i = 0; i < tgtSignals.size(); i++) {
                        wrappedAlwaysBlocks.emplace_back(fmt::format("always @(posedge {}) begin if({} != $past({})) {}++; end", coverageInfo.clockName, tgtSignals[i], tgtSignals[i], incrSignals[i]));
                    }
                    infoVec.emplace_back(fmt::format("{}\n{}\n", fmt::to_string(fmt::join(decls, "\n")), fmt::to_string(fmt::join(wrappedAlwaysBlocks, "\n"))));
                } else {
                    infoVec.emplace_back(fmt::format(R"(
{}

always @(posedge {}) begin
if(_COVERGE_ENABLE) begin
{}
end
end
)",
                                                     fmt::to_string(fmt::join(decls, "\n")), coverageInfo.clockName, fmt::to_string(fmt::join(incrs, "\n"))));
                }
            };

            beforeInsertInfo();
            for (const auto &net : coverageInfo.netVec) {
                decls.emplace_back(fmt::format("int _COVER_TOGGLE_CNT__{} = 0;", net));
                incrs.emplace_back(fmt::format("if({0} != $past({0})) _COVER_TOGGLE_CNT__{0}++;", net));
                tgtSignals.emplace_back(net);
                incrSignals.emplace_back(fmt::format("_COVER_TOGGLE_CNT__{}", net));
                allCoverSignalVec.emplace_back("_COVER_TOGGLE_CNT__" + net);
            }
            insertInfo();

            beforeInsertInfo();
            for (const auto &var : coverageInfo.varVec) {
                decls.emplace_back(fmt::format("int _COVER_TOGGLE_CNT__{} = 0;", var));
                incrs.emplace_back(fmt::format("if({0} != $past({0})) _COVER_TOGGLE_CNT__{0}++;", var));
                tgtSignals.emplace_back(var);
                incrSignals.emplace_back(fmt::format("_COVER_TOGGLE_CNT__{}", var));
                allCoverSignalVec.emplace_back("_COVER_TOGGLE_CNT__" + var);
            }
            insertInfo();

            beforeInsertInfo();
            for (const auto &binExpr : coverageInfo.binExprVec) {
                auto binExprUniqueId = getUniqueBinExprId();
                auto cntSignal       = fmt::format("_COVER_TOGGLE_CNT_BIN_EXPR__{}", binExprUniqueId);
                decls.emplace_back(fmt::format("wire _COVER_TOGGLE_BIN_EXPR__{0} = {1};\nint {2} = 0;", binExprUniqueId, binExpr, cntSignal));
                incrs.emplace_back(fmt::format("if(_COVER_TOGGLE_BIN_EXPR__{0} != $past(_COVER_TOGGLE_BIN_EXPR__{0})) {1}++;", binExprUniqueId, cntSignal));
                allCoverSignalVec.emplace_back(cntSignal);
                allBinExprCntSignalVec.emplace_back(cntSignal);
                binExprUniqueId++;
            }
            insertInfoForBinExpr();

            std::vector<std::string> wrappedSignalVec;
            std::vector<std::string> wrappedBinExprCntVec;
            for (const auto &signal : allCoverSignalVec) {
                wrappedSignalVec.emplace_back(fmt::format("({} >= 1 ? 1 : 0)", signal));
            }
            for (const auto &signal : allBinExprCntSignalVec) {
                wrappedBinExprCntVec.emplace_back(fmt::format("({} >= 1 ? 1 : 0)", signal));
            }

            infoVec.push_back(R"(
function void coverageCtrl(input bit enable);
    _COVERGE_ENABLE = enable;
endfunction

export "DPI-C" function coverageCtrl;)");

            // clang-format off
            infoVec.push_back(fmt::format(R"(
function void getCoverageCount(output int totalCount, output int totalBinExprCount);
    totalCount = int'({});
    totalBinExprCount = int'({});
endfunction

export "DPI-C" function getCoverageCount;
)",
                wrappedSignalVec.size() == 0 ? "0" : fmt::to_string(fmt::join(wrappedSignalVec, " + ")),
                wrappedBinExprCntVec.size() == 0 ? "0" : fmt::to_string(fmt::join(wrappedBinExprCntVec, " + "))
            ));
            // clang-format on

            if (allCoverSignalVec.empty()) {
                // clang-format off
                infoVec.push_back(fmt::format(R"(
/*
hierPaths(ScopeNames):
    {0}
*/
function void getCoverage(output real value);
    value = real'(1);
endfunction

export "DPI-C" function getCoverage;
)",
                    fmt::to_string(fmt::join(coverageInfo.hierPaths, "\n    "))
                ));
                // clang-format on
            } else {
                // clang-format off
                infoVec.push_back(fmt::format(R"(
/*
hierPaths(ScopeNames):
    {0}
*/
function void getCoverage(output real value);
    value = real'({1}) / {2}.0;
endfunction

export "DPI-C" function getCoverage;
)",
                    fmt::to_string(fmt::join(coverageInfo.hierPaths, "\n    ")),
                    fmt::to_string(fmt::join(wrappedSignalVec, " + ")),
                    allCoverSignalVec.size()
                ));
                // clang-format on
            }

            // clang-format off
            infoVec.push_back(fmt::format(R"(
/*
hierPaths(ScopeNames):
    {0}
*/
function void getCondCoverage(output real value);
    value = real'({1}) / {2}.0;
endfunction

export "DPI-C" function getCondCoverage;
)",
                fmt::to_string(fmt::join(coverageInfo.hierPaths, "\n    ")),
                wrappedBinExprCntVec.size() == 0 ? "1" : fmt::to_string(fmt::join(wrappedBinExprCntVec, " + ")),
                coverageInfo.binExprVec.size() == 0 ? "1" : fmt::to_string(coverageInfo.binExprVec.size())
            ));
            // clang-format on

            std::vector<std::string> resetCovVec;
            for (const auto &signal : allCoverSignalVec) {
                resetCovVec.emplace_back(fmt::format("{} = 0;", signal));
            }
            // clang-format off
            infoVec.push_back(fmt::format(R"(
function void resetCoverage();
{}
endfunction

export "DPI-C" function resetCoverage;
)",
                fmt::to_string(fmt::join(resetCovVec, " "))
            ));
            // clang-format on

            // TODO: Get IO coverage, consider full toggle?
            // TODO: Other coverage info functions(e.g. show covered, show missed, which line is covered)

            // clang-format off
            infoVec.push_back(fmt::format(R"(
// [cov_exporter] Statistic:
//     netCount: {}
//     varCount: {}
//     binExprCount: {}
//     duplicateNetCount: {}
/*
literalEqualNet:
    {}
*/
/*
identifierEqualNet:
    {}
*/)",
                coverageInfo.statistic.netCount,
                coverageInfo.statistic.varCount,
                coverageInfo.statistic.binExprCount,
                coverageInfo.statistic.duplicateNetCount,
                fmt::to_string(fmt::join(coverageInfo.statistic.literalEqualNetVec, "\n    ")),
                fmt::to_string(fmt::join(coverageInfo.statistic.identifierEqualNetVec, "\n    "))
            ));
            // clang-format on

            infoVec.push_back("`endif // NO_COVERAGE");
            insertAtBack(syntax.members, parse(fmt::to_string(fmt::join(infoVec, "\n\n"))));
        }
    }
};
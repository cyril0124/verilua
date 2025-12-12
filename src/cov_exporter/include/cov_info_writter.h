#pragma once

#include "config.h"
#include "cov_exporter.h"

inline uint64_t getUniqueBinExprId() {
    static uint64_t binExprUniqueId = 0;
    return binExprUniqueId++;
}

struct CoverageInfoWritter : public slang::syntax::SyntaxRewriter<CoverageInfoWritter> {
    CoverageInfo &coverageInfo;
    bool relativeFilePath = false;

    CoverageInfoWritter(CoverageInfo &coverageInfo, bool relativeFilePath) : coverageInfo(coverageInfo), relativeFilePath(relativeFilePath) {}

    void handle(const slang::syntax::ModuleDeclarationSyntax &syntax) {
        if (syntax.header->name.rawText() == coverageInfo.moduleName) {
            std::vector<std::string> cntDecls;
            std::vector<std::string> lastDecls;
            std::vector<std::string> incrs;
            std::vector<std::string> tgtSignals;
            std::vector<std::string> infoVec = {"\n\n`ifndef NO_COVERAGE", "bit _COV_EN = 1;"};
            std::vector<std::string> allCoverSignalVec;
            std::vector<std::string> allBinExprCntSignalVec;
            std::vector<size_t> allBinExprLineVec;
            std::vector<std::string> allBinExprFileVec;

            auto beforeInsertInfo = [&]() {
                cntDecls.clear();
                lastDecls.clear();
                incrs.clear();
                tgtSignals.clear();
            };

            auto insertInfoForBinExpr = [&]() {
                if (cntDecls.empty() && incrs.empty())
                    return;
                if (Config::getInstance().sepAlwaysBlock) {
                    std::vector<std::string> wrappedAlwaysBlocks;
                    for (int i = 0; i < cntDecls.size(); i++) {
                        // tgtSignal[i] here is binExprUniqueId
                        wrappedAlwaysBlocks.emplace_back(fmt::format("always @(posedge {0}) begin if(_COV_EN) begin if(_{1}__COV_BIN_EXPR ^ _{1}__COV_BIN_EXPR_LAST) _{1}__COV_BIN_EXPR_CNT++; _{1}__COV_BIN_EXPR_LAST <= _{1}__COV_BIN_EXPR; end end", coverageInfo.clockName, tgtSignals[i]));
                    }
                    infoVec.emplace_back(fmt::format("{}\n{}\n\n{}\n", fmt::to_string(fmt::join(cntDecls, "\n")), fmt::to_string(fmt::join(lastDecls, "\n")), fmt::to_string(fmt::join(wrappedAlwaysBlocks, "\n"))));
                } else {
                    infoVec.emplace_back(fmt::format(R"(
{}
{}

always @(posedge {}) begin
if(_COV_EN) begin
{}
end
end
)",
                                                     fmt::to_string(fmt::join(cntDecls, "\n")), fmt::to_string(fmt::join(lastDecls, "\n")), coverageInfo.clockName, fmt::to_string(fmt::join(incrs, "\n"))));
                }
            };

            // TODO: Optimize performance
            // TODO: Delay cycles(delay for some clock cycles and then enable coverage collection)
            // TODO: Disable when reset
            // TODO: Merge some signal to reduce the total number of signal?
            auto insertInfo = [&]() {
                if (cntDecls.empty() && incrs.empty())
                    return;
                if (Config::getInstance().sepAlwaysBlock) {
                    // Seperate always block usually has better performance
                    std::vector<std::string> wrappedAlwaysBlocks;
                    for (int i = 0; i < tgtSignals.size(); i++) {
                        wrappedAlwaysBlocks.emplace_back(fmt::format("always @(posedge {0}) begin if(_COV_EN) begin if({1} ^ _{1}__LAST) _{1}__COV_CNT++; _{1}__LAST <= {1}; end end", coverageInfo.clockName, tgtSignals[i]));
                    }
                    infoVec.emplace_back(fmt::format("{}\n{}\n\n{}\n", fmt::to_string(fmt::join(cntDecls, "\n")), fmt::to_string(fmt::join(lastDecls, "\n")), fmt::to_string(fmt::join(wrappedAlwaysBlocks, "\n"))));
                } else {
                    infoVec.emplace_back(fmt::format(R"(
{}

always @(posedge {}) begin
if(_COV_EN) begin
{}
end
end
)",
                                                     fmt::to_string(fmt::join(cntDecls, "\n")), coverageInfo.clockName, fmt::to_string(fmt::join(incrs, "\n"))));
                }
            };

            beforeInsertInfo();
            for (const auto &pair : coverageInfo.netMap) {
                auto &net  = pair.first;
                auto &info = pair.second;
                ASSERT(info.type == "PackedArrayType" || info.type == "ScalarType", "TODO: Other type", info.type, info.typeStr);

                std::string lastRegType = replaceString(info.typeStr, "logic", "bit");

                cntDecls.emplace_back(fmt::format("int _{}__COV_CNT = 0;", net));
                lastDecls.emplace_back(fmt::format("{} _{}__LAST;", lastRegType, net));
                incrs.emplace_back(fmt::format("if({0} ^ _{0}__LAST) _{0}__COV_CNT++; _{0}__LAST <= {0}; end", net));

                tgtSignals.emplace_back(net);
                allCoverSignalVec.emplace_back("_" + net + "__COV_CNT");
            }
            insertInfo();

            beforeInsertInfo();
            for (const auto &pair : coverageInfo.varMap) {
                auto var  = pair.first;
                auto info = pair.second;
                ASSERT(info.type == "PackedArrayType" || info.type == "ScalarType", "TODO: Other type", info.type, info.typeStr);

                std::string _lastRegType = replaceString(info.typeStr, "logic", "bit");
                std::string lastRegType  = replaceString(_lastRegType, "reg", "bit");

                cntDecls.emplace_back(fmt::format("int _{}__COV_CNT = 0;", var));
                lastDecls.emplace_back(fmt::format("{} _{}__LAST;", lastRegType, var));
                incrs.emplace_back(fmt::format("if({0} ^ _{0}__LAST) _{0}__COV_CNT++; _{0}__LAST <= {0}; end", var));

                tgtSignals.emplace_back(var);
                allCoverSignalVec.emplace_back("_" + var + "__COV_CNT");
            }
            insertInfo();

            beforeInsertInfo();
            for (const auto &pair : coverageInfo.binExprMap) {
                auto &binExpr = pair.first;
                auto &info    = pair.second;

                auto binExprUniqueId = getUniqueBinExprId();
                auto cntSignal       = fmt::format("_{}__COV_BIN_EXPR_CNT", binExprUniqueId);

                cntDecls.emplace_back(fmt::format("wire _{}__COV_BIN_EXPR = {};\nint {} = 0;", binExprUniqueId, binExpr, cntSignal));
                lastDecls.emplace_back(fmt::format("bit _{}__COV_BIN_EXPR_LAST;", binExprUniqueId));
                incrs.emplace_back(fmt::format("if(_{0}__COV_BIN_EXPR ^ _{0}__COV_BIN_EXPR_LAST) {1}++; _{0}__COV_BIN_EXPR_LAST <= _{0}__COV_BIN_EXPR;", binExprUniqueId, cntSignal));

                tgtSignals.emplace_back(std::to_string(binExprUniqueId));
                allCoverSignalVec.emplace_back(cntSignal);
                allBinExprCntSignalVec.emplace_back(cntSignal);
                allBinExprLineVec.emplace_back(info.line);
                allBinExprFileVec.emplace_back(info.file);
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
    _COV_EN = enable;
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
                coverageInfo.binExprMap.size() == 0 ? "1" : fmt::to_string(coverageInfo.binExprMap.size())
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

            struct CovEntry {
                int line;
                std::string display_str;
            };
            std::vector<CovEntry> covEntries;
            for (const auto &pair : coverageInfo.netMap) {
                const auto &net  = pair.first;
                const auto &info = pair.second;
                std::string file = info.file;
                if (relativeFilePath) {
                    auto cwd         = std::filesystem::current_path();
                    auto absFilePath = std::filesystem::absolute(info.file);
                    file             = std::filesystem::relative(absFilePath, cwd).string();
                }
                covEntries.emplace_back(CovEntry{info.line, fmt::format("$display(\"[{0}] {1:6d}: %6d\\t`Net`\\t%s\t{3}:{1}\", _{2}__COV_CNT, _{2}__COV_CNT > 0 ? \"\\x1b[32mCOVERED\\x1b[0m\" : \"\\x1b[31mMISSED\\x1b[0m\");", coverageInfo.moduleName, info.line, net, file)});
            }
            for (const auto &pair : coverageInfo.varMap) {
                const auto &var  = pair.first;
                const auto &info = pair.second;
                std::string file = info.file;
                if (relativeFilePath) {
                    auto cwd         = std::filesystem::current_path();
                    auto absFilePath = std::filesystem::absolute(info.file);
                    file             = std::filesystem::relative(absFilePath, cwd).string();
                }
                covEntries.emplace_back(CovEntry{info.line, fmt::format("$display(\"[{0}] {1:6d}: %6d\\t`Var`\\t%s\t{3}:{1}\", _{2}__COV_CNT, _{2}__COV_CNT > 0 ? \"\\x1b[32mCOVERED\\x1b[0m\" : \"\\x1b[31mMISSED\\x1b[0m\");", coverageInfo.moduleName, info.line, var, file)});
            }
            for (int i = 0; i < allBinExprLineVec.size(); i++) {
                std::string file = allBinExprFileVec[i];
                if (relativeFilePath) {
                    auto cwd         = std::filesystem::current_path();
                    auto absFilePath = std::filesystem::absolute(allBinExprFileVec[i]);
                    file             = std::filesystem::relative(absFilePath, cwd).string();
                }
                covEntries.emplace_back(CovEntry{allBinExprLineVec[i], fmt::format("$display(\"[{0}] {1:6d}: %6d\\t`BinExpr`\\t%s\t{3}:{1}\", _{2}__COV_BIN_EXPR_CNT, _{2}__COV_BIN_EXPR_CNT > 0 ? \"\\x1b[32mCOVERED\\x1b[0m\" : \"\\x1b[31mMISSED\\x1b[0m\");", coverageInfo.moduleName, allBinExprLineVec[i], tgtSignals[i], file)});
            }
            // Sort by linenumber
            std::sort(covEntries.begin(), covEntries.end(), [](const CovEntry &a, const CovEntry &b) { return a.line < b.line; });
            std::vector<std::string> showCovVec;
            for (const auto &entry : covEntries) {
                showCovVec.emplace_back(entry.display_str);
            }

            // clang-format off
            infoVec.push_back(fmt::format(R"(
function void showCoverageCount();
$display("// ----------------------------------------");
$display("// Show Coverage Count[{}]");
$display("// ----------------------------------------");
$display("| Module | Line | Count | SignalType | Status | Source |");
{}
$display("| Module | Line | Count | SignalType | Status | Source |");
$display("");
endfunction

export "DPI-C" function showCoverageCount;
)",
                coverageInfo.moduleName,
                fmt::to_string(fmt::join(showCovVec, "\n"))
            ));
            // clang-format on

            // TODO: Get IO coverage, consider full toggle?

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

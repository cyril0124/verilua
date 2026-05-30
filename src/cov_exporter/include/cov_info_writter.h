#pragma once

#include "config.h"
#include "cov_exporter.h"

// ===================================================================
// cov_info_writter — rewrite modules to embed coverage instrumentation
// ===================================================================
//
//   transform(tree)  visits every ModuleDeclarationSyntax once.
//   For a module that has a CoverageInfo entry, handle() does:
//
//     module foo (...);
//   --+-----------------------------------------------------------
//     | insertAtFront:  `ifndef NO_COVERAGE                  [step 2]
//     |   (only when condPaths non-empty; skipped otherwise)
//     |                   bit _COV_EN = 1;
//     |                   int _<id>__COV_BIN_EXPR_CNT = 0;
//     |                 `endif
//   --+-----------------------------------------------------------
//     | <original RTL always blocks>                         [step 1]
//     |   replace() each top-level ConditionalStatement with
//     |   pre-built wrappedText (counter increments inlined,
//     |   each guarded by `ifndef NO_COVERAGE)
//   --+-----------------------------------------------------------
//     | insertAtBack:   `ifndef NO_COVERAGE                  [step 3]
//     |                   (bit _COV_EN = 1; when no front insert)
//     |                   <toggle counters + always blocks>
//     |                   coverageCtrl / getCoverage* /
//     |                   resetCoverage / showCoverageCount
//     |                 `endif
//     endmodule
//
//   Single transform pass: all modules share one rewriter so the
//   cond-path body pointers (anchored in the original tree) stay valid.
//   Defining NO_COVERAGE strips every guarded region -> clean RTL.
//
//   NOTE: The front insert is skipped when condPaths is empty because a
//   single-member block (just `bit _COV_EN = 1;`) triggers slang's
//   parseGuess() collapse, which drops the trailing `endif. When
//   condPaths >= 1 the block has >= 2 members and is safe.
//
// ===================================================================
struct CoverageInfoWritter : public slang::syntax::SyntaxRewriter<CoverageInfoWritter> {
    std::vector<CoverageInfo> &coverageInfos;
    bool relativeFilePath = false;
    // Lookup: module name -> coverageInfos index. Built once on construction.
    std::unordered_map<std::string, size_t> moduleIndex;

    CoverageInfoWritter(std::vector<CoverageInfo> &coverageInfos, bool relativeFilePath) : coverageInfos(coverageInfos), relativeFilePath(relativeFilePath) {
        for (size_t i = 0; i < coverageInfos.size(); i++) {
            moduleIndex.emplace(coverageInfos[i].moduleName, i);
        }
    }

    void handle(const slang::syntax::ModuleDeclarationSyntax &syntax) {
        // Layout of the rewritten module after all transforms:
        //
        //   module foo (...);
        //     `ifndef NO_COVERAGE                       <-- front decls
        //       bit _COV_EN = 1;                            (only when condPaths
        //       int _0__COV_BIN_EXPR_CNT = 0; // guard: ... is non-empty; skipped
        //       ...                                         when empty to avoid
        //     `endif // NO_COVERAGE                         parseGuess collapse)
        //
        //     <original RTL>
        //     always @(posedge clk) begin
        //       if (a) begin
        //         `ifndef NO_COVERAGE
        //         if(_COV_EN) _0__..._CNT++;   // injected, guarded too
        //         `endif
        //         ... end
        //       ...
        //     end
        //
        //     `ifndef NO_COVERAGE
        //       (bit _COV_EN = 1; when front insert skipped)
        //       int _<sig>__COV_CNT = 0;        <-- toggle counters
        //       bit _<sig>__LAST;
        //       always @(posedge clk) ...      <-- toggle sampling
        //       function void coverageCtrl();
        //       ...
        //     `endif // NO_COVERAGE
        //   endmodule
        //
        // Effect of `+define+NO_COVERAGE`: every guarded region disappears —
        // the front-of-module _COV_EN/counter declarations, the injected
        // `if(_COV_EN) _N__COV_BIN_EXPR_CNT++` increments (also wrapped in
        // `ifndef NO_COVERAGE by the getter), and the toggle/DPI helpers — so
        // the generated module is byte-for-byte equivalent to the original RTL.
        auto it = moduleIndex.find(std::string(syntax.header->name.rawText()));
        if (it == moduleIndex.end()) {
            return;
        }
        auto &coverageInfo = coverageInfos[it->second];

        // Counter ids are assigned by the getter (in collection order); the
        // writer trusts those ids and only emits matching declarations and
        // helpers below.

        // -----------------------------------------------------------------
        // Step 1: replace each top-level ConditionalStatement with a fully
        // rewritten version that already contains every nested counter
        // increment. Doing the rewrite at the outermost statement avoids the
        // problem of dropping nested replacements when the SyntaxRewriter
        // clones the parent subtree.
        // -----------------------------------------------------------------
        for (auto &rw : coverageInfo.condRewrites) {
            const auto *topPtr = static_cast<const slang::syntax::SyntaxNode *>(rw.topStmt);
            if (!topPtr)
                continue;
            // Prefix a newline so the rewritten chunk does not get glued onto
            // the preceding token (e.g. a `begin` immediately followed by `if`
            // would otherwise lex as a single identifier `beginif`).
            std::string text = std::string("\n") + rw.wrappedText;
            auto &newNode    = parse(text);
            replace(*topPtr, newNode);
        }

        // -----------------------------------------------------------------
        // Step 2: append module-level declarations and helpers.
        // -----------------------------------------------------------------
        // _COV_EN and the cond-path counters are inserted at the FRONT of the
        // module (so they precede the always blocks that reference them via
        // the injected `if(_COV_EN) _N__COV_BIN_EXPR_CNT++` statements), but
        // wrapped in `ifndef NO_COVERAGE. Because the injected increments are
        // ALSO wrapped in `ifndef NO_COVERAGE (see cov_info_getter), defining
        // NO_COVERAGE removes every trace of instrumentation and the generated
        // module is byte-for-byte equivalent to the original RTL.
        std::vector<std::string> allCoverSignalVec;      // every counter (toggle + cond-path)
        std::vector<std::string> allBinExprCntSignalVec; // cond-path counters only

        // When condPaths is non-empty, `_COV_EN` and the cond-path counter
        // declarations are inserted at the FRONT of the module (so they
        // precede the always blocks that reference them via the injected
        // `if(_COV_EN) _N__COV_BIN_EXPR_CNT++` statements). The front block
        // always has ≥2 members in this case (`bit _COV_EN` + at least one
        // `int` counter), which avoids slang's parseGuess() single-member
        // collapse that would drop the trailing `endif.
        //
        // When condPaths is empty, no body increments reference `_COV_EN`
        // from before the back block, so we skip the front insert entirely
        // and emit `_COV_EN` in the back block instead. This avoids the
        // single-member collapse bug.
        bool frontInserted = false;
        if (!coverageInfo.condPaths.empty()) {
            std::vector<std::string> frontDeclLines;
            frontDeclLines.emplace_back("`ifndef NO_COVERAGE");
            frontDeclLines.emplace_back("bit _COV_EN = 1;");
            for (const auto &path : coverageInfo.condPaths) {
                std::string cnt = fmt::format("_{}__COV_BIN_EXPR_CNT", path.id);
                frontDeclLines.emplace_back(fmt::format("int {} = 0; // guard: {}", cnt, path.guard));
                allCoverSignalVec.emplace_back(cnt);
                allBinExprCntSignalVec.emplace_back(cnt);
            }
            frontDeclLines.emplace_back("`endif // NO_COVERAGE");
            insertAtFront(syntax.members, parse("\n" + fmt::to_string(fmt::join(frontDeclLines, "\n")) + "\n"));
            frontInserted = true;
        } else {
            // No cond-path points: _COV_EN will be emitted in the back block.
        }

        std::vector<std::string> infoVec = {"\n\n`ifndef NO_COVERAGE"};
        // When front insert was skipped, emit _COV_EN at the top of the back block.
        if (!frontInserted) {
            infoVec.emplace_back("bit _COV_EN = 1;");
        }

        std::vector<std::string> cntDecls;
        std::vector<std::string> lastDecls;
        std::vector<std::string> incrs;
        std::vector<std::string> tgtSignals;

        auto reset = [&]() {
            cntDecls.clear();
            lastDecls.clear();
            incrs.clear();
            tgtSignals.clear();
        };

        // Toggle coverage block writer (used for nets and vars).
        //
        //   sepAlwaysBlock = true  (default, better simulator perf):
        //     one always per signal
        //       always @(posedge clk) if(_COV_EN)
        //         if (s ^ s__LAST) s__COV_CNT++;  s__LAST <= s;
        //       always @(posedge clk) ... (next signal)
        //
        //   sepAlwaysBlock = false (fewer blocks, one merged always):
        //       always @(posedge clk) if(_COV_EN) begin
        //         <incr s0> <incr s1> ... <incr sN>
        //       end
        //
        // `incrs` entries are bare increment statements (no wrapping begin/end);
        // each path wraps them in its own block so both layouts stay balanced.
        auto emitToggleBlock = [&]() {
            if (cntDecls.empty() && incrs.empty())
                return;
            if (Config::getInstance().sepAlwaysBlock) {
                std::vector<std::string> wrappedAlwaysBlocks;
                for (size_t i = 0; i < tgtSignals.size(); i++) {
                    wrappedAlwaysBlocks.emplace_back(fmt::format("always @(posedge {0}) begin if(_COV_EN) begin if({1} ^ _{1}__LAST) _{1}__COV_CNT++; _{1}__LAST <= {1}; end end", coverageInfo.clockName, tgtSignals[i]));
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

        // Net-toggle counters.
        reset();
        for (const auto &pair : coverageInfo.netMap) {
            auto &net  = pair.first;
            auto &info = pair.second;
            ASSERT(info.type == "PackedArrayType" || info.type == "ScalarType", "TODO: Other type", info.type, info.typeStr);
            std::string lastRegType = replaceString(info.typeStr, "logic", "bit");
            cntDecls.emplace_back(fmt::format("int _{}__COV_CNT = 0;", net));
            lastDecls.emplace_back(fmt::format("{} _{}__LAST;", lastRegType, net));
            incrs.emplace_back(fmt::format("if({0} ^ _{0}__LAST) _{0}__COV_CNT++; _{0}__LAST <= {0};", net));
            tgtSignals.emplace_back(net);
            allCoverSignalVec.emplace_back("_" + net + "__COV_CNT");
        }
        emitToggleBlock();

        // Var-toggle counters.
        reset();
        for (const auto &pair : coverageInfo.varMap) {
            auto var  = pair.first;
            auto info = pair.second;
            ASSERT(info.type == "PackedArrayType" || info.type == "ScalarType", "TODO: Other type", info.type, info.typeStr);
            std::string _lastRegType = replaceString(info.typeStr, "logic", "bit");
            std::string lastRegType  = replaceString(_lastRegType, "reg", "bit");
            cntDecls.emplace_back(fmt::format("int _{}__COV_CNT = 0;", var));
            lastDecls.emplace_back(fmt::format("{} _{}__LAST;", lastRegType, var));
            incrs.emplace_back(fmt::format("if({0} ^ _{0}__LAST) _{0}__COV_CNT++; _{0}__LAST <= {0};", var));
            tgtSignals.emplace_back(var);
            allCoverSignalVec.emplace_back("_" + var + "__COV_CNT");
        }
        emitToggleBlock();

        // Build the `>= 1 ? 1 : 0` wrapped expressions used by the helper
        // functions to compute coverage percentages.
        std::vector<std::string> wrappedSignalVec;
        std::vector<std::string> wrappedBinExprCntVec;
        for (const auto &signal : allCoverSignalVec) {
            wrappedSignalVec.emplace_back(fmt::format("({} >= 1 ? 1 : 0)", signal));
        }
        for (const auto &signal : allBinExprCntSignalVec) {
            wrappedBinExprCntVec.emplace_back(fmt::format("({} >= 1 ? 1 : 0)", signal));
        }

        // Renders the module's hierarchical scope paths as a compact `//`
        // comment placed above the coverage DPI functions. Empty -> no comment.
        auto scopeComment = [&]() -> std::string {
            if (coverageInfo.hierPaths.empty())
                return "";
            std::string out = "// scopes:";
            for (const auto &h : coverageInfo.hierPaths) {
                out += fmt::format("\n//   {}", h);
            }
            return out + "\n";
        };

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
            wrappedSignalVec.empty() ? "0" : fmt::to_string(fmt::join(wrappedSignalVec, " + ")),
            wrappedBinExprCntVec.empty() ? "0" : fmt::to_string(fmt::join(wrappedBinExprCntVec, " + "))
        ));
        // clang-format on

        if (allCoverSignalVec.empty()) {
            // clang-format off
            infoVec.push_back(fmt::format(R"(
{0}function void getCoverage(output real value);
    value = real'(1);
endfunction

export "DPI-C" function getCoverage;
)",
                scopeComment()
            ));
            // clang-format on
        } else {
            // clang-format off
            infoVec.push_back(fmt::format(R"(
{0}function void getCoverage(output real value);
    value = real'({1}) / {2}.0;
endfunction

export "DPI-C" function getCoverage;
)",
                scopeComment(),
                fmt::to_string(fmt::join(wrappedSignalVec, " + ")),
                allCoverSignalVec.size()
            ));
            // clang-format on
        }

        // clang-format off
        infoVec.push_back(fmt::format(R"(
{0}function void getCondCoverage(output real value);
    value = real'({1}) / {2}.0;
endfunction

export "DPI-C" function getCondCoverage;
)",
            scopeComment(),
            wrappedBinExprCntVec.empty() ? "1" : fmt::to_string(fmt::join(wrappedBinExprCntVec, " + ")),
            coverageInfo.condPaths.empty() ? "1" : fmt::to_string(coverageInfo.condPaths.size())
        ));
        // clang-format on

        // resetCoverage clears every counter we know about.
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

        // showCoverageCount: per-line $display rows, sorted by source line.
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
            covEntries.emplace_back(CovEntry{(int)info.line, fmt::format("$display(\"[{0}] {1:6d}: %6d\\t`Net`\\t%s\t{3}:{1}\", _{2}__COV_CNT, _{2}__COV_CNT > 0 ? \"\\x1b[32mCOVERED\\x1b[0m\" : \"\\x1b[31mMISSED\\x1b[0m\");", coverageInfo.moduleName, info.line, net, file)});
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
            covEntries.emplace_back(CovEntry{(int)info.line, fmt::format("$display(\"[{0}] {1:6d}: %6d\\t`Var`\\t%s\t{3}:{1}\", _{2}__COV_CNT, _{2}__COV_CNT > 0 ? \"\\x1b[32mCOVERED\\x1b[0m\" : \"\\x1b[31mMISSED\\x1b[0m\");", coverageInfo.moduleName, info.line, var, file)});
        }
        for (const auto &path : coverageInfo.condPaths) {
            // Each location associated with the same path counter shares the
            // same `cnt` signal, but we still want one $display row per
            // location so users can find the correct source position.
            for (const auto &loc : path.locations) {
                std::string file = loc.file;
                if (relativeFilePath) {
                    auto cwd         = std::filesystem::current_path();
                    auto absFilePath = std::filesystem::absolute(loc.file);
                    file             = std::filesystem::relative(absFilePath, cwd).string();
                }
                covEntries.emplace_back(CovEntry{(int)loc.line, fmt::format("$display(\"[{0}] {1:6d}: %6d\\t`CondPath`\\t%s\t{3}:{1}\\t{4}\", _{2}__COV_BIN_EXPR_CNT, _{2}__COV_BIN_EXPR_CNT > 0 ? \"\\x1b[32mCOVERED\\x1b[0m\" : \"\\x1b[31mMISSED\\x1b[0m\");", coverageInfo.moduleName, loc.line, path.id, file, path.guard)});
            }
        }
        std::sort(covEntries.begin(), covEntries.end(), [](const CovEntry &a, const CovEntry &b) { return a.line < b.line; });
        std::vector<std::string> showCovVec;
        for (const auto &entry : covEntries)
            showCovVec.emplace_back(entry.display_str);

        // clang-format off
        infoVec.push_back(fmt::format(R"(
function void showCoverageCount();
$display("// ----------------------------------------");
$display("// Show Coverage Count[{}]");
$display("// ----------------------------------------");
$display("// Column description:");
$display("//   Module    - module name where the coverage point resides");
$display("//   Line      - source line number of the coverage point");
$display("//   Count     - number of times the point was hit during simulation");
$display("//   SignalType - Net (wire toggle), Var (reg toggle), or CondPath {{branch entry}}");
$display("//   Status    - COVERED {{count > 0}} or MISSED {{count == 0}}");
$display("//   Source    - source file path and line");
$display("//   Guard     - {{CondPath only}} the path condition required to enter this branch");
$display("// ----------------------------------------");
$display("| Module | Line | Count | SignalType | Status | Source | Guard |");
{}
$display("| Module | Line | Count | SignalType | Status | Source | Guard |");
$display("");
endfunction

export "DPI-C" function showCoverageCount;
)",
            coverageInfo.moduleName,
            fmt::to_string(fmt::join(showCovVec, "\n"))
        ));
        // clang-format on

        // Statistic comment block.
        {
            // Aligned key/value rows.
            auto kvRow = [](const char *key, const std::string &val) {
                // 22 = width of the longest key below, keeps the colons aligned.
                return fmt::format("//   {:<22} : {}", key, val);
            };
            // A named list section; prints `(none)` when empty so the block
            // never collapses into an ugly empty `/* */` region.
            auto listSection = [](const char *title, const std::vector<std::string> &items) {
                std::string out = fmt::format("//   {}:", title);
                if (items.empty()) {
                    out += "\n//       (none)";
                } else {
                    for (const auto &it : items) {
                        out += fmt::format("\n//       {}", it);
                    }
                }
                return out;
            };

            static const char *bar = "// ----------------------------------------------------------";
            static const char *top = "// ==========================================================";

            std::vector<std::string> stat;
            stat.emplace_back(top);
            stat.emplace_back("//  cov_exporter Statistic");
            stat.emplace_back(bar);
            stat.emplace_back(kvRow("net coverage points", std::to_string(coverageInfo.statistic.netCount)));
            stat.emplace_back(kvRow("var coverage points", std::to_string(coverageInfo.statistic.varCount)));
            stat.emplace_back(kvRow("cond-path points", std::to_string(coverageInfo.statistic.binExprCount)));
            stat.emplace_back(kvRow("duplicate nets removed", std::to_string(coverageInfo.statistic.duplicateNetCount)));
            stat.emplace_back(kvRow("unsupported cond stmts", std::to_string(coverageInfo.statistic.unsupportedCondStmts.size())));
            stat.emplace_back(bar);
            stat.emplace_back(listSection("literalEqualNet (excluded)", coverageInfo.statistic.literalEqualNetVec));
            stat.emplace_back(listSection("identifierEqualNet (excluded)", coverageInfo.statistic.identifierEqualNetVec));
            stat.emplace_back(listSection("unsupportedCondStmts", coverageInfo.statistic.unsupportedCondStmts));
            stat.emplace_back(top);
            infoVec.push_back("\n" + fmt::to_string(fmt::join(stat, "\n")));
        }

        infoVec.push_back("`endif // NO_COVERAGE");
        insertAtBack(syntax.members, parse(fmt::to_string(fmt::join(infoVec, "\n\n"))));
    }
};

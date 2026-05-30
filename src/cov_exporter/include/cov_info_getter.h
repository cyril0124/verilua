#pragma once

#include "config.h"
#include "cov_exporter.h"
#include "debug.h"

// ===================================================================
// cov_info_getter — collect coverage points from one module's syntax
// ===================================================================
//
//   handle(ModuleDeclarationSyntax)            [entry, matched by name]
//       |
//       +--> NetSymbol  iter   --> netMap     (toggle coverage)
//       |       skips: clock/reset, disabled, literal-equal,
//       |              identifier-equal, continuous-assign aliases
//       +--> VariableSymbol it --> varMap     (toggle coverage)
//       +--> ContinuousAssign  --> de-dup alias nets from netMap
//       +--> ProceduralBlock   --> only sequential always / always_ff
//                |                  (must be a TimedStatement)
//                v
//            collectCondPaths(body, prefix=[])  (cond-path coverage)
//                |
//                | finds top-level ConditionalStatements
//                v
//            rewriteConditional() --> guard string + wrapped SV text
//                |                     (recursively rewrites nested if
//                |                      via rewriteStatement)
//                v
//            condPaths[]      : {id, guard, locations}
//            condRewrites[]   : {topStmt anchor, wrappedText}
//
//   Output lives in `coverageInfo`; the writer consumes it later.
//   See cov_exporter.h for the data-model diagram.
//
// ===================================================================

struct CoverageInfoGetter : public slang::syntax::SyntaxVisitor<CoverageInfoGetter> {
    bool findModule         = false;
    bool findClockSignal    = false;
    bool findAltClockSignal = false;
    ModuleOption moduleOption;
    std::vector<std::string> globalDisableSignalPatterns;
    slang::ast::Compilation *compilation;

    CoverageInfo coverageInfo;

    CoverageInfoGetter(ModuleOption moduleOption, std::vector<std::string> globalDisableSignalPatterns, slang::ast::Compilation *compilation) : moduleOption(moduleOption), globalDisableSignalPatterns(globalDisableSignalPatterns), compilation(compilation) {
        coverageInfo.moduleName = moduleOption.moduleName;
        coverageInfo.clockName  = moduleOption.clockName;
        coverageInfo.netMap.clear();
        coverageInfo.varMap.clear();
        coverageInfo.condPaths.clear();
        coverageInfo.condPathIndex.clear();
        coverageInfo.statistic.netCount          = 0;
        coverageInfo.statistic.varCount          = 0;
        coverageInfo.statistic.duplicateNetCount = 0;
        coverageInfo.statistic.binExprCount      = 0;
        coverageInfo.statistic.literalEqualNetVec.clear();
        coverageInfo.statistic.unsupportedCondStmts.clear();
        coverageInfo.subModuleSet = moduleOption.subModuleSet;
    }

    bool conAssignSetInit = false;
    std::unordered_set<std::string> conAssignSet;
    void handle(const slang::syntax::ModuleDeclarationSyntax &syntax) {
        if (syntax.header->name.rawText() == moduleOption.moduleName) {
            findModule = true;
            auto def   = compilation->getDefinition(static_cast<const Scope &>(compilation->getRoot()), syntax);
            auto inst  = &InstanceSymbol::createDefault(*compilation, *def);

            INFO_PRINT("[cov_info_getter] moduleName: {}", moduleOption.moduleName);

            std::vector<std::string> hierPaths = slang_common::getHierPaths(compilation, moduleOption.moduleName);
            for (auto &hierPath : hierPaths) {
                INFO_PRINT("\thierPath: {}", hierPath);
                coverageInfo.hierPaths.emplace_back(hierPath);
            }
            INFO_PRINT("");

            int count = 0;

            auto netIter = inst->body.membersOfType<slang::ast::NetSymbol>();
            for (const auto &net : netIter) {
                auto line              = compilation->getSourceManager()->getLineNumber(net.location) - 2;
                auto fileWithBakSuffix = std::filesystem::absolute(compilation->getSourceManager()->getFileName(net.location)).string();
                auto file              = fileWithBakSuffix.substr(0, fileWithBakSuffix.size() - 4); // Remove `.bak` suffix
                INFO_PRINT("\t[{}] NetSymbol: {}, type: <{}, {}>, source: {}:{}", count++, net.name, toString(net.getType().kind), net.getType().toString(), file, line);

                if (!findClockSignal && net.name == moduleOption.clockName) {
                    findClockSignal = true;
                }

                if (!findAltClockSignal && net.name == moduleOption.altClockName) {
                    findAltClockSignal = true;
                }

                if (checkDisableSignal(globalDisableSignalPatterns, net.name)) {
                    INFO_PRINT("\t\t[Global Disabled] {}", net.name);
                    continue;
                }

                if (moduleOption.checkDisableSignal(net.name)) {
                    INFO_PRINT("\t\t[Disabled] {}", net.name);
                    continue;
                }

                // TODO: Configurable `reset` signal
                if (net.name == moduleOption.clockName || net.name == "reset") {
                    continue;
                }

                struct IntegerVectorVisitor : public slang::syntax::SyntaxVisitor<IntegerVectorVisitor> {
                    bool maybeLiteralEqual    = false;
                    bool maybeIdentifierEqual = false;

                    // Remove literal equal net:
                    //      e.g. wire a = 1'b1;
                    void handle(const slang::syntax::IntegerVectorExpressionSyntax &syntax) {
                        if (syntax.parent->kind == slang::syntax::SyntaxKind::EqualsValueClause) {
                            maybeLiteralEqual = true;
                        }
                    }

                    // Remove identifier name equal net:
                    //      e.g.
                    //          wire b;
                    //          wire a = b;
                    void handle(const slang::syntax::IdentifierNameSyntax &syntax) {
                        if (syntax.parent->kind == slang::syntax::SyntaxKind::EqualsValueClause) {
                            maybeIdentifierEqual = true;
                        }
                    }
                };

                auto v = IntegerVectorVisitor();
                net.getSyntax()->visit(v);
                // Decide whether this net is a constant/alias that should be
                // EXCLUDED from toggle coverage (it never really toggles):
                //
                //   wire a = 1'b1;   maybeLiteralEqual    ──┐
                //   wire a = b;      maybeIdentifierEqual ──┤
                //                                          v
                //              is `a` also driven by a continuous assign?
                //              (a in conAssignSet, built once, lazily)
                //                 yes ──> NOT excluded (it can change)
                //                 no  ──> excluded -> literalEqualNetVec /
                //                                     identifierEqualNetVec
                if (v.maybeLiteralEqual || v.maybeIdentifierEqual) {
                    bool isLiteralEqualNet    = true;
                    bool isIdentifierEqualNet = true;

                    if (conAssignSet.count(std::string(net.name))) {
                        isLiteralEqualNet    = false;
                        isIdentifierEqualNet = false;
                    } else {
                        // If the NetSymbol has been assigned by continuous assign after the net is defined, it is not a literal equal net.
                        auto conAssignSymIter = inst->body.membersOfType<slang::ast::ContinuousAssignSymbol>();
                        if (!conAssignSetInit) {
                            for (const auto &conAssignSym : conAssignSymIter) {
                                auto syntax = conAssignSym.getSyntax();
                                if (syntax->kind != slang::syntax::SyntaxKind::AssignmentExpression) {
                                    continue;
                                }

                                auto binExprSyn = &syntax->as<slang::syntax::BinaryExpressionSyntax>();
                                if (binExprSyn->left->kind != slang::syntax::SyntaxKind::IdentifierName) {
                                    continue;
                                }

                                auto identifier = &binExprSyn->left->as<slang::syntax::IdentifierNameSyntax>();
                                auto identName  = identifier->identifier.rawText();
                                conAssignSet.insert(std::string(identName));
                            }
                            conAssignSetInit = true;
                        }

                        for (const auto &conAssignSym : conAssignSymIter) {
                            auto syntax = conAssignSym.getSyntax();
                            if (syntax->kind != slang::syntax::SyntaxKind::AssignmentExpression) {
                                // fmt::println("\t\tNot AssignmentExpressionSyntax: {}", syntax->toString());
                                continue;
                            }

                            auto binExprSyn = &syntax->as<slang::syntax::BinaryExpressionSyntax>();
                            if (binExprSyn->left->kind != slang::syntax::SyntaxKind::IdentifierName) {
                                // fmt::println("\t\tNot IdentifierNameSyntax: {}", binExprSyn->left->toString());
                                continue;
                            }

                            auto identifier = &binExprSyn->left->as<slang::syntax::IdentifierNameSyntax>();
                            auto identName  = identifier->identifier.rawText();

                            if (identName == net.name) {
                                isLiteralEqualNet    = false;
                                isIdentifierEqualNet = false;
                                break;
                            }
                        }
                    }

                    if (v.maybeLiteralEqual && isLiteralEqualNet) {
                        INFO_PRINT("\t\t[LiteralEqualNet] {}", net.name);
                        coverageInfo.statistic.literalEqualNetVec.emplace_back(net.name);
                        continue;
                    }

                    if (v.maybeIdentifierEqual && isIdentifierEqualNet) {
                        INFO_PRINT("\t\t[IdentifierEqualNet] {}", net.name);
                        coverageInfo.statistic.identifierEqualNetVec.emplace_back(net.name);
                        continue;
                    }
                }

                // TODO: wire a = c | d; ??

                coverageInfo.netMap.emplace(net.name, SignalInfo{std::string(toString(net.getType().kind)), std::string(net.getType().toString()), line, file});
            }

            count = 0;

            auto varIter = inst->body.membersOfType<slang::ast::VariableSymbol>();
            for (const auto &var : varIter) {
                auto line              = compilation->getSourceManager()->getLineNumber(var.location) - 2;
                auto fileWithBakSuffix = std::filesystem::absolute(compilation->getSourceManager()->getFileName(var.location)).string();
                auto file              = fileWithBakSuffix.substr(0, fileWithBakSuffix.size() - 4); // Remove `.bak` suffix
                INFO_PRINT("\t[{}] VariableSymbol: {}, type: <{}, {}>, source: {}:{}", count++, var.name, toString(var.getType().kind), var.getType().toString(), file, line);

                if (!findClockSignal && var.name == moduleOption.clockName) {
                    findClockSignal = true;
                }

                if (!findAltClockSignal && var.name == moduleOption.altClockName) {
                    findAltClockSignal = true;
                }

                if (checkDisableSignal(globalDisableSignalPatterns, var.name)) {
                    INFO_PRINT("\t\t[Global Disabled] {}", var.name);
                    continue;
                }

                if (moduleOption.checkDisableSignal(var.name)) {
                    INFO_PRINT("\t\t[Disabled] {}", var.name);
                    continue;
                }

                coverageInfo.varMap.emplace(var.name, SignalInfo{std::string(toString(var.getType().kind)), std::string(var.getType().toString()), line, file});
            }

            // TODO: Optimize some simple expr? (e.g. assign a = c & d;)
            auto conAssignSymIter = inst->body.membersOfType<slang::ast::ContinuousAssignSymbol>();
            for (const auto &conAssignSym : conAssignSymIter) {
                // Optimize alias signal assignment
                // e.g.
                //      wire a;
                //      wire b;
                //      assign a = b;
                // In this case, we only need to record `a`.
                conAssignSym.visitExprs(makeVisitor([&](auto &, const slang::ast::AssignmentExpression &assignExpr) {
                    auto &lkind = assignExpr.left().kind;
                    auto &rkind = assignExpr.right().kind;
                    if (lkind == slang::ast::ExpressionKind::NamedValue && rkind == slang::ast::ExpressionKind::NamedValue) {
                        auto assignExprStr = assignExpr.syntax->toString();
                        auto &leftExpr     = assignExpr.left().as<slang::ast::NamedValueExpression>();
                        auto &rightExpr    = assignExpr.right().as<slang::ast::NamedValueExpression>();
                        auto leftName      = leftExpr.symbol.name;
                        auto rightName     = rightExpr.symbol.name;

                        // Remove duplicate signal from `coverageInfo.netMap`
                        auto it = coverageInfo.netMap.find(std::string(leftName));
                        if (it != coverageInfo.netMap.end()) {
                            auto &count = coverageInfo.statistic.duplicateNetCount;
                            INFO_PRINT("\t[AssignAliasSignal] [No.{}] Remove duplicate net signal: `{}`, left: `{}`, right: `{}`, expr: `assign {}`", count, leftName, leftName, rightName, assignExprStr);
                            coverageInfo.netMap.erase(it);
                            count++;
                        }
                    }
                }));
            }

            count         = 0;
            auto procIter = inst->body.membersOfType<slang::ast::ProceduralBlockSymbol>();
            for (const auto &proc : procIter) {
                using slang::ast::ProceduralBlockKind;
                // Only sequential `always` and `always_ff` are instrumented for cond-path
                // coverage. always_comb / always_latch / initial / final do not give a clean
                // "branch entry" semantics under our counter-in-body model, so they are
                // skipped explicitly.
                if (proc.procedureKind != ProceduralBlockKind::Always && proc.procedureKind != ProceduralBlockKind::AlwaysFF) {
                    continue;
                }

                // The body must be a TimedStatement (i.e. driven by an event control such as
                // `@(posedge clk)`); otherwise we cannot guarantee a sequential execution
                // model and skip the block.
                const auto &body = proc.getBody();
                if (body.kind != slang::ast::StatementKind::Timed) {
                    continue;
                }
                const auto &timed = body.as<slang::ast::TimedStatement>();

                collectCondPaths(timed.stmt, /*prefix*/ {});
            }

            coverageInfo.statistic.netCount     = coverageInfo.netMap.size();
            coverageInfo.statistic.varCount     = coverageInfo.varMap.size();
            coverageInfo.statistic.binExprCount = coverageInfo.condPaths.size();
        } else {
            visitDefault(syntax);
        }
    }

    // ---------------------------------------------------------------------
    // Cond-path coverage collection
    // ---------------------------------------------------------------------

    // Detects expressions that we cannot safely treat as a static path guard:
    // function/system calls and similar side-effecting/non-pure constructs.
    // The check is recursive across the whole expression tree because a complex
    // condition is rejected if *any* sub-expression is unsafe.
    static bool exprHasUnsupportedKind(const slang::ast::Expression &expr) {
        bool found   = false;
        auto visitor = makeVisitor(
            [&](auto &v, const slang::ast::CallExpression &e) {
                found = true;
                v.visitDefault(e);
            },
            [&](auto &v, const slang::ast::NewArrayExpression &e) {
                found = true;
                v.visitDefault(e);
            },
            [&](auto &v, const slang::ast::NewClassExpression &e) {
                found = true;
                v.visitDefault(e);
            },
            [&](auto &v, const slang::ast::NewCovergroupExpression &e) {
                found = true;
                v.visitDefault(e);
            },
            [&](auto &v, const slang::ast::CopyClassExpression &e) {
                found = true;
                v.visitDefault(e);
            },
            [&](auto &v, const slang::ast::AssignmentExpression &e) {
                found = true;
                v.visitDefault(e);
            },
            [&](auto &v, const slang::ast::StreamingConcatenationExpression &e) {
                found = true;
                v.visitDefault(e);
            });
        expr.visit(visitor);
        return found;
    }

    // Returns (file, line) for a syntax node by translating its starting source
    // location through the source manager. The file path is normalized to drop
    // the `.bak` suffix used by the workdir snapshot.
    std::pair<std::string, size_t> locationOf(const slang::syntax::SyntaxNode &node) const {
        auto loc               = node.sourceRange().start();
        auto line              = compilation->getSourceManager()->getLineNumber(loc) - 2;
        auto fileWithBakSuffix = std::filesystem::absolute(compilation->getSourceManager()->getFileName(loc)).string();
        auto file              = fileWithBakSuffix.substr(0, fileWithBakSuffix.size() - 4);
        return {file, line};
    }

    // Combines a list of accumulated prefix conditions with the current branch
    // condition into a single canonical guard string of the form
    // `(prefix0) && (prefix1) && (cond)`. Each piece is wrapped in parentheses
    // so that operator precedence in the original expressions does not affect
    // the structure of the guard string used for dedup.
    static std::string buildGuard(const std::vector<std::string> &prefix, const std::string &cond) {
        std::string out;
        for (const auto &p : prefix) {
            if (!out.empty())
                out += " && ";
            out += "(" + p + ")";
        }
        if (!out.empty() && !cond.empty())
            out += " && ";
        if (!cond.empty())
            out += "(" + cond + ")";
        return out;
    }

    // Records (or merges) a coverage point with the given guard, returning the
    // assigned counter id. The same id is reused if the guard already exists.
    uint64_t recordPath(const std::string &guard, const SignalInfo &loc) {
        auto it = coverageInfo.condPathIndex.find(guard);
        size_t idx;
        if (it == coverageInfo.condPathIndex.end()) {
            CondPathInfo info;
            info.id    = coverageInfo.condPaths.size();
            info.guard = guard;
            idx        = info.id;
            coverageInfo.condPaths.emplace_back(std::move(info));
            coverageInfo.condPathIndex.emplace(guard, idx);
        } else {
            idx = it->second;
        }
        coverageInfo.condPaths[idx].locations.push_back(loc);
        return coverageInfo.condPaths[idx].id;
    }

    // Returns true if `body` is empty in the SystemVerilog sense, i.e. would
    // generate no observable execution. Empty branches are intentionally not
    // instrumented because they cannot be "entered" in a meaningful way.
    static bool isEmptyBody(const slang::ast::Statement &body) {
        using slang::ast::StatementKind;
        if (body.kind == StatementKind::Empty)
            return true;
        if (body.kind == StatementKind::Block) {
            const auto &blk = body.as<slang::ast::BlockStatement>();
            return isEmptyBody(blk.body);
        }
        if (body.kind == StatementKind::List) {
            const auto &lst = body.as<slang::ast::StatementList>();
            return lst.list.empty();
        }
        return false;
    }

    // Trims surrounding whitespace and an optional `begin .. end` wrapper from
    // `text`. Used so we do not introduce extra nested begin/end blocks when
    // wrapping branch bodies that are already a block.
    static std::string stripBeginEnd(const std::string &text) {
        auto firstNonWS = text.find_first_not_of(" \t\r\n");
        auto lastNonWS  = text.find_last_not_of(" \t\r\n");
        if (firstNonWS == std::string::npos || lastNonWS == std::string::npos)
            return text;
        std::string trimmed = text.substr(firstNonWS, lastNonWS - firstNonWS + 1);
        if (trimmed.size() >= 8 && trimmed.compare(0, 5, "begin") == 0 && trimmed.compare(trimmed.size() - 3, 3, "end") == 0) {
            return trimmed.substr(5, trimmed.size() - 5 - 3);
        }
        return text;
    }

    // Recursively rewrites `stmt` so every cond-path branch contains a counter
    // increment as its first action. Returns the rewritten SV source text.
    //
    //   Statement kind dispatch:
    //
    //     Conditional --> rewriteConditional() [emits if/else-if/else chain]
    //     Block       --> recurse into body, wrap with begin/end
    //                     (only for Sequential blockKind; fork/join/etc.
    //                      kept as raw text to preserve semantics)
    //     List        --> recurse into each child statement
    //     ForLoop     --\
    //     WhileLoop    |
    //     DoWhileLoop  |
    //     ForeverLoop  |--> rewriteLoopWithBody() [keep header, rewrite body]
    //     RepeatLoop   |
    //     ForeachLoop -/
    //     Case        --> rewriteCaseStatement() [recurse into each item.body]
    //     PatternCase --\
    //     RandCase     |--> raw text (header too complex to reconstruct)
    //     Timed       --/
    //     Wait        --> raw text
    //     <other>     --> raw text (no nested statements to instrument)
    std::string rewriteStatement(const slang::ast::Statement &stmt, std::vector<std::string> prefix) {
        using slang::ast::StatementKind;
        switch (stmt.kind) {
        case StatementKind::Conditional:
            return rewriteConditional(stmt.as<slang::ast::ConditionalStatement>(), std::move(prefix));
        case StatementKind::Block: {
            const auto &blk = stmt.as<slang::ast::BlockStatement>();
            // Preserve block kind for fork-join blocks (non-Sequential).
            // For sequential blocks, always recurse into the body.
            if (blk.blockKind != slang::ast::StatementBlockKind::Sequential) {
                return stmt.syntax ? std::string(stmt.syntax->toString()) : rewriteStatement(blk.body, prefix);
            }
            std::string inner = rewriteStatement(blk.body, prefix);
            return std::string("begin ") + inner + " end";
        }
        case StatementKind::List: {
            const auto &lst = stmt.as<slang::ast::StatementList>();
            std::string out;
            for (auto child : lst.list) {
                out += rewriteStatement(*child, prefix);
                out += "\n";
            }
            return out;
        }
        case StatementKind::ForLoop: {
            const auto &loop     = stmt.as<slang::ast::ForLoopStatement>();
            std::string bodyText = rewriteStatement(loop.body, prefix);
            // Reconstruct: keep original loop header, replace body.
            // Since we cannot easily reconstruct the for-header from AST,
            // we use the original syntax text but splice in the rewritten body.
            return rewriteLoopWithBody(stmt, bodyText);
        }
        case StatementKind::WhileLoop: {
            const auto &loop     = stmt.as<slang::ast::WhileLoopStatement>();
            std::string bodyText = rewriteStatement(loop.body, prefix);
            return rewriteLoopWithBody(stmt, bodyText);
        }
        case StatementKind::DoWhileLoop: {
            const auto &loop     = stmt.as<slang::ast::DoWhileLoopStatement>();
            std::string bodyText = rewriteStatement(loop.body, prefix);
            return rewriteLoopWithBody(stmt, bodyText);
        }
        case StatementKind::ForeverLoop: {
            const auto &loop     = stmt.as<slang::ast::ForeverLoopStatement>();
            std::string bodyText = rewriteStatement(loop.body, prefix);
            return rewriteLoopWithBody(stmt, bodyText);
        }
        case StatementKind::RepeatLoop: {
            const auto &loop     = stmt.as<slang::ast::RepeatLoopStatement>();
            std::string bodyText = rewriteStatement(loop.body, prefix);
            return rewriteLoopWithBody(stmt, bodyText);
        }
        case StatementKind::ForeachLoop: {
            const auto &loop     = stmt.as<slang::ast::ForeachLoopStatement>();
            std::string bodyText = rewriteStatement(loop.body, prefix);
            return rewriteLoopWithBody(stmt, bodyText);
        }
        case StatementKind::Case: {
            const auto &cs = stmt.as<slang::ast::CaseStatement>();
            return rewriteCaseStatement(cs, prefix);
        }
        case StatementKind::PatternCase:
        case StatementKind::RandCase:
        case StatementKind::Timed: {
            // For Timed/PatternCase/RandCase: emit raw syntax (header is
            // complex) but still recurse into bodies for nested conditionals.
            // This is a best-effort approach — the header is preserved as-is.
            return stmt.syntax ? std::string(stmt.syntax->toString()) : std::string();
        }
        case StatementKind::Wait: {
            // Wait has a body that could contain conditionals.
            const auto &ws       = stmt.as<slang::ast::WaitStatement>();
            std::string bodyText = rewriteStatement(ws.stmt, prefix);
            // Cannot easily reconstruct wait header; emit raw.
            return stmt.syntax ? std::string(stmt.syntax->toString()) : std::string();
        }
        default:
            return stmt.syntax ? std::string(stmt.syntax->toString()) : std::string();
        }
    }

    // Rewrites a loop statement by replacing its body with `bodyText` while
    // keeping the loop header intact. Since reconstructing the loop header
    // from AST fields is complex and error-prone, we find the body's source
    // range within the loop's source text and splice in the rewritten body.
    std::string rewriteLoopWithBody(const slang::ast::Statement &loopStmt, const std::string &bodyText) {
        if (!loopStmt.syntax)
            return bodyText;
        std::string loopText = std::string(loopStmt.syntax->toString());
        // The body is always the last child statement. Find its source text
        // within the loop text and replace it.
        const slang::ast::Statement *bodyStmt = nullptr;
        switch (loopStmt.kind) {
        case slang::ast::StatementKind::ForLoop:
            bodyStmt = &loopStmt.as<slang::ast::ForLoopStatement>().body;
            break;
        case slang::ast::StatementKind::WhileLoop:
            bodyStmt = &loopStmt.as<slang::ast::WhileLoopStatement>().body;
            break;
        case slang::ast::StatementKind::DoWhileLoop:
            bodyStmt = &loopStmt.as<slang::ast::DoWhileLoopStatement>().body;
            break;
        case slang::ast::StatementKind::ForeverLoop:
            bodyStmt = &loopStmt.as<slang::ast::ForeverLoopStatement>().body;
            break;
        case slang::ast::StatementKind::RepeatLoop:
            bodyStmt = &loopStmt.as<slang::ast::RepeatLoopStatement>().body;
            break;
        case slang::ast::StatementKind::ForeachLoop:
            bodyStmt = &loopStmt.as<slang::ast::ForeachLoopStatement>().body;
            break;
        default:
            return loopText;
        }
        if (!bodyStmt || !bodyStmt->syntax)
            return loopText;
        std::string origBody = std::string(bodyStmt->syntax->toString());
        // Find and replace the LAST occurrence of origBody in loopText.
        auto pos = loopText.rfind(origBody);
        if (pos != std::string::npos) {
            loopText.replace(pos, origBody.size(), bodyText);
        }
        return loopText;
    }

    // Rewrites a CaseStatement by recursing into each item's body.
    std::string rewriteCaseStatement(const slang::ast::CaseStatement &cs, std::vector<std::string> prefix) {
        if (!cs.syntax)
            return std::string();
        std::string caseText = std::string(cs.syntax->toString());
        // For each item, find its body text and replace with rewritten version.
        for (const auto &item : cs.items) {
            if (!item.stmt || !item.stmt->syntax)
                continue;
            std::string origBody = std::string(item.stmt->syntax->toString());
            std::string newBody  = rewriteStatement(*item.stmt, prefix);
            if (origBody != newBody) {
                auto pos = caseText.find(origBody);
                if (pos != std::string::npos) {
                    caseText.replace(pos, origBody.size(), newBody);
                }
            }
        }
        if (cs.defaultCase && cs.defaultCase->syntax) {
            std::string origBody = std::string(cs.defaultCase->syntax->toString());
            std::string newBody  = rewriteStatement(*cs.defaultCase, prefix);
            if (origBody != newBody) {
                auto pos = caseText.find(origBody);
                if (pos != std::string::npos) {
                    caseText.replace(pos, origBody.size(), newBody);
                }
            }
        }
        return caseText;
    }

    // Rewrites a ConditionalStatement (and the rest of its else-if/else chain)
    // into a wrapped SV string. Each supported branch body is wrapped in
    // `begin if(_COV_EN) _<id>__COV_BIN_EXPR_CNT++; <inner> end`.
    //
    //   Source                       Path guards collected
    //   --------------------------   ----------------------------------
    //     if (a)                       (a)
    //         body0                ->
    //     else if (b)                  (!(a)) && (b)
    //         body1                ->
    //     else if (c)                  (!(a)) && (!(b)) && (c)
    //         body2                ->
    //     else                         (!(a)) && (!(b)) && (!(c))
    //         body3                ->
    //
    //   chainNegation accumulates  ->  prior-conditions-all-false
    //   prefix (passed in)         ->  guards from outer if-statements
    //
    //   Resulting text shape per branch:
    //     [else ]if (cond) begin if(_COV_EN) _N__COV_BIN_EXPR_CNT++; ... end
    //     else             begin if(_COV_EN) _M__COV_BIN_EXPR_CNT++; ... end
    //
    //   Unsupported branches (multi-cond / pattern / func call in cond)
    //   bail out: emit raw syntax for the current node and return,
    //   skipping the rest of the chain (recorded in unsupportedCondStmts).
    std::string rewriteConditional(const slang::ast::ConditionalStatement &cond, std::vector<std::string> prefix) {
        const slang::ast::ConditionalStatement *current = &cond;
        std::string chainNegation;
        std::string out;

        while (true) {
            bool branchSupported = (current->conditions.size() == 1) && (current->conditions[0].pattern == nullptr);
            std::string condText;
            if (branchSupported) {
                const auto &c = current->conditions[0];
                if (exprHasUnsupportedKind(*c.expr)) {
                    branchSupported = false;
                    coverageInfo.statistic.unsupportedCondStmts.emplace_back(fmt::format("unsupported expression in if-condition: {}", c.expr->syntax ? std::string(c.expr->syntax->toString()) : std::string("<no_syntax>")));
                } else if (c.expr->syntax) {
                    condText = c.expr->syntax->toString();
                }
            } else {
                std::string raw = current->syntax ? std::string(current->syntax->toString()) : std::string("<no_syntax>");
                coverageInfo.statistic.unsupportedCondStmts.emplace_back(fmt::format("unsupported conditional (multi-condition / pattern): {}", raw));
            }

            const bool ifTrueEmpty = isEmptyBody(current->ifTrue);
            std::string ifKeyword  = out.empty() ? "if" : "else if";

            // Emit `[else ]if (cond) <wrappedBody>`.
            if (branchSupported) {
                std::vector<std::string> branchPrefix = prefix;
                if (!chainNegation.empty())
                    branchPrefix.push_back(chainNegation);
                std::string guard = buildGuard(branchPrefix, condText);

                std::string innerText;
                std::vector<std::string> nestedPrefix = branchPrefix;
                nestedPrefix.push_back(condText);
                innerText = rewriteStatement(current->ifTrue, nestedPrefix);
                innerText = stripBeginEnd(innerText);

                if (ifTrueEmpty) {
                    coverageInfo.statistic.unsupportedCondStmts.emplace_back(fmt::format("empty if-body skipped: {}", current->syntax ? std::string(current->syntax->toString()) : std::string("<no_syntax>")));
                    out += fmt::format("{} ({}) begin {} end\n", ifKeyword, condText, innerText);
                } else {
                    auto loc    = locationOf(current->ifTrue.syntax ? *current->ifTrue.syntax : *current->syntax);
                    uint64_t id = recordPath(guard, SignalInfo{"", "", loc.second, loc.first});
                    // The counter increment is wrapped in `ifndef NO_COVERAGE so
                    // that defining NO_COVERAGE removes every trace of coverage
                    // instrumentation (the directive survives the parse() +
                    // SyntaxPrinter round-trip because printFile enables
                    // setIncludeDirectives).
                    out += fmt::format("{} ({}) begin\n`ifndef NO_COVERAGE\nif(_COV_EN) _{}__COV_BIN_EXPR_CNT++;\n`endif\n{} end\n", ifKeyword, condText, id, innerText);
                }
            } else {
                // Unsupported: keep the original source text intact. Do NOT
                // call rewriteStatement here — it would register phantom
                // counters for nested supported branches that will never be
                // incremented (the raw syntax dump below does not contain
                // counter increments).
                std::string prefix_kw = out.empty() ? "" : "else ";
                if (current->syntax) {
                    out += prefix_kw + std::string(current->syntax->toString()) + "\n";
                } else {
                    out += prefix_kw + (current->ifTrue.syntax ? std::string(current->ifTrue.syntax->toString()) : std::string("<no_syntax>")) + "\n";
                }
                return out;
            }

            if (branchSupported) {
                std::string thisNeg = "!(" + condText + ")";
                if (chainNegation.empty())
                    chainNegation = thisNeg;
                else
                    chainNegation += " && " + thisNeg;
            }

            if (!current->ifFalse)
                break;
            if (current->ifFalse->kind == slang::ast::StatementKind::Conditional) {
                current = &current->ifFalse->as<slang::ast::ConditionalStatement>();
                continue;
            }

            const auto &elseStmt = *current->ifFalse;
            if (isEmptyBody(elseStmt)) {
                coverageInfo.statistic.unsupportedCondStmts.emplace_back(fmt::format("empty else-body skipped: {}", current->syntax ? std::string(current->syntax->toString()) : std::string("<no_syntax>")));
                break;
            }
            std::vector<std::string> elsePrefix = prefix;
            if (!chainNegation.empty())
                elsePrefix.push_back(chainNegation);
            std::string guard = buildGuard(elsePrefix, "");

            std::string innerText = rewriteStatement(elseStmt, elsePrefix);
            innerText             = stripBeginEnd(innerText);
            auto loc              = locationOf(elseStmt.syntax ? *elseStmt.syntax : *current->syntax);
            uint64_t id           = recordPath(guard, SignalInfo{"", "", loc.second, loc.first});
            out += fmt::format("else begin\n`ifndef NO_COVERAGE\nif(_COV_EN) _{}__COV_BIN_EXPR_CNT++;\n`endif\n{} end\n", id, innerText);
            break;
        }
        return out;
    }

    // Top-level entry for procedural-block traversal. Walks the body and
    // schedules every top-level ConditionalStatement for source rewriting.
    //
    //   Relationship with rewriteStatement / rewriteConditional:
    //
    //     collectCondPaths()       <-- entry from procedural block walker
    //         |
    //         | when stmt is Conditional
    //         v
    //     rewriteConditional()     <-- generates wrapped SV for the WHOLE chain
    //         |  (recursively calls rewriteStatement on each branch body,
    //         |   which may call rewriteConditional again for nested if)
    //         v
    //     wrappedText  ->  CondPathTopRewrite { topStmt, wrappedText }
    //                      stored in coverageInfo.condRewrites
    //                      consumed by the writer's replace() call.
    //
    //   For non-Conditional statements (Block/List/loops/Case/...) this walker
    //   recurses into nested statements so any top-level Conditional discovered
    //   inside them is registered as its own CondPathTopRewrite anchor.
    void collectCondPaths(const slang::ast::Statement &stmt, std::vector<std::string> prefix) {
        using slang::ast::StatementKind;
        switch (stmt.kind) {
        case StatementKind::Conditional: {
            const auto &cond    = stmt.as<slang::ast::ConditionalStatement>();
            std::string wrapped = rewriteConditional(cond, prefix);
            CondPathTopRewrite r;
            r.topStmt     = cond.syntax;
            r.wrappedText = std::move(wrapped);
            coverageInfo.condRewrites.push_back(std::move(r));
            break;
        }
        case StatementKind::Block:
            collectCondPaths(stmt.as<slang::ast::BlockStatement>().body, prefix);
            break;
        case StatementKind::List: {
            const auto &lst = stmt.as<slang::ast::StatementList>();
            for (auto child : lst.list)
                collectCondPaths(*child, prefix);
            break;
        }
        case StatementKind::Timed:
            collectCondPaths(stmt.as<slang::ast::TimedStatement>().stmt, prefix);
            break;
        case StatementKind::ForLoop:
            collectCondPaths(stmt.as<slang::ast::ForLoopStatement>().body, prefix);
            break;
        case StatementKind::RepeatLoop:
            collectCondPaths(stmt.as<slang::ast::RepeatLoopStatement>().body, prefix);
            break;
        case StatementKind::ForeachLoop:
            collectCondPaths(stmt.as<slang::ast::ForeachLoopStatement>().body, prefix);
            break;
        case StatementKind::WhileLoop:
            collectCondPaths(stmt.as<slang::ast::WhileLoopStatement>().body, prefix);
            break;
        case StatementKind::DoWhileLoop:
            collectCondPaths(stmt.as<slang::ast::DoWhileLoopStatement>().body, prefix);
            break;
        case StatementKind::ForeverLoop:
            collectCondPaths(stmt.as<slang::ast::ForeverLoopStatement>().body, prefix);
            break;
        case StatementKind::Case: {
            const auto &cs = stmt.as<slang::ast::CaseStatement>();
            for (const auto &item : cs.items)
                collectCondPaths(*item.stmt, prefix);
            if (cs.defaultCase)
                collectCondPaths(*cs.defaultCase, prefix);
            break;
        }
        case StatementKind::PatternCase: {
            const auto &cs = stmt.as<slang::ast::PatternCaseStatement>();
            for (const auto &item : cs.items)
                collectCondPaths(*item.stmt, prefix);
            if (cs.defaultCase)
                collectCondPaths(*cs.defaultCase, prefix);
            break;
        }
        case StatementKind::RandCase: {
            const auto &rc = stmt.as<slang::ast::RandCaseStatement>();
            for (const auto &item : rc.items)
                collectCondPaths(*item.stmt, prefix);
            break;
        }
        case StatementKind::Wait:
            collectCondPaths(stmt.as<slang::ast::WaitStatement>().stmt, prefix);
            break;
        case StatementKind::ImmediateAssertion: {
            const auto &ia = stmt.as<slang::ast::ImmediateAssertionStatement>();
            if (ia.ifTrue)
                collectCondPaths(*ia.ifTrue, prefix);
            if (ia.ifFalse)
                collectCondPaths(*ia.ifFalse, prefix);
            break;
        }
        case StatementKind::WaitOrder: {
            const auto &wo = stmt.as<slang::ast::WaitOrderStatement>();
            if (wo.ifTrue)
                collectCondPaths(*wo.ifTrue, prefix);
            if (wo.ifFalse)
                collectCondPaths(*wo.ifFalse, prefix);
            break;
        }
        default:
            break;
        }
    }
};

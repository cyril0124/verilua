#pragma once

#include "config.h"
#include "cov_exporter.h"
#include "debug.h"

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
        coverageInfo.binExprMap.clear();
        coverageInfo.statistic.netCount          = 0;
        coverageInfo.statistic.varCount          = 0;
        coverageInfo.statistic.duplicateNetCount = 0;
        coverageInfo.statistic.binExprCount      = 0;
        coverageInfo.statistic.literalEqualNetVec.clear();
        coverageInfo.subModuleSet = moduleOption.subModuleSet;
    }

    bool conAssignSetInit = false;
    std::unordered_set<std::string> conAssignSet;
    void handle(const slang::syntax::ModuleDeclarationSyntax &syntax) {
        if (syntax.header->name.rawText() == moduleOption.moduleName) {
            findModule = true;
            auto def   = compilation->getDefinition(compilation->getRoot(), syntax);
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
                auto line = compilation->getSourceManager()->getLineNumber(net.location) - 2;
                INFO_PRINT("\t[{}] NetSymbol: {}, line: {}, type: <{}, {}>", count++, net.name, line, toString(net.getType().kind), net.getType().toString());

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
                if (v.maybeLiteralEqual || v.maybeIdentifierEqual) {
                    bool isLiteralEqualNet    = true;
                    bool isIdentifierEqualNet = true;

                    if (conAssignSet.count(std::string(net.name))) {
                        isLiteralEqualNet    = false;
                        isIdentifierEqualNet = false;
                    } else {
                        // If the NetSymbol has been assigned by continuous assign after the net is defined, it is not a literal equal net.
                        auto conAssignSymIten = inst->body.membersOfType<slang::ast::ContinuousAssignSymbol>();
                        if (!conAssignSetInit) {
                            for (const auto &conAssignSym : conAssignSymIten) {
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

                        for (const auto &conAssignSym : conAssignSymIten) {
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

                coverageInfo.netMap.emplace(net.name, SignalInfo{std::string(toString(net.getType().kind)), std::string(net.getType().toString()), line});
            }

            count = 0;

            auto varIter = inst->body.membersOfType<slang::ast::VariableSymbol>();
            for (const auto &var : varIter) {
                auto line = compilation->getSourceManager()->getLineNumber(var.location) - 2;
                INFO_PRINT("\t[{}] VariableSymbol: {}, line: {}, type: <{}, {}>", count++, var.name, line, toString(var.getType().kind), var.getType().toString());

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

                coverageInfo.varMap.emplace(var.name, SignalInfo{std::string(toString(var.getType().kind)), std::string(var.getType().toString()), line});
            }

            // TODO: Optimize some simple expr? (e.g. assign a = c & d;)
            auto conAssignSymIten = inst->body.membersOfType<slang::ast::ContinuousAssignSymbol>();
            for (const auto &conAssignSym : conAssignSymIten) {
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

            count = 0;
            std::unordered_set<std::string> binExprSet;
            auto procIter = inst->body.membersOfType<slang::ast::ProceduralBlockSymbol>();
            for (const auto &proc : procIter) {

                struct CondStmtVisitior : public slang::ast::ASTVisitor<CondStmtVisitior, true, true> {
                    int depth = 0;
                    int &count;
                    slang::ast::Compilation *compilation;
                    std::vector<CondInfo> condInfoVec;
                    std::unordered_map<std::string, SignalInfo> &binExprMap;
                    std::unordered_set<std::string> &binExprSet;

                    CondStmtVisitior(int &count, slang::ast::Compilation *compilation, std::unordered_map<std::string, SignalInfo> &binExprMap, std::unordered_set<std::string> &binExprSet) : count(count), compilation(compilation), binExprMap(binExprMap), binExprSet(binExprSet) {}

                    void handle(const slang::ast::ConditionalStatement &cond) {
                        depth++;

                        assert(cond.conditions.size() == 1 && "TODO: support multiple conditions");
                        auto &c    = cond.conditions[0];
                        auto ckind = c.expr->kind;
                        if (ckind == slang::ast::ExpressionKind::BinaryOp || ckind == slang::ast::ExpressionKind::NamedValue || ckind == slang::ast::ExpressionKind::UnaryOp || ckind == slang::ast::ExpressionKind::ElementSelect) {
                            // TODO: NamedValue is a signal name, and it is not a binary expression, so we can reuse netMap or varMap

                            cond.visitExprs(makeVisitor([&](auto &, const slang::ast::Expression &expr) {
                                if (expr.kind != slang::ast::ExpressionKind::BinaryOp && expr.kind != slang::ast::ExpressionKind::NamedValue) {
                                    return;
                                }

                                auto s           = expr.syntax->toString();
                                std::string type = "if";

                                // Unique binary expression
                                if (binExprSet.count(s)) {
                                    // TODO: It is possible duplicate?
                                    return;
                                }
                                binExprSet.insert(s);
                                count++;

                                auto parent = expr.syntax->parent;
                                assert(parent != nullptr);
                                while (parent->kind != slang::syntax::SyntaxKind::ConditionalStatement) {
                                    parent = parent->parent;
                                    assert(parent != nullptr);
                                }

                                parent = parent->parent;
                                assert(parent != nullptr);
                                if (parent->kind == slang::syntax::SyntaxKind::ElseClause) {
                                    type = "elseif";
                                }

                                auto line = compilation->getSourceManager()->getLineNumber(expr.sourceRange.start()) - 2;
                                INFO_PRINT("\t[{}] {}-Expression: {}, line: {}", count, toString(expr.kind), s, line);

                                condInfoVec.emplace_back(depth, type, s);
                                binExprMap.emplace(s, SignalInfo{"", "", line});
                            }));
                        } else if (ckind == slang::ast::ExpressionKind::IntegerLiteral) {
                            // do nothing
                        } else {
                            PANIC("TODO: support other expression kind", toString(ckind), c.expr->syntax->toString(), cond.syntax->toString());
                        }

                        visitDefault(cond);
                        depth--;
                    }
                };
                CondStmtVisitior condStmtVisitor(count, compilation, coverageInfo.binExprMap, binExprSet);
                proc.visit(condStmtVisitor);

                // TODO: Binary expression path finder
                INFO_PRINT("\t>>>>>>>> Binary Expression Info <<<<<<<<<");
                for (auto &condInfo : condStmtVisitor.condInfoVec) {
                    INFO_PRINT("\t\t{{ depth: {}, type: {}, expr: {} }},", condInfo.depth, condInfo.type, condInfo.expr);
                }
                INFO_PRINT("\t<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
                // extractConditionCombinations(condStmtVisitor.condInfoVec);
            }

            coverageInfo.statistic.netCount     = coverageInfo.netMap.size();
            coverageInfo.statistic.varCount     = coverageInfo.varMap.size();
            coverageInfo.statistic.binExprCount = coverageInfo.binExprMap.size();
        } else {
            visitDefault(syntax);
        }
    }
};

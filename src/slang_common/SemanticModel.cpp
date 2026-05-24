#include "SemanticModel.h"
#include "fmt/color.h"
#include "slang/ast/Symbol.h"
#include "slang/ast/symbols/VariableSymbols.h"
#include "slang/syntax/AllSyntax.h"
#include "slang/syntax/SyntaxKind.h"
#include <cassert>
#include <iostream>

using namespace std;
using namespace slang;
using namespace slang::syntax;
using namespace slang::ast;

// clang-format off
const Symbol* SemanticModel::getDeclaredSymbol(const syntax::SyntaxNode& syntax) {
    // If we've already cached this node, return that.
    if (auto it = symbolCache.find(&syntax); it != symbolCache.end())
        return it->second;

    // If we hit the top of the syntax tree, look in the compilation for the correct symbol.
    if (syntax.kind == SyntaxKind::CompilationUnit) {
        auto result = compilation.getCompilationUnit(syntax.as<CompilationUnitSyntax>());
        if (result)
            symbolCache[&syntax] = result;
        return result;
    }
    else if (syntax.kind == SyntaxKind::ModuleDeclaration ||
             syntax.kind == SyntaxKind::InterfaceDeclaration ||
             syntax.kind == SyntaxKind::ProgramDeclaration) {
        auto [parentScope, parentSym] = getParent(syntax);
        if (!parentScope)
            parentScope = &compilation.getRoot();

        auto def = compilation.getDefinition(*parentScope, syntax.as<ModuleDeclarationSyntax>());

        if (!def)
            return nullptr;

        // fmt::println("[SemanticModel] defName: {}", def->name);

        // There is no symbol to use here so create a placeholder instance.
        auto result = &InstanceSymbol::createDefault(compilation, *def);
        symbolCache[&syntax] = result;
        return result;
    }

    // Otherwise try to find the parent symbol first.
    auto [parentScope, parentSym] = getParent(syntax);
    if (!parentSym)
        return nullptr;

    // If this is a type alias, unwrap its target type to look at the syntax node.
    if (parentSym->kind == SymbolKind::TypeAlias) {
        auto& target = parentSym->as<TypeAliasType>().targetType.getType();
        if (target.getSyntax() == &syntax) {
            symbolCache.emplace(&syntax, &target);
            return &target;
        }
        return nullptr;
    }

    if (!parentScope)
        return nullptr;

    // Search among the parent's children to see if we can find ourself.
    for (auto& child : parentScope->members()) {
        // fmt::println("[SemanticModel] synKind: {} <==> {}", toString(child.getSyntax()->kind), toString(syntax.kind));
        if (child.getSyntax() == &syntax) {
            // We found ourselves, hurray.
            symbolCache.emplace(&syntax, &child);
            return &child;
        }

        if(syntax.kind == SyntaxKind::NetDeclaration) {
            auto &syntax_1 = syntax.as<NetDeclarationSyntax>();
            auto syntax_2 = syntax_1.declarators[0];
            if(child.getSyntax() == syntax_2) {
                fmt::println("found! => {}", syntax_2->name.rawText());
                return &child;
                // assert(false);
            }
        }
    }

    return nullptr;
}

const CompilationUnitSymbol* SemanticModel::getDeclaredSymbol(const CompilationUnitSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<CompilationUnitSymbol>() : nullptr;
}

const InstanceSymbol* SemanticModel::getDeclaredSymbol(const HierarchyInstantiationSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<InstanceSymbol>() : nullptr;
}

const StatementBlockSymbol* SemanticModel::getDeclaredSymbol(const BlockStatementSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<StatementBlockSymbol>() : nullptr;
}

const ProceduralBlockSymbol* SemanticModel::getDeclaredSymbol(const ProceduralBlockSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<ProceduralBlockSymbol>() : nullptr;
}

const GenerateBlockSymbol* SemanticModel::getDeclaredSymbol(const IfGenerateSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<GenerateBlockSymbol>() : nullptr;
}

const GenerateBlockArraySymbol* SemanticModel::getDeclaredSymbol(const LoopGenerateSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<GenerateBlockArraySymbol>() : nullptr;
}

const SubroutineSymbol* SemanticModel::getDeclaredSymbol(const FunctionDeclarationSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<SubroutineSymbol>() : nullptr;
}

const EnumType* SemanticModel::getDeclaredSymbol(const EnumTypeSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<EnumType>() : nullptr;
}

const TypeAliasType* SemanticModel::getDeclaredSymbol(const TypedefDeclarationSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<TypeAliasType>() : nullptr;
}

const NetSymbol* SemanticModel::getDeclaredSymbol(const DeclaratorSyntax& syntax) {
    auto result = getDeclaredSymbol((const SyntaxNode&)syntax);
    return result ? &result->as<NetSymbol>() : nullptr;
}

std::pair<const Scope*, const Symbol*> SemanticModel::getParent(const SyntaxNode& syntax) {
    auto parent = syntax.parent ? getDeclaredSymbol(*syntax.parent) : nullptr;
    if (!parent)
        return {nullptr, nullptr};

    if (parent->kind == SymbolKind::Instance)
        parent = &parent->as<InstanceSymbol>().body;
    else if (!parent->isScope())
        return {nullptr, parent};

    return {&parent->as<Scope>(), parent};
}

const InstanceSymbol *SemanticModel::syntaxToInstanceSymbol(const syntax::SyntaxNode &syntax) {
    auto currSyntax = &syntax;
    uint32_t iter   = 0;
    while (currSyntax->kind != SyntaxKind::ModuleDeclaration) {
        currSyntax = currSyntax->parent;
        iter++;
        if (iter >= 1000) {
            assert(false && "cannot found any module declaration syntax!");
        }
    }
    auto r      = &compilation.getRoot();
    auto &rs    = r->as<Scope>();
    auto def    = compilation.getDefinition(rs, currSyntax->as<ModuleDeclarationSyntax>());
    auto result = &InstanceSymbol::createDefault(compilation, *def);
    return result;
}

const NetSymbol &SemanticModel::getNetSymbol(const InstanceSymbol *instSym, std::string_view identifierName) {
    for (auto &sym : instSym->body.members()) {
        if (sym.kind == SymbolKind::Net) {
            auto &netSym = sym.as<NetSymbol>();
            if (netSym.name == identifierName) {
                return netSym;
            }
        }
    }

    std::cout << "Assertion failed: Not found NetSymbol! "
                << "Identifier: " << identifierName << std::endl;

    assert(false);
}
// clang-format on

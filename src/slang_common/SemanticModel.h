#pragma once

#include "SlangCommon.h"
#include "slang/ast/symbols/BlockSymbols.h"
#include "slang/ast/symbols/CompilationUnitSymbols.h"
#include "slang/ast/symbols/MemberSymbols.h"
#include "slang/ast/symbols/PortSymbols.h"
#include "slang/ast/symbols/SubroutineSymbols.h"
#include "slang/ast/symbols/VariableSymbols.h"
#include "slang/ast/types/AllTypes.h"
#include "slang/syntax/AllSyntax.h"

using namespace std;
using namespace slang;
using namespace slang::syntax;
using namespace slang::ast;

class SemanticModel {

  public:
    explicit SemanticModel(Compilation &compilation) : compilation(compilation) {}

    const Symbol *getDeclaredSymbol(const syntax::SyntaxNode &syntax);

    const CompilationUnitSymbol *getDeclaredSymbol(const CompilationUnitSyntax &syntax);

    const InstanceSymbol *getDeclaredSymbol(const HierarchyInstantiationSyntax &syntax);

    const StatementBlockSymbol *getDeclaredSymbol(const BlockStatementSyntax &syntax);

    const ProceduralBlockSymbol *getDeclaredSymbol(const ProceduralBlockSyntax &syntax);

    const GenerateBlockSymbol *getDeclaredSymbol(const IfGenerateSyntax &syntax);

    const GenerateBlockArraySymbol *getDeclaredSymbol(const LoopGenerateSyntax &syntax);

    const SubroutineSymbol *getDeclaredSymbol(const FunctionDeclarationSyntax &syntax);

    const EnumType *getDeclaredSymbol(const EnumTypeSyntax &syntax);

    const TypeAliasType *getDeclaredSymbol(const TypedefDeclarationSyntax &syntax);

    const NetSymbol *getDeclaredSymbol(const DeclaratorSyntax &syntax);

    const InstanceSymbol *syntaxToInstanceSymbol(const syntax::SyntaxNode &syntax);

    const NetSymbol &getNetSymbol(const InstanceSymbol *instSym, std::string_view identifierName);

  private:
    std::pair<const Scope *, const Symbol *> getParent(const SyntaxNode &syntax);

    Compilation &compilation;
    flat_hash_map<const syntax::SyntaxNode *, const Symbol *> symbolCache;
};

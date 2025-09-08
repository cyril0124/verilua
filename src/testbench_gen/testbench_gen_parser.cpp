#include "testbench_gen.h"

void TestbenchGenParser::handle(const InstanceBodySymbol &ast) {
    if (ast.name == topName) {
        for (auto &p : ast.getParameters()) {
            if (p->isPortParam()) {
                auto maybeParamDeclSyn = p->defaultValSyntax->parent;
                ASSERT(toString(maybeParamDeclSyn->kind) == "ParameterDeclaration", "Expected ParameterDeclaration", toString(maybeParamDeclSyn->kind));

                auto &paramDeclSyn = maybeParamDeclSyn->as<slang::syntax::ParameterDeclarationSyntax>();
                auto paramTypeStr  = toString(paramDeclSyn.type->kind);

                std::string typeStr = "";
                if (paramTypeStr == "StringType") {
                    typeStr = "string";
                } else if (paramTypeStr == "IntType") {
                    typeStr = "int";
                } else if (paramTypeStr == "IntegerType") {
                    typeStr = "integer";
                } else if (paramTypeStr == "RealType") {
                    typeStr = "real";
                } else if (paramTypeStr == "TimeType") {
                    typeStr = "time";
                } else if (paramTypeStr == "ImplicitType") {
                    typeStr = "";
                } else {
                    PANIC("TODO: Unsupported parameter type", paramTypeStr);
                }
                portParamStmts.push_back(fmt::format("parameter {} {}", typeStr, p->defaultValSyntax->toString()));
                portParamInstStmts.push_back(fmt::format(".{0}({0})", p->symbol.name));
            }
        }

        auto pl = ast.getPortList();
        for (auto p : pl) {
            auto &port         = p->as<PortSymbol>();
            auto &pType        = port.getType();
            auto &dir          = port.direction;
            auto &internalKind = port.internalSymbol->kind;
            auto arraySize     = 0;

            if (pType.kind == slang::ast::SymbolKind::ScalarType) {
                /// Represents the single-bit scalar types.
                auto &pt = pType.as<ScalarType>();
            } else if (pType.kind == slang::ast::SymbolKind::PackedArrayType) {
                /// Represents a packed array of some simple element type
                /// (vectors, packed structures, other packed arrays).
                auto &pt = pType.as<PackedArrayType>();
            } else if (pType.kind == slang::ast::SymbolKind::FixedSizeUnpackedArrayType) {
                /// Represents a fixed size unpacked array (as opposed to a
                /// dynamically sized unpacked array, associative array, or queue).
                auto &pt  = pType.as<FixedSizeUnpackedArrayType>();
                arraySize = pt.getFixedRange().width();
                ASSERT(!pt.isDynamicallySizedArray(), "Expected fixed size array", port.name);
            } else {
                ASSERT(false, "Unknown port type kind", toString(pType.kind));
            }

            if (internalKind == SymbolKind::Net) {
                auto &net  = port.internalSymbol->as<NetSymbol>();
                auto dType = net.netType.getDataType().toString();

                if (verbose)
                    fmt::println("[TestbenchGenParser] [Net] portName: {} portWidth: {} "
                                 "pType: {} dir: {} arraySize: {} dType: {}",
                                 port.name, pType.getBitWidth(), pType.toString(), toString(port.direction), arraySize, dType);
            } else if (internalKind == SymbolKind::Variable) {
                auto &var = port.internalSymbol->as<VariableSymbol>();

                if (verbose)
                    fmt::println("[TestbenchGenParser] [Var] portName: {} portWidth: {} "
                                 "pType: {} dir: {} arraySize: {}",
                                 port.name, pType.getBitWidth(), pType.toString(), toString(port.direction), arraySize);
            } else {
                ASSERT(false, "Unknown internal kind", toString(internalKind));
            }

            std::string declStr = "";
            if (arraySize != 0) { // is FixedSizeUnpackedArrayType
                if (dir == ArgumentDirection::In) {
                    declStr = replaceString(replaceString(pType.toString(), "logic", "reg"), "$", std::string(" ") + std::string(port.name));
                } else if (dir == ArgumentDirection::Out) {
                    declStr = replaceString(replaceString(pType.toString(), "logic", "wire"), "$", std::string(" ") + std::string(port.name));
                } else {
                    ASSERT(false, "Unknown direction", toString(dir));
                }
            }

            portInfos.push_back(PortInfo{std::string(port.name), std::string(toString(port.direction)), pType.toString(), declStr, arraySize, portIdAllocator});
            portIdAllocator++;
        }
    }

    if (verbose)
        fmt::println("[TestbenchGenParser] get module:{}", ast.name);
}
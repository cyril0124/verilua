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

        // Check for ImplicitAnsiPortSyntax
        ast.getSyntax()->visit(makeSyntaxVisitor([&](auto &visitor, const slang::syntax::ImplicitAnsiPortSyntax &node) {
            // ImplicitAnsiPort:
            // e.g.
            //  module top(
            //      input wire clk, <----
            //      output reg value
            //  );
            //
            // endmodule
            auto headerKind = node.header->kind;
            auto name       = node.declarator->name.rawText();

            // clang-format off
            PortInfo p = {
                .dir = "",
                .type = "",
                .name = std::string(node.declarator->name.rawText()),
                .dimensions = {},
                .dimSizes = {},
                .isNet = headerKind == slang::syntax::SyntaxKind::NetPortHeader,
                .id = portIdAllocator
            };
            portIdAllocator++;
            // clang-format on

            // fmt::println("implicitAnsiPort: name: <{}>", name);

            if (headerKind == slang::syntax::SyntaxKind::NetPortHeader) {
                auto &netPortHeader = node.header->as<slang::syntax::NetPortHeaderSyntax>();
                auto dataType       = netPortHeader.dataType;
                p.dir               = netPortHeader.direction.valueText();
                p.type              = "wire " + dataType->toString();
                // fmt::println("\tnetPortHeader: dataType: <{}>, dir: <{}>", dataType->toString(), netPortHeader.direction.valueText());
            } else if (headerKind == slang::syntax::SyntaxKind::VariablePortHeader) {
                auto &varPortHeader = node.header->as<slang::syntax::VariablePortHeaderSyntax>();
                auto dataType       = varPortHeader.dataType;
                auto dataTypeStr    = dataType->toString();
                p.dir               = varPortHeader.direction.valueText();
                if (!containsString(dataTypeStr, "reg") && !containsString(dataTypeStr, "wire") && !containsString(dataTypeStr, "logic") && !containsString(dataTypeStr, "bit")) {
                    // e.g. input value(no type specified)
                    p.type = "wire " + dataTypeStr;
                } else {
                    p.type = dataTypeStr;
                }
                // fmt::println("\tvarPortHeader: dataType: <{}>, dir: <{}>", dataType->toString(), varPortHeader.direction.valueText());
            } else {
                PANIC("TODO: Unsupported PortDeclarationSyntax header kind", toString(headerKind));
            }

            for (auto dim : node.declarator->dimensions) {
                ASSERT(dim->specifier->kind == slang::syntax::SyntaxKind::RangeDimensionSpecifier, "Expected RangeDimensionSpecifier", toString(dim->specifier->kind));
                auto &specifier = dim->specifier->as<slang::syntax::RangeDimensionSpecifierSyntax>();

                ASSERT(specifier.selector->kind == slang::syntax::SyntaxKind::SimpleRangeSelect, "Expected SimpleRangeSelect", toString(dim->specifier->kind));
                auto &rangeSel = specifier.selector->as<slang::syntax::RangeSelectSyntax>();

                std::string dimSizeStr;
                bool gotZero = false;
                if (rangeSel.left->toString() == "0") {
                    gotZero    = true;
                    dimSizeStr = fmt::format("{} - {} + 1", rangeSel.right->toString(), rangeSel.left->toString());
                } else if (rangeSel.right->toString() == "0") {
                    gotZero    = true;
                    dimSizeStr = fmt::format("{} - {} + 1", rangeSel.left->toString(), rangeSel.right->toString());
                }
                ASSERT(gotZero, "Expected one side of range to be 0", rangeSel.left->toString(), rangeSel.right->toString());

                p.dimensions.push_back(dim->toString());
                p.dimSizes.push_back(dimSizeStr);
                // fmt::println("\tdim: {}, <{}>, <{}>, <{}>", dim->toString(), rangeSel.left->toString(), rangeSel.right->toString(), dimSizeStr);
            }
            // fmt::println("{}", p.toString());
            // fmt::println("{}", p.toDeclString());
            // fmt::println("");
            portInfos.push_back(p);
        }));

        // Check for PortDeclarationSyntax, for non-ansi ports
        ast.getSyntax()->visit(makeSyntaxVisitor([&](auto &visitor, const slang::syntax::PortDeclarationSyntax &node) { PANIC("TODO: Non-ansi port declaration not supported yet", node.toString()); }));
    }

    if (verbose)
        fmt::println("[TestbenchGenParser] get module:{}", ast.name);
}
#include "testbench_gen.h"

void TestbenchGenParser::handle(const InstanceBodySymbol &ast) {
    if (ast.name == topName) {
        for (auto &p : ast.getParameters()) {
            if (p->isPortParam()) {
                auto maybeParamDeclSyn = p->defaultValSyntax->parent;
                ASSERT(toString(maybeParamDeclSyn->kind) == "ParameterDeclaration", "Expected ParameterDeclaration", toString(maybeParamDeclSyn->kind));

                auto &paramDeclSyn = maybeParamDeclSyn->as<slang::syntax::ParameterDeclarationSyntax>();
                auto paramTypeStr  = toString(paramDeclSyn.type->kind);

                std::string typeStr;
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
                } else if (paramTypeStr == "ShortIntType") {
                    typeStr = "shortint";
                } else if (paramTypeStr == "LongIntType") {
                    typeStr = "longint";
                } else if (paramTypeStr == "ByteType") {
                    typeStr = "byte";
                } else if (paramTypeStr == "ShortRealType") {
                    typeStr = "shortreal";
                } else if (paramTypeStr == "BitType" || paramTypeStr == "LogicType") {
                    // For bit/logic types with optional width, use the full type string
                    typeStr = paramDeclSyn.type->toString();
                } else if (paramTypeStr == "ImplicitType") {
                    typeStr = "";
                } else {
                    PANIC("TODO: Unsupported parameter type", paramTypeStr);
                }
                portParamStmts.push_back(fmt::format("parameter {} {}", typeStr, p->defaultValSyntax->toString()));
                portParamInstStmts.push_back(fmt::format(".{0}({0})", p->symbol.name));
            }
        }

        auto portList      = ast.getPortList();
        auto getPortSymbol = [&](const std::string &name) {
            const slang::ast::PortSymbol *ret = nullptr;
            for (auto p : portList) {
                auto &port = p->as<PortSymbol>();
                if (port.name == name) {
                    ret = &port;
                }
            }
            ASSERT(ret != nullptr, "Could not find port", name);
            return ret;
        };

        auto getPortDir = [&](const std::string &name) {
            auto port = getPortSymbol(name);
            if (port->direction == slang::ast::ArgumentDirection::In) {
                return "input";
            }
            if (port->direction == slang::ast::ArgumentDirection::Out) {
                return "output";
            }
            if (port->direction == slang::ast::ArgumentDirection::InOut) {
                return "inout";
            }
            PANIC("TODO: Unsupported port direction", toString(port->direction));
        };

        auto getPortType = [&](const std::string &name) {
            auto port = getPortSymbol(name);
            return port->getType().toString();
        };

        // Check for ImplicitAnsiPortSyntax
        std::string lastAnsiPortTypeStr;
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

            if (headerKind == slang::syntax::SyntaxKind::NetPortHeader) {
                auto &netPortHeader = node.header->as<slang::syntax::NetPortHeaderSyntax>();
                auto dataTypeStr    = netPortHeader.dataType->toString();
                if (dataTypeStr == "") {
                    if (getPortType(p.name) == "logic") {
                        // e.g.
                        //      input clk, <--- no type
                        // Here `clk` is `wire` type
                        dataTypeStr = "wire";
                    } else {
                        // e.g.
                        //  input wire [3:0] foo,
                        //                   bar, <--- no type
                        //
                        // Here `bar` has no type, so we use the type of `foo`
                        ASSERT(lastAnsiPortTypeStr != "", "Expected lastAnsiPortTypeStr to be set", p.name, getPortType(p.name));
                        dataTypeStr = lastAnsiPortTypeStr;
                    }
                } else if (!containsString(dataTypeStr, "reg") && !containsString(dataTypeStr, "wire") && !containsString(dataTypeStr, "logic") && !containsString(dataTypeStr, "bit")) {
                    // NetPortHeader has no `wire` prefix, so add it here
                    dataTypeStr = "wire " + dataTypeStr;
                }
                p.dir  = getPortDir(p.name);
                p.type = dataTypeStr;
            } else if (headerKind == slang::syntax::SyntaxKind::VariablePortHeader) {
                auto &varPortHeader = node.header->as<slang::syntax::VariablePortHeaderSyntax>();
                auto dataTypeStr    = varPortHeader.dataType->toString();
                if (dataTypeStr == "") {
                    if (getPortType(p.name) == "logic") {
                        // e.g.
                        //      output value, <--- no type
                        dataTypeStr = "wire";
                    } else {
                        // e.g.
                        //      output reg [3:0] foo,
                        //                       bar, <--- no type
                        // Here `bar` has no type, so we use the type of `foo`
                        ASSERT(lastAnsiPortTypeStr != "", "Expected lastAnsiPortTypeStr to be set", p.name, getPortType(p.name));
                        dataTypeStr = lastAnsiPortTypeStr;
                    }
                } else if (!containsString(dataTypeStr, "reg") && !containsString(dataTypeStr, "wire") && !containsString(dataTypeStr, "logic") && !containsString(dataTypeStr, "bit")) {
                    // e.g.
                    //      input [WIDTH-1:0] foo, <--- no type
                    //      input [7:0] bar, <--- no type
                    dataTypeStr = "wire " + dataTypeStr;
                }
                p.dir  = getPortDir(p.name);
                p.type = dataTypeStr;
            } else {
                PANIC("TODO: Unsupported PortDeclarationSyntax header kind", toString(headerKind));
            }

            for (auto dim : node.declarator->dimensions) {
                std::string dimSizeStr;

                ASSERT(dim->specifier->kind == slang::syntax::SyntaxKind::RangeDimensionSpecifier, "Expected RangeDimensionSpecifier", toString(dim->specifier->kind));
                auto &specifier = dim->specifier->as<slang::syntax::RangeDimensionSpecifierSyntax>();

                auto selectorKind = specifier.selector->kind;
                if (selectorKind == slang::syntax::SyntaxKind::SimpleRangeSelect) {
                    // e.g.: logic a [3:0], logic a [WIDTH-1:0], logic a [0:WIDTH-1], etc
                    auto &rangeSel = specifier.selector->as<slang::syntax::RangeSelectSyntax>();
                    bool gotZero   = false;
                    if (rangeSel.left->toString() == "0") {
                        gotZero    = true;
                        dimSizeStr = fmt::format("{} - {} + 1", rangeSel.right->toString(), rangeSel.left->toString());
                    } else if (rangeSel.right->toString() == "0") {
                        gotZero    = true;
                        dimSizeStr = fmt::format("{} - {} + 1", rangeSel.left->toString(), rangeSel.right->toString());
                    }
                    ASSERT(gotZero, "Expected one side of range to be 0", rangeSel.left->toString(), rangeSel.right->toString());
                } else if (selectorKind == slang::syntax::SyntaxKind::BitSelect) {
                    // e.g.: logic a[12], logic a[WIDTH], logic a[WIDTH*2], logic a[WIDTH-1], etc
                    auto &bitSel = specifier.selector->as<slang::syntax::BitSelectSyntax>();
                    if (bitSel.expr->toString() == "0") {
                        dimSizeStr = "1";
                    } else {
                        dimSizeStr = bitSel.expr->toString();
                    }
                } else {
                    PANIC("TODO: Unsupported dimension specifier selector kind", toString(selectorKind));
                }

                p.dimensions.push_back(dim->toString());
                p.dimSizes.push_back(dimSizeStr);
            }
            if (verbose)
                fmt::println("[TestbenchGenParser] get ansi port: {}", p.toString());
            lastAnsiPortTypeStr = p.type;
            portInfos.push_back(p);
        }));

        // Check for PortDeclarationSyntax, for non-ansi ports
        // Non-ansi ports are declared inside the module body, not in the port list
        // e.g.:
        //   module top(clk, reset, data);
        //     input clk;           // PortDeclarationSyntax
        //     input reset;         // PortDeclarationSyntax
        //     output [7:0] data;   // PortDeclarationSyntax
        //   endmodule
        std::string lastNonAnsiPortTypeStr;
        ast.getSyntax()->visit(makeSyntaxVisitor([&](auto &visitor, const slang::syntax::PortDeclarationSyntax &node) {
            auto headerKind = node.header->kind;

            std::vector<PortInfo> ports;
            for (auto declarator : node.declarators) {
                // clang-format off
                PortInfo p = {
                    .dir = "",
                    .type = "",
                    .name = std::string(declarator->name.rawText()),
                    .dimensions = {},
                    .dimSizes = {},
                    .isNet = headerKind == slang::syntax::SyntaxKind::NetPortHeader,
                    .id = portIdAllocator
                };
                // clang-format on
                portIdAllocator++;
                for (auto dim : declarator->dimensions) {
                    std::string dimSizeStr;

                    ASSERT(dim->specifier->kind == slang::syntax::SyntaxKind::RangeDimensionSpecifier, "Expected RangeDimensionSpecifier", toString(dim->specifier->kind));
                    auto &specifier = dim->specifier->as<slang::syntax::RangeDimensionSpecifierSyntax>();

                    auto selectorKind = specifier.selector->kind;
                    if (selectorKind == slang::syntax::SyntaxKind::SimpleRangeSelect) {
                        // e.g.: logic a [3:0], logic a [WIDTH-1:0], logic a [0:WIDTH-1], etc
                        auto &rangeSel = specifier.selector->as<slang::syntax::RangeSelectSyntax>();
                        bool gotZero   = false;
                        if (rangeSel.left->toString() == "0") {
                            gotZero    = true;
                            dimSizeStr = fmt::format("{} - {} + 1", rangeSel.right->toString(), rangeSel.left->toString());
                        } else if (rangeSel.right->toString() == "0") {
                            gotZero    = true;
                            dimSizeStr = fmt::format("{} - {} + 1", rangeSel.left->toString(), rangeSel.right->toString());
                        }
                        ASSERT(gotZero, "Expected one side of range to be 0", rangeSel.left->toString(), rangeSel.right->toString());
                    } else if (selectorKind == slang::syntax::SyntaxKind::BitSelect) {
                        // e.g.: logic a[12], logic a[WIDTH], logic a[WIDTH*2], logic a[WIDTH-1], etc
                        auto &bitSel = specifier.selector->as<slang::syntax::BitSelectSyntax>();
                        if (bitSel.expr->toString() == "0") {
                            dimSizeStr = "1";
                        } else {
                            dimSizeStr = bitSel.expr->toString();
                        }
                    } else {
                        PANIC("TODO: Unsupported dimension specifier selector kind", toString(selectorKind));
                    }

                    p.dimensions.push_back(dim->toString());
                    p.dimSizes.push_back(dimSizeStr);
                }
                ports.push_back(p);
            }

            if (headerKind == slang::syntax::SyntaxKind::NetPortHeader) {
                auto &netPortHeader = node.header->as<slang::syntax::NetPortHeaderSyntax>();
                auto dataTypeStr    = netPortHeader.dataType->toString();
                for (auto &p : ports) {
                    if (dataTypeStr == "") {
                        if (getPortType(p.name) == "logic") {
                            // e.g.
                            //      input clk; <--- no type
                            // Here `clk` is `wire` type
                            dataTypeStr = "wire";
                        } else {
                            // e.g.
                            //  input wire [3:0] foo, bar; <--- bar has no type
                            //
                            // Here `bar` has no type, so we use the type of `foo`
                            ASSERT(lastNonAnsiPortTypeStr != "", "Expected lastNonAnsiPortTypeStr to be set", p.name, getPortType(p.name));
                            dataTypeStr = lastNonAnsiPortTypeStr;
                        }
                    } else if (!containsString(dataTypeStr, "reg") && !containsString(dataTypeStr, "wire") && !containsString(dataTypeStr, "logic") && !containsString(dataTypeStr, "bit")) {
                        // NetPortHeader has no `wire` prefix, so add it here
                        dataTypeStr = "wire " + dataTypeStr;
                    }
                    p.dir  = getPortDir(p.name);
                    p.type = dataTypeStr;
                }
            } else if (headerKind == slang::syntax::SyntaxKind::VariablePortHeader) {
                auto &varPortHeader = node.header->as<slang::syntax::VariablePortHeaderSyntax>();
                auto dataTypeStr    = varPortHeader.dataType->toString();
                for (auto &p : ports) {
                    if (dataTypeStr == "") {
                        if (getPortType(p.name) == "logic") {
                            // e.g.
                            //      output value; <--- no type
                            dataTypeStr = "wire";
                        } else {
                            // e.g.
                            //      output reg [3:0] foo, bar; <--- bar has no type
                            // Here `bar` has no type, so we use the type of `foo`
                            ASSERT(lastNonAnsiPortTypeStr != "", "Expected lastNonAnsiPortTypeStr to be set", p.name, getPortType(p.name));
                            dataTypeStr = lastNonAnsiPortTypeStr;
                        }
                    } else if (!containsString(dataTypeStr, "reg") && !containsString(dataTypeStr, "wire") && !containsString(dataTypeStr, "logic") && !containsString(dataTypeStr, "bit")) {
                        // e.g.
                        //      input [WIDTH-1:0] foo; <--- no type
                        //      input [7:0] bar; <--- no type
                        dataTypeStr = "wire " + dataTypeStr;
                    }
                    p.dir  = getPortDir(p.name);
                    p.type = dataTypeStr;
                }
            } else {
                PANIC("TODO: Unsupported PortDeclarationSyntax header kind", toString(headerKind));
            }

            if (verbose) {
                for (auto p : ports) {
                    fmt::println("[TestbenchGenParser] get non-ansi port: {}", p.toString());
                }
            }

            lastNonAnsiPortTypeStr = ports[0].type;

            portInfos.insert(portInfos.end(), ports.begin(), ports.end());
        }));
    }

    // Check if therer has any clocking logic(e.g. always block)
    ast.visit(makeVisitor([&](auto &, const slang::ast::ProceduralBlockSymbol &procBlock) {
        auto syn     = procBlock.getSyntax();
        auto synKind = syn->kind;
        if (synKind == slang::syntax::SyntaxKind::AlwaysBlock || synKind == slang::syntax::SyntaxKind::AlwaysFFBlock || synKind == slang::syntax::SyntaxKind::AlwaysLatchBlock) {
            hasProceduralBlock = true;
        }
        // fmt::println("procBlock.kind: {} synKind: {}", toString(procBlock.kind), toString(syn->kind));
    }));

    if (verbose)
        fmt::println("[TestbenchGenParser] get module:{}", ast.name);
}

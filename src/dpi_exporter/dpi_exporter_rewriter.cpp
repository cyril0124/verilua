#include "dpi_exporter_rewriter.h"

using namespace slang::parsing;

uint64_t globalHandleIdx = 0; // Each signal has its own handle value(integer)

void DPIExporterRewriter_1::handle(ModuleDeclarationSyntax &syntax) {
    if (syntax.header->name.rawText() == topModuleName) {
        MemberSyntax *firstMember = nullptr;
        for (auto m : syntax.members) {
            firstMember = m;
            break;
        }
        ASSERT(firstMember != nullptr, "TODO:");

        std::string dpiTickDeclParam = "";
        std::string dpiTickFuncParam = "";
        std::vector<std::string> dpiTickDeclParamVec;
        std::vector<std::string> dpiTickFuncParamVec;
        for (auto &p : portVec) {
            if (p.bitWidth == 1) {
                dpiTickDeclParamVec.push_back(fmt::format("\tinput bit {}_{}", p.hierPathName, p.name));
            } else {
                dpiTickDeclParamVec.push_back(fmt::format("\tinput bit [{}:0] {}_{}", p.bitWidth - 1, p.hierPathName, p.name));
            }

            dpiTickFuncParamVec.push_back(fmt::format("{}.{}", p.hierPathNameDot, p.name));
        }

        dpiTickDeclParam = fmt::to_string(fmt::join(dpiTickDeclParamVec, ",\n"));
        dpiTickFuncParam = fmt::to_string(fmt::join(dpiTickFuncParamVec, ", "));

        // Check clock signal
        auto instSym = model.syntaxToInstanceSymbol(syntax);
        auto clkSym  = instSym->body.find(clock);
        if (clkSym != nullptr) {
            auto bitWidth = 0;
            if (clkSym->kind == SymbolKind::Variable) {
                auto varSym = &clkSym->as<VariableSymbol>();
                bitWidth    = varSym->getType().getBitWidth();
            } else if (clkSym->kind == SymbolKind::Net) {
                auto netSym = &clkSym->as<NetSymbol>();
                bitWidth    = netSym->getType().getBitWidth();
            } else {
                PANIC("Unsupported clock type", toString(clkSym->kind));
            }
            ASSERT(bitWidth == 1, "Unsupported clock bitwidth", bitWidth);
        } else {
            PANIC("Cannot find clock signal", topModuleName, clock);
        }

        insertAtBack(syntax.members, parse(fmt::format(R"(
import "DPI-C" function void dpi_exporter_tick(
{}    
);

always @(posedge {}.{}) begin
    dpi_exporter_tick({});
end
)",
                                                       dpiTickDeclParam, topModuleName, clock, dpiTickFuncParam)));
        findTopModule = true;
    }
}

void DPIExporterRewriter::handle(ModuleDeclarationSyntax &syntax) {
    if (syntax.header->name.rawText() == moduleName) {
        fmt::println("[DPIExporterRewriter] found module: {}, writeGenStatment: {}, instSize: {}", moduleName, writeGenStatment, instSize);

        if (writeGenStatment) {
            std::string sv_dpiTickDeclParam = "";
            std::string sv_dpiTickFuncParam = "";
            std::string dpiTickDeclParam    = "";

            ASSERT(portVec.size() != 0, "Port vector is empty!", moduleName);

            std::vector<std::string> sv_dpiTickDeclParamVec;
            std::vector<std::string> sv_dpiTickFuncParamVec;
            std::vector<std::string> dpiTickDeclParamVec;
            for (int i = 0; i < portVec.size(); i++) {
                auto &p = portVec[i];
                if (p.bitWidth == 1) {
                    sv_dpiTickDeclParamVec.push_back(fmt::format("\t\tinput bit {}", p.name, p.name));
                } else {
                    sv_dpiTickDeclParamVec.push_back(fmt::format("\t\tinput bit [{}:0] {}", p.bitWidth - 1, p.name));
                }

                sv_dpiTickFuncParamVec.push_back(fmt::format("{}", p.name));

                if (p.bitWidth == 1) {
                    dpiTickDeclParamVec.push_back(fmt::format("const uint8_t {}", p.name));
                } else {
                    dpiTickDeclParamVec.push_back(fmt::format("const uint32_t *{}", p.name));
                }
            }

            sv_dpiTickDeclParam = fmt::to_string(fmt::join(sv_dpiTickDeclParamVec, ",\n"));
            sv_dpiTickFuncParam = fmt::to_string(fmt::join(sv_dpiTickFuncParamVec, ", "));
            dpiTickDeclParam    = fmt::to_string(fmt::join(dpiTickDeclParamVec, ", "));

            std::string dpiFuncBody     = "";
            std::string sv_genStatement = "\ngenerate // DPI Exporter\n";

            ASSERT(hierPathNameVec.size() == 0);
            for (int i = 0; i < hierPathVec.size(); i++) {
                std::string hierPathName = hierPathVec[i];
                std::replace(hierPathName.begin(), hierPathName.end(), '.', '_');
                hierPathNameVec.emplace_back(hierPathName);
            }

            bool isTopModule = instSize == 0;
            auto _instSize   = instSize;
            if (instSize == 0) {
                _instSize = 1;
            }

            for (int instId = 0; instId < _instSize; instId++) {
                std::string hierPath          = "";
                std::string hierPathName      = "";
                std::string dpiFuncNamePrefix = "";
                std::string dpiTickName       = "";

                if (!isTopModule) {
                    hierPath     = hierPathVec[instId];
                    hierPathName = hierPathNameVec[instId];
                } else {
                    hierPath     = moduleName;
                    hierPathName = moduleName;
                }

                dpiFuncNamePrefix = fmt::format("VERILUA_DPI_EXPORTER_{}", hierPathName);
                dpiTickName       = fmt::format("{}_TICK", dpiFuncNamePrefix);

                std::string sv_dpiBlock = "";
                if (!isTopModule) {
                    sv_dpiBlock += fmt::format("if(instId == {}) begin\n", instId);
                }
                sv_dpiBlock += fmt::format(R"(
    // hierPath: {}
    import "DPI-C" function void {}(
{}
    );

    always @(posedge {}) begin
        {}({});
    end
)",
                                           hierPath, dpiTickName, sv_dpiTickDeclParam, clock, dpiTickName, sv_dpiTickFuncParam);
                if (!isTopModule) {
                    sv_dpiBlock += "end\n";
                }

                sv_genStatement += sv_dpiBlock;

                // ----------------------------------------------------------------------
                // Generate DPI file(C++)
                // ----------------------------------------------------------------------
                dpiFuncBody += fmt::format("extern \"C\" void {}({}) {{\n", dpiTickName, dpiTickDeclParam);
                dpiFuncFileContent += fmt::format("// hierPath: {}\n", hierPath);
                for (auto &p : portVec) {
                    auto beatSize   = coverWith32(p.bitWidth);
                    auto signalName = fmt::format("__{}_{}", hierPathName, p.name);
                    ASSERT(beatSize >= 1);

                    // Signal declaration
                    if (beatSize == 1) {
                        if (p.bitWidth == 1) {
                            dpiFuncFileContent += fmt::format("uint8_t __{}_{}; // bits: {}, handleId: {}\n", hierPathName, p.name, p.bitWidth, p.handleId);
                            dpiFuncBody += fmt::format("\t__{}_{} = {};\n", hierPathName, p.name, p.name);
                        } else {
                            dpiFuncFileContent += fmt::format("uint32_t __{}_{}; // bits: {}, handleId: {}\n", hierPathName, p.name, p.bitWidth, p.handleId);
                            dpiFuncBody += fmt::format("\t__{}_{} = *{};\n", hierPathName, p.name, p.name);
                        }
                    } else {
                        dpiFuncFileContent += fmt::format("uint32_t __{}_{}[{}]; // bits: {}, handleId: {}\n", hierPathName, p.name, beatSize, p.bitWidth, p.handleId);
#ifdef NO_STD_COPY
                        // No std::copy
                        for (int k = 0; k < beatSize; k++) {
                            dpiFuncBody += fmt::format("\t{}[{}] = {}[{}];\n", signalName, k, p.name, k);
                        }
#else
                        // With std::copy
                        dpiFuncBody += fmt::format("\tstd::copy({0}, {0} + {1}, {2});\n", p.name, beatSize, signalName);
#endif // NO_STD_COPY
                    }

                    if (!distributeDPI) {
                        if (p.bitWidth == 1) {
                            dpiTickFuncParam += fmt::format("const uint8_t {}_{}, ", hierPathName, p.name);
                        } else {
                            dpiTickFuncParam += fmt::format("const uint32_t *{}_{}, ", hierPathName, p.name);
                        }

                        if (beatSize == 1) {
                            if (p.bitWidth == 1) {
                                dpiTickFuncBody += fmt::format("\t{} = {}_{};\n", signalName, hierPathName, p.name);
                            } else {
                                dpiTickFuncBody += fmt::format("\t{} = *{}_{};\n", signalName, hierPathName, p.name);
                            }
                        } else {
#ifdef NO_STD_COPY
                            // No std::copy
                            for (int k = 0; k < beatSize; k++) {
                                dpiTickFuncBody += fmt::format("\t{}[{}] = {}_{}[{}];\n", signalName, k, hierPathName, p.name, k);
                            }
#else
                            // With std::copy
                            dpiTickFuncBody += fmt::format("\tstd::copy({0}_{1}, {0}_{1} + {2}, {3});\n", hierPathName, p.name, beatSize, signalName);
#endif // NO_STD_COPY
                        }

                        auto pp            = p;
                        pp.hierPathName    = hierPathName;
                        pp.hierPathNameDot = hierPath;
                        portVecAll.emplace_back(pp);
                    }
                }

                for (auto &p : portVec) {
                    auto beatSize   = coverWith32(p.bitWidth);
                    auto signalName = fmt::format("__{}_{}", hierPathName, p.name);

                    if (beatSize == 1) {
                        dpiFuncFileContent += fmt::format(R"(
extern "C" uint32_t {}_{}_GET() {{
    return (uint32_t){};
}}
                            )",
                                                          dpiFuncNamePrefix, p.name, signalName);

                        dpiFuncFileContent += fmt::format(R"(
extern "C" uint64_t {}_{}_GET64() {{
    return (uint64_t){};
}}
                            )",
                                                          dpiFuncNamePrefix, p.name, signalName);

                        dpiFuncFileContent += fmt::format(R"(
extern "C" void {}_{}_GET_HEX_STR(char *hexStr) {{
    uint32_t value = {};
    for(int i = {}; i >= 0; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}
    hexStr[{}] = '\0';
}}
                            )",
                                                          dpiFuncNamePrefix, p.name, signalName, coverWith4(p.bitWidth) - 1, coverWith4(p.bitWidth));

                    } else { // beatSize > 1
                        dpiFuncFileContent += fmt::format(R"(
extern "C" uint32_t {}_{}_GET() {{
    return (uint32_t){}[0];
}}
                            )",
                                                          dpiFuncNamePrefix, p.name, signalName);

                        dpiFuncFileContent += fmt::format(R"(
extern "C" uint64_t {}_{}_GET64() {{
    return (uint64_t)((uint64_t)({}[1]) << 32 | (uint64_t){}[0]);
}}
                            )",
                                                          dpiFuncNamePrefix, p.name, signalName, signalName);

                        {
#ifdef NO_STD_COPY
                            // No std::copy
                            std::string tmp = "";
                            for (int k = 0; k < beatSize; k++) {
                                tmp = tmp + fmt::format("\tvalues[{}] = {}[{}];\n", k, signalName, k);
                            }
                            tmp.pop_back();
#else
                            // With std::copy
                            std::string tmp = fmt::format("\tstd::copy({0}, {0} + {1}, values);\n", signalName, beatSize);
#endif
                            dpiFuncFileContent += fmt::format(R"(
extern "C" void {}_{}_GET_VEC(uint32_t *values) {{
{}
}}
                                )",
                                                              dpiFuncNamePrefix, p.name, tmp);
                        }

                        if (beatSize == 2) {
                            dpiFuncFileContent += fmt::format(R"(
extern "C" void {}_{}_GET_HEX_STR(char *hexStr) {{
    uint32_t value;
    value = {}[0];
    for(int i = 8 + {} - 1; i >= {}; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}
    
    value = {}[1];
    for(int i = {} - 1; i >= 0; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}

    hexStr[{}] = '\0';
}}
)",

                                                              dpiFuncNamePrefix, p.name, signalName, coverWith4(p.bitWidth) - 8, coverWith4(p.bitWidth) - 8, signalName, coverWith4(p.bitWidth) - 8, coverWith4(p.bitWidth));
                        } else { // beatSize > 2
                            std::string tmp = "";
                            int beatIdx     = 0;
                            for (int k = beatSize - 1; k >= 0; k--) {
                                tmp = tmp + fmt::format(R"(
    value = {}[{}];
    for(int i = {}; i >= {}; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}
)",
                                                        signalName, beatIdx, (k + 1) * 8 - 1, k * 8);
                                beatIdx++;
                            }
                            tmp.pop_back();

                            dpiFuncFileContent += fmt::format(R"(
extern "C" void {}_{}_GET_HEX_STR(char *hexStr) {{
    uint32_t value;
{}
    hexStr[{}] = '\0';
}}
                                )",
                                                              dpiFuncNamePrefix, p.name, tmp, coverWith4(p.bitWidth));
                        }
                    }
                }
                dpiFuncBody += "}\n\n";
                dpiFuncFileContent += "\n";
            }
            sv_genStatement += "\nendgenerate\n";

            dpiFuncFileContent += dpiFuncBody;
            dpiFuncFileContent += "\n";

            if (distributeDPI) {
                MemberSyntax *lastMember;
                for (auto m : syntax.members) {
                    lastMember = m;
                }
                ASSERT(lastMember != nullptr, "TODO: syntax.members is nullptr");

                insertAtBack(syntax.members, parse(sv_genStatement));
            }
        } else {
            auto instSym    = model.syntaxToInstanceSymbol(syntax);
            auto foundClock = false;

            // If no signal pattern is set, check all ports
            if (info.signalPatternVec.size() == 0) {
                for (auto p : instSym->body.getPortList()) {
                    auto &pp      = p->as<PortSymbol>();
                    auto portName = std::string(pp.name);

                    auto bitWidth  = pp.getType().getBitWidth();
                    auto direction = toString(pp.direction);

                    if (portName == clock && bitWidth == 1 && direction == "In") {
                        foundClock = true;
                    }

                    // TODO: Check port type
                    if (checkValidSignal(portName)) {
                        portVec.emplace_back(PortInfo{.name = portName, .direction = std::string(direction), .bitWidth = bitWidth, .handleId = globalHandleIdx, .typeStr = "vpiNet", .hierPathName = "", .hierPathNameDot = ""}); // TODO: typeStr
                        if (!quiet) {
                            fmt::println("[DPIExporterRewriter] [{}VALID{}] [PORT] moudleName:<{}> portName:<{}> direction:<{}> bitWidth:<{}> handleId:<{}>", ANSI_COLOR_GREEN, ANSI_COLOR_RESET, moduleName, portName, direction, bitWidth, globalHandleIdx);
                            fflush(stdout);
                        }
                        globalHandleIdx++;
                    } else {
                        if (!quiet) {
                            fmt::println("[DPIExporterRewriter] [{}IGNORED{}] [PORT] moudleName:<{}> portName:<{}> direction:<{}> bitWidth:<{}>", ANSI_COLOR_RED, ANSI_COLOR_RESET, moduleName, portName, direction, bitWidth);
                            fflush(stdout);
                        }
                    }
                }
            } else {
                bool hasAnyNet = false;
                bool hasAnyVar = false;

                auto netIter = instSym->body.membersOfType<NetSymbol>();
                for (const auto &net : netIter) {
                    auto netName  = std::string(net.name);
                    auto bitWidth = net.getType().getBitWidth();

                    // TODO: Check net type
                    if (checkValidSignal(netName)) {
                        portVec.emplace_back(PortInfo{.name = netName, .direction = std::string("Unknown"), .bitWidth = bitWidth, .handleId = globalHandleIdx, .typeStr = "vpiNet", .hierPathName = "", .hierPathNameDot = ""});
                        if (!quiet) {
                            fmt::println("[DPIExporterRewriter] [{}VALID{}] [NET] moudleName:<{}> netName:<{}> bitWidth:<{}> handleId:<{}>", ANSI_COLOR_GREEN, ANSI_COLOR_RESET, moduleName, netName, bitWidth, globalHandleIdx);
                            fflush(stdout);
                        }
                        globalHandleIdx++;
                    } else {
                        if (!quiet) {
                            fmt::println("[DPIExporterRewriter] [{}IGNORED{}] [NET] moudleName:<{}> netName:<{}> bitWidth:<{}>", ANSI_COLOR_RED, ANSI_COLOR_RESET, moduleName, netName, bitWidth);
                            fflush(stdout);
                        }
                    }

                    hasAnyNet = true;
                }

                auto varIter = instSym->body.membersOfType<VariableSymbol>();
                for (const auto &var : varIter) {
                    auto varName  = std::string(var.name);
                    auto bitWidth = var.getType().getBitWidth();

                    // TODO: Check var type
                    if (checkValidSignal(varName)) {
                        portVec.emplace_back(PortInfo{.name = varName, .direction = std::string("Unknown"), .bitWidth = bitWidth, .handleId = globalHandleIdx, .typeStr = "vpiReg", .hierPathName = "", .hierPathNameDot = ""});
                        if (!quiet) {
                            fmt::println("[DPIExporterRewriter] [{}VALID{}] [VAR] moudleName:<{}> varName:<{}> bitWidth:<{}> handleId:<{}>", ANSI_COLOR_GREEN, ANSI_COLOR_RESET, moduleName, varName, bitWidth, globalHandleIdx);
                            fflush(stdout);
                        }
                        globalHandleIdx++;
                    } else {
                        if (!quiet) {
                            fmt::println("[DPIExporterRewriter] [{}IGNORED{}] [VAR] moudleName:<{}> varName:<{}> bitWidth:<{}>", ANSI_COLOR_RED, ANSI_COLOR_RESET, moduleName, varName, bitWidth);
                            fflush(stdout);
                        }
                    }

                    hasAnyVar = true;
                }

                ASSERT(hasAnyNet || hasAnyVar, "No net or var found in module", moduleName, info);
            }

            // Try find clock from instance body
            if (!foundClock) {
                auto clkSym = instSym->body.find(clock);
                if (clkSym != nullptr) {
                    auto bitWidth = 0;
                    if (clkSym->kind == SymbolKind::Variable) {
                        auto varSym = &clkSym->as<VariableSymbol>();
                        bitWidth    = varSym->getType().getBitWidth();
                    } else if (clkSym->kind == SymbolKind::Net) {
                        auto netSym = &clkSym->as<NetSymbol>();
                        bitWidth    = netSym->getType().getBitWidth();
                    } else {
                        PANIC("Unsupported clock type", toString(clkSym->kind));
                    }
                    ASSERT(bitWidth == 1, "Unsupported clock bitwidth", bitWidth);
                    foundClock = true;
                }
            }

            ASSERT(foundClock, "Clock signal not found!", moduleName, clock);

            if (!info.isTopModule && distributeDPI) {
                if (syntax.header->parameters == nullptr) {
                    // If the module has no parameters, add one
                    SmallVector<TokenOrSyntax> declsVec;
                    declsVec.push_back(TokenOrSyntax(&parse("parameter instId = 5555")));

                    std::span<TokenOrSyntax> decls = declsVec.copy(this->alloc);
                    syntax.header->parameters      = &this->factory.parameterPortList(makeId("#"), makeId("("), decls, makeId(")"));
                } else {
                    PANIC("TODO: has Parameters");
                }
            }
        }
    }

    if (!writeGenStatment) {
        visitDefault(syntax);
    }
}

void DPIExporterRewriter::handle(HierarchyInstantiationSyntax &inst) {
    std::string _moduleName = std::string(inst.type.rawText());

    if (_moduleName == moduleName) {
        std::string _instName = std::string(inst.instances[0]->decl->name.rawText());

        HierPathGetter visitor(_moduleName, _instName);
        compilation.getRoot().visit(visitor);

        int idx = 0;
        for (const auto &hierPath : visitor.hierPaths) {
            bool ignore = false;

            // Check if the hierPath is already in hierPathVec
            for (const auto &hierPath_1 : hierPathVec) {
                if (hierPath == hierPath_1) {
                    ignore = true;
                    break;
                }
            }

            if (ignore) {
                continue;
            }

            hierPathVec.emplace_back(hierPath);
            fmt::println("[DPIExporterRewriter] [{}INSTANCE{}] instName:<{}> moudleName:<{}>, instName:<{}>, hierPath[{}]:<{}>", ANSI_COLOR_YELLOW, ANSI_COLOR_RESET, _instName, inst.type.rawText(), _instName, idx, hierPath);
            idx++;
        }

        if (distributeDPI) {
            // Each module has only one unique instance ID
            SmallVector<TokenOrSyntax> paramAssignVec;
            paramAssignVec.push_back(TokenOrSyntax(&parse(fmt::format(".instId({})", instSize))));
            inst.parameters = &this->factory.parameterValueAssignment(makeId("#"), makeId("("), paramAssignVec.copy(this->alloc), makeId(")"));
        }

        instSize++;
    }
}
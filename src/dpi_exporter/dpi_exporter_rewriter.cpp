#include "dpi_exporter_rewriter.h"

using json = nlohmann::json;
using namespace slang::parsing;

uint64_t globalHandleIdx = 0; // Each signal has its own handle value(integer) and is unique

void DPIExporterRewriter_1::handle(ModuleDeclarationSyntax &syntax) {
    if (syntax.header->name.rawText() == topModuleName) {
        MemberSyntax *firstMember = nullptr;
        for (auto m : syntax.members) {
            firstMember = m;
            break;
        }
        ASSERT(firstMember != nullptr, "TODO:");

        std::string dpiTickFuncDeclParam = "";
        std::string dpiTickFuncParam     = "";
        std::vector<std::string> dpiTickDeclParamVec;
        std::vector<std::string> dpiTickFuncParamVec;
        for (auto &p : portVec) {
            if (p.bitWidth == 1) {
                dpiTickDeclParamVec.push_back(fmt::format("\t{} bit {}_{}", p.writable ? "output" : "input", p.hierPathName, p.name));
            } else {
                dpiTickDeclParamVec.push_back(fmt::format("\t{} bit [{}:0] {}_{}", p.writable ? "output" : "input", p.bitWidth - 1, p.hierPathName, p.name));
            }

            dpiTickFuncParamVec.push_back(fmt::format("{}.{}", p.hierPathNameDot, p.name));
        }

        dpiTickFuncDeclParam = fmt::to_string(fmt::join(dpiTickDeclParamVec, ",\n"));
        dpiTickFuncParam     = fmt::to_string(fmt::join(dpiTickFuncParamVec, ", "));

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

        json j;
        j["dpiTickFuncDeclParam"] = dpiTickFuncDeclParam;
        j["dpiTickFuncParam"]     = dpiTickFuncParam;
        j["sampleEdge"]           = sampleEdge;
        j["topModuleName"]        = topModuleName;
        j["clock"]                = clock;

        // TODO: if syntax.members is NULL?
        // Insert the following dpic tick function into top module
        insertAtBack(syntax.members, parse(inja::render(R"(
import "DPI-C" function void dpi_exporter_tick(
{{dpiTickFuncDeclParam}}    
);

always @({{sampleEdge}} {{topModuleName}}.{{clock}}) begin
    dpi_exporter_tick({{dpiTickFuncParam}});
end
)",
                                                        j)));
        findTopModule = true;
    }
}

void DPIExporterRewriter::handle(ModuleDeclarationSyntax &syntax) {
    if (syntax.header->name.rawText() == moduleName) {
        fmt::println("[DPIExporterRewriter] found module: {}, writeGenStatment: {}, instSize: {}", moduleName, writeGenStatment, instSize);

        if (writeGenStatment) {
            std::string sv_dpiTickDeclParam  = "";
            std::string sv_dpiTickFuncParam  = "";
            std::string dpiTickFuncDeclParam = "";

            ASSERT(portVec.size() != 0, "Port vector is empty!", moduleName);

            std::vector<std::string> sv_dpiTickDeclParamVec;
            std::vector<std::string> sv_dpiTickFuncParamVec;
            std::vector<std::string> dpiTickDeclParamVec;
            for (int i = 0; i < portVec.size(); i++) {
                auto &p = portVec[i];
                if (p.bitWidth == 1) {
                    sv_dpiTickDeclParamVec.push_back(fmt::format("\t\t{} bit {}", p.writable ? "output" : "input", p.name));
                } else {
                    sv_dpiTickDeclParamVec.push_back(fmt::format("\t\t{} bit [{}:0] {}", p.writable ? "output" : "input", p.bitWidth - 1, p.name));
                }

                sv_dpiTickFuncParamVec.push_back(fmt::format("{}", p.name));

                if (p.bitWidth == 1) {
                    if (p.writable) {
                        dpiTickDeclParamVec.push_back(fmt::format("uint8_t* {}", p.name));
                    } else {
                        dpiTickDeclParamVec.push_back(fmt::format("const uint8_t {}", p.name));
                    }
                } else {
                    if (p.writable) {
                        dpiTickDeclParamVec.push_back(fmt::format("uint32_t *{}", p.name));
                    } else {
                        dpiTickDeclParamVec.push_back(fmt::format("const uint32_t *{}", p.name));
                    }
                }
            }

            sv_dpiTickDeclParam  = fmt::to_string(fmt::join(sv_dpiTickDeclParamVec, ",\n"));
            sv_dpiTickFuncParam  = fmt::to_string(fmt::join(sv_dpiTickFuncParamVec, ", "));
            dpiTickFuncDeclParam = fmt::to_string(fmt::join(dpiTickDeclParamVec, ", "));

            ASSERT(hierPathNameVec.size() == 0);
            ASSERT(hierPathNameDotVec.size() == 0);
            for (int i = 0; i < hierPathVec.size(); i++) {
                std::string hierPathName = hierPathVec[i];
                std::replace(hierPathName.begin(), hierPathName.end(), '.', '_');
                hierPathNameVec.emplace_back(hierPathName);
                hierPathNameDotVec.emplace_back(hierPathVec[i]);
            }

            bool isTopModule = instSize == 0;
            auto _instSize   = instSize;
            if (instSize == 0) {
                _instSize = 1;
            }

            std::vector<std::string> dpiTickFuncVec;
            std::vector<std::string> dpiSignalBlockVec;
            std::string sv_genStatement = "\ngenerate // DPI Exporter\n";
            for (int instId = 0; instId < _instSize; instId++) {
                std::string hierPath          = "";
                std::string hierPathName      = "";
                std::string dpiFuncNamePrefix = "";
                std::string dpiTickFuncName   = "";

                if (!isTopModule) {
                    hierPath     = hierPathVec[instId];
                    hierPathName = hierPathNameVec[instId];
                } else {
                    hierPath     = moduleName;
                    hierPathName = moduleName;
                }

                dpiFuncNamePrefix = fmt::format("VERILUA_DPI_EXPORTER_{}", hierPathName);
                dpiTickFuncName   = fmt::format("{}_TICK", dpiFuncNamePrefix);

                std::string sv_dpiBlock = "";
                if (!isTopModule) {
                    sv_dpiBlock += fmt::format("if(instId == {}) begin\n", instId);
                }

                {
                    // Tick dpic function used when distributeDPI == TRUE
                    json j;
                    j["hierPath"]            = hierPath;
                    j["dpiTickFuncName"]     = dpiTickFuncName;
                    j["sv_dpiTickDeclParam"] = sv_dpiTickDeclParam;
                    j["sv_dpiTickFuncParam"] = sv_dpiTickFuncParam;
                    j["sampleEdge"]          = sampleEdge;
                    j["clock"]               = clock;
                    sv_dpiBlock += inja::render(R"(
    // hierPath: {{hierPath}}
    import "DPI-C" function void {{dpiTickFuncName}}(
{{sv_dpiTickDeclParam}}
    );

    always @({{sampleEdge}} {{clock}}) begin
        {{dpiTickFuncName}}({{sv_dpiTickFuncParam}});
    end
)",
                                                j);
                }

                if (!isTopModule) {
                    sv_dpiBlock += "end\n";
                }

                sv_genStatement += sv_dpiBlock;

                // ----------------------------------------------------------------------
                // Generate DPI file content(C++)
                // ----------------------------------------------------------------------
                std::vector<std::string> dpiTickDDFuncBodyVec;
                std::vector<std::string> dpiSignalDeclVec;
                std::vector<std::string> dpiSignalAccessFunctionsVec;
                for (auto &p : portVec) {
                    auto beatSize   = coverWith32(p.bitWidth);
                    auto signalName = fmt::format("__{}_{}", hierPathName, p.name);
                    ASSERT(beatSize >= 1);

                    // generate signal declarations
                    if (beatSize == 1) {
                        if (p.bitWidth == 1) {
                            dpiSignalDeclVec.push_back(fmt::format("uint8_t __{}_{}; // bits: {}, handleId: {}", hierPathName, p.name, p.bitWidth, p.handleId));
                            if (p.writable) {
                                dpiTickDDFuncBodyVec.push_back(fmt::format("\t*{} = __{}_{};", p.name, hierPathName, p.name));
                            } else {
                                dpiTickDDFuncBodyVec.push_back(fmt::format("\t__{}_{} = {};", hierPathName, p.name, p.name));
                            }
                        } else {
                            // dpiFuncFileContent += fmt::format("uint32_t __{}_{}; // bits: {}, handleId: {}\n", hierPathName, p.name, p.bitWidth, p.handleId);
                            dpiSignalDeclVec.push_back(fmt::format("uint32_t __{}_{}; // bits: {}, handleId: {}", hierPathName, p.name, p.bitWidth, p.handleId));
                            if (p.writable) {
                                dpiTickDDFuncBodyVec.push_back(fmt::format("\t*{} = __{}_{};", p.name, hierPathName, p.name));

                            } else {
                                dpiTickDDFuncBodyVec.push_back(fmt::format("\t__{}_{} = *{};", hierPathName, p.name, p.name));
                            }
                        }
                    } else {
                        dpiSignalDeclVec.push_back(fmt::format("uint32_t __{}_{}[{}]; // bits: {}, handleId: {}", hierPathName, p.name, beatSize, p.bitWidth, p.handleId));
#ifdef NO_STD_COPY
                        // No std::copy
                        if (p.writable) {
                            for (int k = 0; k < beatSize; k++) {
                                dpiTickDDFuncBodyVec.push_back(fmt::format("\t{}[{}] = {}[{}];", p.name, k, signalName, k));
                            }
                        } else {
                            for (int k = 0; k < beatSize; k++) {
                                dpiTickDDFuncBodyVec.push_back(fmt::format("\t{}[{}] = {}[{}];", signalName, k, p.name, k));
                            }
                        }
#else
                        // With std::copy
                        if (p.writable) {
                            dpiTickDDFuncBodyVec.push_back(fmt::format("\tstd::copy({2}, {2} + {1}, {0});", p.name, beatSize, signalName));
                        } else {
                            dpiTickDDFuncBodyVec.push_back(fmt::format("\tstd::copy({0}, {0} + {1}, {2});", p.name, beatSize, signalName));
                        }
#endif // NO_STD_COPY
                    }

                    if (!distributeDPI) {
                        if (p.bitWidth == 1) {
                            // dpiTickFuncParamVec is uesd outside the rewriter class
                            if (p.writable) {
                                dpiTickFuncParamVec.push_back(fmt::format("uint8_t* {}_{}", hierPathName, p.name));
                            } else {
                                dpiTickFuncParamVec.push_back(fmt::format("const uint8_t {}_{}", hierPathName, p.name));
                            }
                        } else {
                            if (p.writable) {
                                dpiTickFuncParamVec.push_back(fmt::format("uint32_t *{}_{}", hierPathName, p.name));
                            } else {
                                dpiTickFuncParamVec.push_back(fmt::format("const uint32_t *{}_{}", hierPathName, p.name));
                            }
                        }

                        if (beatSize == 1) {
                            if (p.bitWidth == 1) {
                                if (p.writable) {
                                    dpiTickFuncBodyVec.push_back(fmt::format("\t*{}_{} = {};", hierPathName, p.name, signalName));
                                } else {
                                    dpiTickFuncBodyVec.push_back(fmt::format("\t{} = {}_{};", signalName, hierPathName, p.name));
                                }
                            } else {
                                if (p.writable) {
                                    dpiTickFuncBodyVec.push_back(fmt::format("\t*{}_{} = {};", hierPathName, p.name, signalName));
                                } else {
                                    dpiTickFuncBodyVec.push_back(fmt::format("\t{} = *{}_{};", signalName, hierPathName, p.name));
                                }
                            }
                        } else {
#ifdef NO_STD_COPY
                            // No std::copy
                            if (p.writable) {
                                for (int k = 0; k < beatSize; k++) {
                                    dpiTickFuncBodyVec.push_back(fmt::format("\t{}_{}[{}] = {}[{}];", hierPathName, p.name, k, signalName, k));
                                }
                            } else {
                                for (int k = 0; k < beatSize; k++) {
                                    dpiTickFuncBodyVec.push_back(fmt::format("\t{}[{}] = {}_{}[{}];", signalName, k, hierPathName, p.name, k));
                                }
                            }

#else
                            // With std::copy
                            if (p.writable) {
                                dpiTickFuncBodyVec.push_back(fmt::format("\tstd::copy({3}, {3} + {2}, {0}_{1});", hierPathName, p.name, beatSize, signalName));
                            } else {
                                dpiTickFuncBodyVec.push_back(fmt::format("\tstd::copy({0}_{1}, {0}_{1} + {2}, {3});", hierPathName, p.name, beatSize, signalName));
                            }
#endif // NO_STD_COPY
                        }
                    }

                    auto pp            = p;
                    pp.hierPathName    = hierPathName;
                    pp.hierPathNameDot = hierPath;
                    portVecAll.emplace_back(pp);
                }

                // Generate DPI accesstor functions
                for (auto &p : portVec) {
                    auto beatSize   = coverWith32(p.bitWidth);
                    auto signalName = fmt::format("__{}_{}", hierPathName, p.name);

                    // Generate reader functions
                    if (beatSize == 1) {
                        dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" uint32_t {}_{}_GET() {{
    return (uint32_t){};
}})",
                                                                          dpiFuncNamePrefix, p.name, signalName));

                        dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" uint64_t {}_{}_GET64() {{
    return (uint64_t){};
}})",
                                                                          dpiFuncNamePrefix, p.name, signalName));

                        dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {}_{}_GET_HEX_STR(char *hexStr) {{
    uint32_t value = {};
    for(int i = {}; i >= 0; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}
    hexStr[{}] = '\0';
}})",
                                                                          dpiFuncNamePrefix, p.name, signalName, coverWith4(p.bitWidth) - 1, coverWith4(p.bitWidth)));

                    } else { // beatSize > 1
                        dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" uint32_t {}_{}_GET() {{
    return (uint32_t){}[0];
}})",
                                                                          dpiFuncNamePrefix, p.name, signalName));

                        dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" uint64_t {}_{}_GET64() {{
    return (uint64_t)((uint64_t)({}[1]) << 32 | (uint64_t){}[0]);
}})",
                                                                          dpiFuncNamePrefix, p.name, signalName, signalName));

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
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {}_{}_GET_VEC(uint32_t *values) {{
{}
}})",
                                                                              dpiFuncNamePrefix, p.name, tmp));
                        }

                        if (beatSize == 2) {
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
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
}})",

                                                                              dpiFuncNamePrefix, p.name, signalName, coverWith4(p.bitWidth) - 8, coverWith4(p.bitWidth) - 8, signalName, coverWith4(p.bitWidth) - 8, coverWith4(p.bitWidth)));
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

                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {}_{}_GET_HEX_STR(char *hexStr) {{
    uint32_t value;
{}
    hexStr[{}] = '\0';
}})",
                                                                              dpiFuncNamePrefix, p.name, tmp, coverWith4(p.bitWidth)));
                        }
                    }

                    // Generate writer functions
                    if (p.writable) {
                        if (beatSize == 1) {
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {}_{}_SET(uint32_t value) {{
    {} = value;
}})",
                                                                              dpiFuncNamePrefix, p.name, signalName));
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {}_{}_SET64(uint64_t value) {{
    {} = (uint32_t)value;
}})",
                                                                              dpiFuncNamePrefix, p.name, signalName));
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {}_{}_SET_HEX_STR(char *hexStr) {{
    uint32_t value = 0;
    for (int i = 0; hexStr[i] != '\0' && i < 7; ++i) {{
        char c = hexStr[i];
        value <<= 4;
        if (c >= '0' && c <= '9') {{
            value |= (c - '0');
        }} else if (c >= 'a' && c <= 'f') {{
            value |= (c - 'a' + 10);
        }} else if (c >= 'A' && c <= 'F') {{
            value |= (c - 'A' + 10);
        }}
    }}
    {} = value;
}})",
                                                                              dpiFuncNamePrefix, p.name, signalName));

                        } else { // beatSize > 1
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {0}_{1}_SET(uint32_t value) {{
    {2}[0] = value;
    for (int i = 1; i < {3}; i++) {{
        {2}[i] = 0;
    }}
}})",
                                                                              dpiFuncNamePrefix, p.name, signalName, beatSize));
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {0}_{1}_SET64(uint64_t value) {{
    {2}[0] = value & 0xFFFFFFFF;
    {2}[1] = (uint32_t)(value >> 32);
    for (int i = 2; i < {3}; i++) {{
        {2}[i] = 0;
    }}
}})",
                                                                              dpiFuncNamePrefix, p.name, signalName, beatSize));
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {0}_{1}_SET_VEC(uint32_t *values) {{
    std::copy(values, values + {3}, {2});
}})",
                                                                              dpiFuncNamePrefix, p.name, signalName, beatSize));
                            dpiSignalAccessFunctionsVec.push_back(fmt::format(R"(
extern "C" void {0}_{1}_SET_HEX_STR(char *hexStr) {{
    for (int j = 0; j < {3}; j++) {{
        uint32_t value = 0;
        for (int i = j * 8; hexStr[i] != '\0' && i < 8 + j * 8; ++i) {{
            char c = hexStr[i];
            value <<= 4;
            if (c >= '0' && c <= '9') {{
                value |= (c - '0');
            }} else if (c >= 'a' && c <= 'f') {{
                value |= (c - 'a' + 10);
            }} else if (c >= 'A' && c <= 'F') {{
                value |= (c - 'A' + 10);
            }}
        }}
        {2}[{3} - 1 - j] = value;
    }}
}})",
                                                                              dpiFuncNamePrefix, p.name, signalName, beatSize));
                        }
                    }
                }

                json j;
                j["dpiTickFuncName"]      = dpiTickFuncName;
                j["dpiTickFuncDeclParam"] = dpiTickFuncDeclParam;
                j["dpiTickDDFuncBody"]    = fmt::to_string(fmt::join(dpiTickDDFuncBodyVec, "\n"));

                std::string dpiTickFunc = inja::render(R"(
extern "C" void {{dpiTickFuncName}}({{dpiTickFuncDeclParam}}) {
{{dpiTickDDFuncBody}}
}
                )",
                                                       j);
                dpiTickFuncVec.push_back(dpiTickFunc);

                j["hierPath"]                      = hierPath;
                j["dpiSignalDecl"]                 = fmt::to_string(fmt::join(dpiSignalDeclVec, "\n"));
                j["dpiSignalAccessFunctions"]      = fmt::to_string(fmt::join(dpiSignalAccessFunctionsVec, "\n"));
                std::string dpiSignalDeclAndAccess = inja::render(R"(
// hierPath: {{hierPath}}
{{dpiSignalDecl}}
{{dpiSignalAccessFunctions}}
                )",
                                                                  j);
                dpiSignalBlockVec.push_back(dpiSignalDeclAndAccess);
            }
            sv_genStatement += "\nendgenerate\n";

            // Insert `VERILUA_DPI_EXPORTER_xxx_GET_xxx` and `VERILUA_DPI_EXPORTER_xxx_SET_xxx` functions
            dpiFuncFileContent += fmt::to_string(fmt::join(dpiSignalBlockVec, "\n"));
            if (distributeDPI) {
                // Insert `VERILUA_DPI_EXPORTER_xxx_TICK` functions when distributeDPI == TRUE
                dpiFuncFileContent += fmt::to_string(fmt::join(dpiTickFuncVec, "\n"));
            }
            dpiFuncFileContent += "\n";

            if (distributeDPI) {
                MemberSyntax *lastMember;
                for (auto m : syntax.members) {
                    lastMember = m;
                }
                ASSERT(lastMember != nullptr, "TODO: syntax.members is nullptr");

                insertAtBack(syntax.members, parse(sv_genStatement));
            }
        } else { // writeGenStatment == false
            auto instSym    = model.syntaxToInstanceSymbol(syntax);
            auto foundClock = false;

            // If no signal pattern is set, check all ports
            if (info.signalPatternVec.empty() && info.writableSignalPatternVec.empty()) {
                for (auto p : instSym->body.getPortList()) {
                    auto &pp      = p->as<PortSymbol>();
                    auto portName = std::string(pp.name);

                    auto bitWidth  = pp.getType().getBitWidth();
                    auto direction = toString(pp.direction);

                    if (portName == clock && bitWidth == 1 && direction == "In") {
                        foundClock = true;
                    }

                    // TODO: Check port type
                    auto portInfo = PortInfo{.name = portName, .direction = std::string(direction), .bitWidth = bitWidth, .handleId = globalHandleIdx, .writable = false, .typeStr = "vpiNet", .hierPathName = "", .hierPathNameDot = ""};
                    if (appendPortVec("PORT", portInfo)) {
                        globalHandleIdx++;
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
                    auto portInfo = PortInfo{.name = netName, .direction = std::string("Unknown"), .bitWidth = bitWidth, .handleId = globalHandleIdx, .writable = false, .typeStr = "vpiNet", .hierPathName = "", .hierPathNameDot = ""};
                    if (appendPortVec("NET", portInfo)) {
                        globalHandleIdx++;
                    }

                    hasAnyNet = true;
                }

                auto varIter = instSym->body.membersOfType<VariableSymbol>();
                for (const auto &var : varIter) {
                    auto varName  = std::string(var.name);
                    auto bitWidth = var.getType().getBitWidth();

                    // TODO: Check var type
                    auto portInfo = PortInfo{.name = varName, .direction = std::string("Unknown"), .bitWidth = bitWidth, .handleId = globalHandleIdx, .writable = false, .typeStr = "vpiReg", .hierPathName = "", .hierPathNameDot = ""};
                    if (appendPortVec("VAR", portInfo)) {
                        globalHandleIdx++;
                    }

                    hasAnyVar = true;
                }

                ASSERT(hasAnyNet || hasAnyVar, "No `net` or `var` found in module", moduleName, info);
            }

            if (info.writableSignalPatternVec.size() > 0) {
                // Only variable symbol are supported to be writable
                bool hasAnyVar = false;
                auto varIter   = instSym->body.membersOfType<VariableSymbol>();
                for (const auto &var : varIter) {
                    auto varName  = std::string(var.name);
                    auto bitWidth = var.getType().getBitWidth();

                    // TODO: Check var type
                    bool duplicateSiangl = false;
                    // Check if the mathed signal is duplicate in the portVec
                    for (auto &port : portVec) {
                        if (port.name == varName && checkValidSignal(varName, info.writableSignalPatternVec)) {
                            ASSERT(port.typeStr == "vpiReg", "Writable signal should be vpiReg type!", port.name);
                            ASSERT(port.bitWidth == bitWidth, "Writable signal should have the same bit width!", port);

                            port.writable   = true;
                            duplicateSiangl = true;
                            hasAnyVar       = true;

                            if (!quiet) {
                                fmt::println("[DPIExporterRewriter] [{}UPDATE{}] [WR_VAR] moudleName:<{}> signalName:<{}> bitWidth:<{}> handleId:<{}>", ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET, moduleName, port.name, port.bitWidth, port.handleId);
                                fflush(stdout);
                            }

                            break;
                        }
                    }

                    if (!duplicateSiangl) {
                        // Add writable variable signal that is not already in portVec
                        auto portInfo = PortInfo{.name = varName, .direction = std::string("Unknown"), .bitWidth = bitWidth, .handleId = globalHandleIdx, .writable = true, .typeStr = "vpiReg", .hierPathName = "", .hierPathNameDot = ""};
                        if (appendPortVec("WR_VAR", portInfo)) {
                            globalHandleIdx++;
                        }
                    }

                    hasAnyVar = true;
                }

                ASSERT(hasAnyVar, "No `var` found in module", moduleName, info);
            }

            if (distributeDPI) {
                // Try find clock from instance body
                // Every instance should have a clock signal specified by the configuration file
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
            }

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

            // If the hierPath is already in hierPathVec, ignore it
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
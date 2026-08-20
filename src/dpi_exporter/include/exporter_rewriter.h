#pragma once

#include "dpi_exporter.h"

using json = nlohmann::json;

// Used when distributeDPI is FALSE
struct ExporterRewriter : public slang::syntax::SyntaxRewriter<ExporterRewriter> {
    std::string insertModuleName;
    std::string sampleEdge;
    std::string topModuleName;
    std::string clock;
    std::vector<SignalGroup> signalGroupVec;
    slang::ast::Compilation *compilation;
    bool findModule = false;

    // clang-format off
    ExporterRewriter(
        slang::ast::Compilation *compilation,
        std::string insertModuleName,
        std::string sampleEdge,
        std::string topModuleName,
        std::string clock, std::vector<SignalGroup> signalGroupVec
    ) : 
        compilation(compilation), 
        insertModuleName(insertModuleName),
        sampleEdge(sampleEdge),
        topModuleName(topModuleName),
        clock(clock),
        signalGroupVec(signalGroupVec)
    {

    };
    // clang-format on

    void handle(const ModuleDeclarationSyntax &syntax) {
        if (this->insertModuleName == syntax.header->name.rawText()) {
            auto pldmGfifoDpi           = Config::getInstance().pldmGfifoDpi;
            std::string pldmGfifoDpiStr = "";

            fmt::println("[dpi_exporter] ExporterRewriter insertModuleName: {}", syntax.header->name.rawText());

            // Deal with normal signal groups
            std::vector<std::string> dpiTickFuncDeclParamVec;
            std::vector<std::string> dpiTickFuncDeclParam1Vec;
            std::vector<std::string> dpiTickFuncParamVec;
            int sgIdx = 0;
            for (auto &sg : signalGroupVec) {
                std::vector<std::string> declParamVec;
                std::vector<std::string> paramVec;

                for (auto &s : sg.signalInfoVec) {
                    if (s.isMetaOnly) {
                        continue; // meta_only signals are not tick-sampled
                    }
                    if (s.bitWidth == 1) {
                        declParamVec.push_back(fmt::format("\t{} bit {}", s.isWritable ? "output" : "input", s.hierPathName));
                    } else {
                        declParamVec.push_back(fmt::format("\t{} bit [{}:0] {}", s.isWritable ? "output" : "input", s.bitWidth - 1, s.hierPathName));
                    }

                    paramVec.push_back(fmt::format("\t\t\t{}", s.hierPath));
                }

                dpiTickFuncDeclParamVec.emplace_back(joinStrVec(declParamVec, ",\n"));
                if (sgIdx == 0) {
                    dpiTickFuncDeclParam1Vec.emplace_back(joinStrVec(declParamVec, ", \\\n"));
                } else {
                    dpiTickFuncDeclParam1Vec.emplace_back(joinStrVec(declParamVec, ", "));
                }
                // Used by `VL_DPI_EXP_CALL_TICK` macro body (backslash-continued single logical line).
                dpiTickFuncParamVec.emplace_back(joinStrVec(paramVec, ", \\\n"));

                sgIdx++;
            }

            // ---------------------------------------------------------------------------
            // Why dpiTickFuncParamDirectVec exists (Verilator + large export lists)
            //
            // Historical default always-block was:
            //   always @(...) begin
            //   `VL_DPI_EXP_CALL_TICK   (legacy: `CALL_DPI_EXPORTER_TICK)
            //   end
            // and VL_DPI_EXP_CALL_TICK expands to dpi_exporter_tick(arg0, arg1, ...).
            //
            // When many hierarchical signals are exported, that macro expansion becomes
            // one logical preprocessor line with tens of thousands of tokens. Verilator
            // then fails with:
            //   %Error: Too many preprocessor tokens on a line (>40000);
            //           perhaps recursive `define
            //
            // Fix: keep DECL/CALL macros for PLDM / VL_DPI_EXP_MANUAL_TICK users
            // (legacy: MANUALLY_CALL_DPI_EXPORTER_TICK), but emit the *default*
            // always-block as a real multi-line function call (comma + newline, not
            // macro-expanded). See always-block template below.
            // ---------------------------------------------------------------------------
            std::vector<std::string> dpiTickFuncParamDirectVec;
            for (auto &sg : signalGroupVec) {
                std::vector<std::string> paramVec;
                for (auto &s : sg.signalInfoVec) {
                    if (s.isMetaOnly) {
                        continue; // meta_only signals are not tick-sampled
                    }
                    paramVec.push_back(fmt::format("\t\t\t{}", s.hierPath));
                }
                dpiTickFuncParamDirectVec.emplace_back(joinStrVec(paramVec, ",\n"));
            }

            // Deal with sensitive signal groups
            std::string sDpiTickFuncDecl   = "";
            std::string sDpiTickFuncDecl_1 = "";
            std::string sCallDpiTickFunc   = "";
            // Multi-line form for the default always-block (NOT macro-expanded).
            // Sensitive ticks used to live only inside `VL_DPI_EXP_CALL_TICK`, but the
            // Verilator-safe always path no longer expands that macro — so without this
            // direct form, sensitive groups never update after the large-arg-list fix.
            std::string sCallDpiTickFuncDirect = "";
            for (size_t i = 1; i < dpiTickFuncDeclParamVec.size(); i++) {
                std::string sSignals                        = "";
                std::string sSignalsCond                    = "";
                std::string sSignalsCondExtra               = "";
                std::string sSignalsLastRegAssign           = "";
                std::string sSignalsLastRegAssignDirect     = "";
                std::vector<std::string> sSignalsLastRegVec = {};
                for (auto &s : signalGroupVec[i].sensitiveSignalInfoVec) {
                    sSignals += fmt::format("\t{}\n", s.hierPathName);

                    //
                    // e.g.
                    //      SensitiveSignals => valid, valid1, valid2
                    //      sSignalsCond => (valid ^ valid__LAST) || (valid1 ^ valid1__LAST) || (valid2 ^ valid2__LAST) || valid || valid1 || valid2
                    //
                    // TODO: for sensitive signals with bitWidth > 1
                    sSignalsCond += fmt::format("({} ^ {}) ||", s.hierPath, s.hierPathName + "__LAST");
                    sSignalsCondExtra += fmt::format("{} ||", s.hierPath);
                    sSignalsLastRegAssign += fmt::format("{}__LAST <= {}; \\\n\t", s.hierPathName, s.hierPath);
                    sSignalsLastRegAssignDirect += fmt::format("        {}__LAST <= {};\n", s.hierPathName, s.hierPath);
                    sSignalsLastRegVec.emplace_back(fmt::format("bit {}__LAST;", s.hierPathName));
                }
                sSignals.pop_back(); // Remove the last '\n'

                // Remove the last '||'
                sSignalsCondExtra.pop_back();
                sSignalsCondExtra.pop_back();
                sSignalsCond += sSignalsCondExtra;

                auto &name               = signalGroupVec[i].name;
                auto sSignalGroupContent = fmt::format(R"({0}
import "DPI-C" function void dpi_exporter_tick_{1}(
{2}
);)",
                                                       joinStrVec(sSignalsLastRegVec, "\n"), name, dpiTickFuncDeclParamVec[i]);
                sDpiTickFuncDecl += fmt::format(R"(
`ifndef VL_DPI_EXP_MANUAL_TICK
/*
Sensitive group name: {0}
Sensitive trigger signals:
{1}
*/
{2}
`endif // VL_DPI_EXP_MANUAL_TICK
)",
                                                name, sSignals, sSignalGroupContent);

                // Replace '\n' with ' \\n'
                size_t pos = 0;
                while ((pos = sSignalGroupContent.find("\n", pos)) != std::string::npos) {
                    sSignalGroupContent.replace(pos, 1, " \\\n\t");
                    pos += 3;
                }

                if (sSignalsLastRegAssign != "") {
                    // Remove the last '\\\n\t'
                    sSignalsLastRegAssign.pop_back();
                    sSignalsLastRegAssign.pop_back();
                    sSignalsLastRegAssign.pop_back();
                }

                sDpiTickFuncDecl_1 += sSignalGroupContent + " \\\n\t";

                // clang-format off
                sCallDpiTickFunc += inja::render(R"(if({{sSignalsCond}}) begin \
        dpi_exporter_tick_{{name}}( \
{{dpiTickFuncParam}}); \
    end \
    {{sSignalsLastRegAssign}} \
    )",
                json{
                        {"sSignalsCond", sSignalsCond },
                        { "name", name },
                        { "dpiTickFuncParam", dpiTickFuncParamVec[i] },
                        { "sSignalsLastRegAssign", sSignalsLastRegAssign }
                    }
                );

                // Multi-line always-body form (same logic, no macro backslashes).
                sCallDpiTickFuncDirect += inja::render(R"(
    if ({{sSignalsCond}}) begin
        dpi_exporter_tick_{{name}}(
{{dpiTickFuncParamDirect}});
    end
{{sSignalsLastRegAssignDirect}})",
                json{
                        {"sSignalsCond", sSignalsCond },
                        { "name", name },
                        { "dpiTickFuncParamDirect", dpiTickFuncParamDirectVec[i] },
                        { "sSignalsLastRegAssignDirect", sSignalsLastRegAssignDirect }
                    }
                );
                // clang-format on

                if (pldmGfifoDpi) {
                    pldmGfifoDpiStr += fmt::format("initial $ixc_ctrl(\"gfifo\", \"dpi_exporter_tick_{}\");\n", name);
                }
            }

            if (sDpiTickFuncDecl_1 != "") {
                // Remove trailing '\\\n\t'
                sDpiTickFuncDecl_1.pop_back();
                sDpiTickFuncDecl_1.pop_back();
                sDpiTickFuncDecl_1.pop_back();
            }

            // clang-format off
            std::string dpiTickFuncDecl = inja::render(R"({% if dpiTickFuncDeclParam != "" %}
import "DPI-C" function void dpi_exporter_tick(
{{dpiTickFuncDeclParam}}
);
{% else %}
import "DPI-C" function void dpi_exporter_tick();
{% endif %})",
            json{
                    { "dpiTickFuncDeclParam", dpiTickFuncDeclParamVec[0] /* The first signal group is `DEFAULT` */ }
                }
            );

            std::string dpiTickDeclMacro = inja::render(R"(`define VL_DPI_EXP_DECL_TICK \
    import "DPI-C" function void dpi_exporter_tick( \
{{dpiTickFuncDeclParam_1}}); {% if sDpiTickFuncDecl_1 != "" %}\{% endif %}
    {{sDpiTickFuncDecl_1}}
// Legacy aliases (deprecated): same expansion as VL_DPI_EXP_DECL_TICK / VL_DPI_EXP_CALL_TICK.
`define DECL_DPI_EXPORTER_TICK `VL_DPI_EXP_DECL_TICK
            )", json {
                { "dpiTickFuncDeclParam_1", dpiTickFuncDeclParam1Vec[0] },
                { "sDpiTickFuncDecl_1", sDpiTickFuncDecl_1 }
            });

            std::string callDpiTickMacro = inja::render(R"(`define VL_DPI_EXP_CALL_TICK \
    {% if sCallDpiTickFunc != "" %}{{sCallDpiTickFunc}}{% endif %}begin \
    {% if dpiTickFuncParam != "" %}    dpi_exporter_tick( \
{{dpiTickFuncParam}}); \
    end
    {% else %}    dpi_exporter_tick(); \
    end
    {% endif %}
`define CALL_DPI_EXPORTER_TICK `VL_DPI_EXP_CALL_TICK
            )", json {
                { "sCallDpiTickFunc", sCallDpiTickFunc },
                { "dpiTickFuncParam", dpiTickFuncParamVec[0] }
            });
            // clang-format on

            if (pldmGfifoDpi) {
                pldmGfifoDpiStr += "initial $ixc_ctrl(\"gfifo\", \"dpi_exporter_tick\");\n";
                pldmGfifoDpiStr = std::string("`ifdef PALLADIUM\n") + pldmGfifoDpiStr + "`endif // PALLADIUM\n";
            }

            json j;
            j["dpiTickFuncDecl"]  = dpiTickFuncDecl;
            j["sDpiTickFuncDecl"] = sDpiTickFuncDecl;
            j["dpiTickDeclMacro"] = dpiTickDeclMacro;
            j["callDpiTickMacro"] = callDpiTickMacro;
            j["sampleEdge"]       = sampleEdge;
            j["topModuleName"]    = topModuleName;
            j["clock"]            = clock;
            j["pldmGfifoDpiStr"]  = pldmGfifoDpiStr;
            // DEFAULT signal-group args for the non-macro always-block (see comment above).
            j["dpiTickFuncParamDirect"] = dpiTickFuncParamDirectVec.empty() ? "" : dpiTickFuncParamDirectVec[0];
            j["sCallDpiTickFuncDirect"] = sCallDpiTickFuncDirect;

            // Generated SV layout:
            //   1) import "DPI-C" dpi_exporter_tick(...);   // multi-line decl (OK for Verilator)
            //   2) lift legacy MANUALLY_CALL_DPI_EXPORTER_TICK -> VL_DPI_EXP_MANUAL_TICK
            //   3) `define VL_DPI_EXP_DECL_TICK / VL_DPI_EXP_CALL_TICK (+ legacy aliases)
            //   4) default always: sensitive group ticks (if any) + dpi_exporter_tick(DEFAULT)
            //      DO NOT use `VL_DPI_EXP_CALL_TICK here when the arg list is huge —
            //      Verilator expands that macro into one line and hits token-limit errors.
            auto code = inja::render(R"(
{{dpiTickFuncDecl}}

// Prefer VL_DPI_EXP_MANUAL_TICK. Legacy: MANUALLY_CALL_DPI_EXPORTER_TICK.
`ifdef MANUALLY_CALL_DPI_EXPORTER_TICK
`ifndef VL_DPI_EXP_MANUAL_TICK
`define VL_DPI_EXP_MANUAL_TICK
`endif
`endif

{{sDpiTickFuncDecl}}

{{dpiTickDeclMacro}}

{{callDpiTickMacro}}

// Manual override: define VL_DPI_EXP_MANUAL_TICK (or legacy MANUALLY_CALL_DPI_EXPORTER_TICK)
// and use VL_DPI_EXP_DECL_TICK / VL_DPI_EXP_CALL_TICK yourself (legacy: DECL_/CALL_DPI_EXPORTER_TICK).
// Default path below intentionally does NOT invoke `VL_DPI_EXP_CALL_TICK (see ExporterRewriter
// comment: Verilator "Too many preprocessor tokens on a line" with large export lists).
`ifndef VL_DPI_EXP_MANUAL_TICK
always @({{sampleEdge}} {{topModuleName}}.{{clock}}) begin
{{sCallDpiTickFuncDirect}}
{% if dpiTickFuncParamDirect != "" %}
    // Multi-line DEFAULT call (not a macro expansion) — required for large hierarchical arg lists.
    dpi_exporter_tick(
{{dpiTickFuncParamDirect}});
{% else %}
    dpi_exporter_tick();
{% endif %}
end
`endif // VL_DPI_EXP_MANUAL_TICK

{{pldmGfifoDpiStr}}
)",
                                     j);

            // Make sure clock signal is exist in the inserted module
            auto def      = compilation->getDefinition(static_cast<const Scope &>(compilation->getRoot()), syntax);
            auto inst     = &InstanceSymbol::createDefault(*compilation, *def);
            bool hasClock = false;
            auto netIter  = inst->body.membersOfType<slang::ast::NetSymbol>();
            for (const auto &net : netIter) {
                if (net.name == clock) {
                    hasClock = true;
                    break;
                }
            }
            if (!hasClock) {
                auto varIter = inst->body.membersOfType<slang::ast::VariableSymbol>();
                for (const auto &var : varIter) {
                    if (var.name == clock) {
                        hasClock = true;
                        break;
                    }
                }
            }
            ASSERT(hasClock, "Clock signal not found in inserted module, please make sure the clock signal is exist in the module.", clock, topModuleName);

            // Insert the following dpic tick function into top module
            insertAtBack(syntax.members, parse(code));

            findModule = true;
        }
    }
};

// TODO: distributeDPI is TRUE
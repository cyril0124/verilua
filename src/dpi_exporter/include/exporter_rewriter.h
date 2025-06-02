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
    bool findModule = false;

    ExporterRewriter(std::string insertModuleName, std::string sampleEdge, std::string topModuleName, std::string clock, std::vector<SignalGroup> signalGroupVec) : insertModuleName(insertModuleName), sampleEdge(sampleEdge), topModuleName(topModuleName), clock(clock), signalGroupVec(signalGroupVec) {};

    void handle(const ModuleDeclarationSyntax &syntax) {
        if (this->insertModuleName == syntax.header->name.rawText()) {
            fmt::println("[dpi_exporter] ExporterRewriter insertModuleName: {}", syntax.header->name.rawText());

            std::vector<std::string> dpiTickFuncDeclParamVec;
            std::vector<std::string> dpiTickFuncDeclParam1Vec;
            std::vector<std::string> dpiTickFuncParamVec;
            for (auto &sg : signalGroupVec) {
                std::vector<std::string> declParamVec;
                std::vector<std::string> paramVec;

                for (auto &s : sg.signalInfoVec) {
                    if (s.bitWidth == 1) {
                        declParamVec.push_back(fmt::format("\t{} bit {}", s.isWritable ? "output" : "input", s.hierPathName));
                    } else {
                        declParamVec.push_back(fmt::format("\t{} bit [{}:0] {}", s.isWritable ? "output" : "input", s.bitWidth - 1, s.hierPathName));
                    }

                    paramVec.push_back(fmt::format("{}", s.hierPath));
                }

                dpiTickFuncDeclParamVec.emplace_back(fmt::to_string(fmt::join(declParamVec, ",\n")));
                dpiTickFuncDeclParam1Vec.emplace_back(fmt::to_string(fmt::join(declParamVec, ", ")));
                dpiTickFuncParamVec.emplace_back(fmt::to_string(fmt::join(paramVec, ", ")));
            }

            std::string sDpiTickFuncDecl   = "";
            std::string sDpiTickFuncDecl_1 = "";
            std::string sCallDpiTickFunc   = "";
            for (size_t i = 1; i < dpiTickFuncDeclParamVec.size(); i++) {
                std::string sSignals                        = "";
                std::string sSignalsCond                    = "";
                std::string sSignalsCondExtra               = "";
                std::string sSignalsLastRegAssign           = "";
                std::vector<std::string> sSignalsLastRegVec = {};
                for (auto &s : signalGroupVec[i].sensitiveSignalInfoVec) {
                    sSignals += fmt::format("\t{}\n", s.hierPathName);
                    sSignalsCond += fmt::format("({} ^ {}) ||", s.hierPath, s.hierPathName + "__LAST");
                    sSignalsCondExtra += fmt::format("{} ||", s.hierPath);
                    sSignalsLastRegAssign += fmt::format("{}__LAST <= {}; ", s.hierPathName, s.hierPath);
                    sSignalsLastRegVec.emplace_back(fmt::format("bit {}__LAST;", s.hierPathName));
                }
                sSignals.pop_back(); // Remove the last '\n'

                // Remove the last '||'
                sSignalsCondExtra.pop_back();
                sSignalsCondExtra.pop_back();
                sSignalsCond += sSignalsCondExtra;

                auto &name = signalGroupVec[i].name;
                sDpiTickFuncDecl += fmt::format(R"(
`ifndef MANUALLY_CALL_DPI_EXPORTER_TICK
/*
Sensitive group name: {1}
Sensitive trigger signals:
{0}
*/
{3}
import "DPI-C" function void dpi_exporter_tick_{1}(
{2}
);
`endif // MANUALLY_CALL_DPI_EXPORTER_TICK
)",
                                                sSignals, name, dpiTickFuncDeclParamVec[i], fmt::to_string(fmt::join(sSignalsLastRegVec, "\n")));
                sDpiTickFuncDecl_1 += fmt::format("{0} import \"DPI-C\" function void dpi_exporter_tick_{1}({2}); ", fmt::to_string(fmt::join(sSignalsLastRegVec, " ")), name, dpiTickFuncDeclParam1Vec[i]);
                sCallDpiTickFunc += fmt::format("if({0}) dpi_exporter_tick_{1}({2}); {3}", sSignalsCond, name, dpiTickFuncParamVec[i], sSignalsLastRegAssign);
            }

            json j;
            j["dpiTickFuncDeclParam"]   = dpiTickFuncDeclParamVec[0];
            j["dpiTickFuncDeclParam_1"] = dpiTickFuncDeclParam1Vec[0];
            j["dpiTickFuncParam"]       = dpiTickFuncParamVec[0];
            j["sDpiTickFuncDecl"]       = sDpiTickFuncDecl;
            j["sDpiTickFuncDecl_1"]     = sDpiTickFuncDecl_1;
            j["sCallDpiTickFunc"]       = sCallDpiTickFunc;
            j["sampleEdge"]             = sampleEdge;
            j["topModuleName"]          = topModuleName;
            j["clock"]                  = clock;

            auto code = inja::render(R"(
import "DPI-C" function void dpi_exporter_tick(
{{dpiTickFuncDeclParam}}    
);

{{sDpiTickFuncDecl}}

`define DECL_DPI_EXPORTER_TICK import "DPI-C" function void dpi_exporter_tick({{dpiTickFuncDeclParam_1}}); {{sDpiTickFuncDecl_1}}
`define CALL_DPI_EXPORTER_TICK {{sCallDpiTickFunc}} dpi_exporter_tick({{dpiTickFuncParam}});

// If this macro is defined, the DPI tick function will be called manually in other places. 
// Users can use with `DECL_DPI_EXPORTER_TICK` and `CALL_DPI_EXPORTER_TICK` to call the DPI tick function manually.
`ifndef MANUALLY_CALL_DPI_EXPORTER_TICK
always @({{sampleEdge}} {{topModuleName}}.{{clock}}) begin
`CALL_DPI_EXPORTER_TICK
end
`endif // MANUALLY_CALL_DPI_EXPORTER_TICK
)",
                                     j);

            // Insert the following dpic tick function into top module
            insertAtBack(syntax.members, parse(code));

            findModule = true;
        }
    }
};

// TODO: distributeDPI is TRUE
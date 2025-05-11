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

            std::string dpiTickFuncDeclParam   = "";
            std::string dpiTickFuncDeclParam_1 = "";
            std::string dpiTickFuncParam       = "";
            std::vector<std::string> dpiTickDeclParamVec;
            std::vector<std::string> dpiTickFuncParamVec;
            for (auto &sg : signalGroupVec) {
                for (auto &s : sg.signalInfoVec) {
                    if (s.bitWidth == 1) {
                        dpiTickDeclParamVec.push_back(fmt::format("\t{} bit {}", s.isWritable ? "output" : "input", s.hierPathName));
                    } else {
                        dpiTickDeclParamVec.push_back(fmt::format("\t{} bit [{}:0] {}", s.isWritable ? "output" : "input", s.bitWidth - 1, s.hierPathName));
                    }

                    dpiTickFuncParamVec.push_back(fmt::format("{}", s.hierPath));
                }
            }

            dpiTickFuncDeclParam   = fmt::to_string(fmt::join(dpiTickDeclParamVec, ",\n"));
            dpiTickFuncDeclParam_1 = fmt::to_string(fmt::join(dpiTickDeclParamVec, ", "));
            dpiTickFuncParam       = fmt::to_string(fmt::join(dpiTickFuncParamVec, ", "));

            json j;
            j["dpiTickFuncDeclParam"]   = dpiTickFuncDeclParam;
            j["dpiTickFuncDeclParam_1"] = dpiTickFuncDeclParam_1;
            j["dpiTickFuncParam"]       = dpiTickFuncParam;
            j["sampleEdge"]             = sampleEdge;
            j["topModuleName"]          = topModuleName;
            j["clock"]                  = clock;

            auto code = inja::render(R"(
import "DPI-C" function void dpi_exporter_tick(
{{dpiTickFuncDeclParam}}    
);

`define DECL_DPI_EXPORTER_TICK import "DPI-C" function void dpi_exporter_tick({{dpiTickFuncDeclParam_1}});
`define CALL_DPI_EXPORTER_TICK dpi_exporter_tick({{dpiTickFuncParam}});

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
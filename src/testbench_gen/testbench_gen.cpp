#include "SlangCommon.h"
#include "fmt/base.h"
#include "fmt/color.h"
#include "inja/inja.hpp"
#include "libassert/assert.hpp"
#include "slang/ast/ASTVisitor.h"
#include "slang/ast/SemanticFacts.h"
#include "slang/ast/Symbol.h"
#include "slang/ast/symbols/InstanceSymbols.h"
#include "slang/ast/symbols/PortSymbols.h"
#include "slang/ast/symbols/VariableSymbols.h"
#include "slang/driver/Driver.h"
#include "slang/parsing/TokenKind.h"
#include "slang/syntax/AllSyntax.h"
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <nlohmann/json.hpp>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

using json   = nlohmann::json;
namespace fs = std::filesystem;

using PortInfo = struct {
    std::string name;
    std::string dir;
    std::string pType; // port type
    std::string declStr;
    int arraySize;
    int id; // port id

    bool isArray() { return arraySize != 0; }
    bool isInput() { return dir == "In"; }
    bool isOutput() { return dir == "Out"; }
};

std::string replaceString(std::string str, const char *pattern, const char *replacement) {
    size_t pos = str.find(pattern);
    if (pos != std::string::npos) {
        return str.replace(pos, std::string(pattern).length(), replacement);
    }
    return str;
};

std::string replaceString(std::string str, std::string pattern, std::string replacement) { return replaceString(str, pattern.c_str(), replacement.c_str()); };

class TestbenchGenParser : public ASTVisitor<TestbenchGenParser, false, false> {
  public:
    bool verbose;
    int portIdAllocator = 0;
    std::string topName;
    TestbenchGenParser(std::string topName, bool verbose) : topName(topName) { this->verbose = verbose; }

    std::vector<PortInfo> portInfos;

    void handle(const InstanceBodySymbol &ast) {
        if (ast.name == topName) {
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
                        fmt::println("[TestbenchGenParser] [Net] portName: {} portWidth: {} pType: {} dir: {} arraySize: {} dType: {}", port.name, pType.getBitWidth(), pType.toString(), toString(port.direction), arraySize, dType);
                } else if (internalKind == SymbolKind::Variable) {
                    auto &var = port.internalSymbol->as<VariableSymbol>();

                    if (verbose)
                        fmt::println("[TestbenchGenParser] [Var] portName: {} portWidth: {} pType: {} dir: {} arraySize: {}", port.name, pType.getBitWidth(), pType.toString(), toString(port.direction), arraySize);
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
};

std::vector<std::string> parseFileList(const std::string &filePath) {
    std::vector<std::string> files;
    std::ifstream infile(filePath);
    std::string line;

    while (std::getline(infile, line)) {
        if (!line.empty()) {
            files.push_back(line);
        }
    }

    return files;
}

int main(int argc, const char *argv[]) {
    OS::setupConsole();
    slang::driver::Driver driver;

    std::vector<std::string> _files;
    std::optional<std::string> _tbtopName;
    std::optional<std::string> _dutName;
    std::optional<std::string> _outdir;
    std::optional<std::string> _clockSignalName;
    std::optional<std::string> _resetSignalName;
    std::optional<std::string> _customCodeFile;
    std::optional<std::string> _customCodeStr;
    std::optional<std::string> _customCodeOuterFile;
    std::optional<std::string> _customCodeStrOuter;
    std::optional<int> _period;
    std::optional<bool> _verbose;
    std::optional<bool> _checkOutput;
    std::optional<bool> _dryrun;
    std::optional<bool> _nodpi;

    driver.cmdLine.add("--tt,--tbtop", _tbtopName, "testbench top module name", "<top module name>");
    driver.cmdLine.add("--dn,--dut-name", _dutName, "testbench dut inst name", "<dut instance name>");
    driver.cmdLine.add("--od,--out-dir", _outdir, "output directory", "<directory>");
    driver.cmdLine.add("--cs,--clock-signal", _clockSignalName, "clock signal name", "<signal name>");
    driver.cmdLine.add("--rs,--reset-signal", _resetSignalName, "reset signal name", "<signal name>");
    driver.cmdLine.add("--cc,--custom-code", _customCodeFile, "input custom code <file>, will be inserted in the bottom of the testbench module", "<file>");
    driver.cmdLine.add("--ccs,--custom-code-str", _customCodeStr, "input custom code <string>, will be inserted in the bottom of the testbench module", "<string>");
    driver.cmdLine.add("--cco,--custom-code-outer", _customCodeOuterFile, "input custom code <file>, will be inserted in the top of the testbench module", "<file>");
    driver.cmdLine.add("--ccso,--custom-code-str-outer", _customCodeStrOuter, "input custom code <string>, will be inserted in the top of the testbench module", "<string>");
    driver.cmdLine.add("--fl,--filelist", _files, "input file or filelist", "<file/filelist>");
    driver.cmdLine.add("-p,--period", _period, "clock period", "<period value>");
    driver.cmdLine.add("--vb,--verbose", _verbose, "verbose output");
    driver.cmdLine.add("--co,--check-output", _checkOutput, "check output");
    driver.cmdLine.add("--dr,--dryrun", _dryrun, "do not generate testbench");

    // TODO: remove this
    driver.cmdLine.add("--nd,--nodpi", _nodpi, "disable dpi generation");

    std::optional<bool> showHelp;
    driver.cmdLine.add("-h,--help", showHelp, "Display available options");

    driver.addStandardArgs();
    ASSERT(driver.parseCommandLine(argc, argv));

    if (showHelp) {
        std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText("Testbench generator for verilua").c_str());
        return 0;
    }

    if (_dryrun.value_or(false)) {
        fmt::println(R"(
--------------- [testbench_gen] ---------------
      _                               
     | |                              
   __| |_ __ _   _    _ __ _   _ _ __  
  / _` | '__| | | |  | '__| | | | '_ \ 
 | (_| | |  | |_| |  | |  | |_| | | | |
  \__,_|_|   \__, |  |_|   \__,_|_| |_|
              __/ |                     
             |___/           
-----------------------------------------------
)");
       return 0; 
    }

    for (const auto &file : _files) {
        if (file.ends_with(".f")) {
            // Parse filelist
            std::vector<std::string> fileList = parseFileList(file);
            for (const auto &listedFile : fileList) {
                driver.sourceLoader.addFiles(fs::absolute(listedFile).string());
            }
        } else {
            driver.sourceLoader.addFiles(fs::absolute(file).string());
        }
    }

    ASSERT(driver.processOptions());

    std::string tbtopName           = _tbtopName.value_or("tb_top");
    std::string dutName             = _dutName.value_or("");
    std::string outdir              = _outdir.value_or(".");
    std::string clockSignalName     = _clockSignalName.value_or("");
    std::string resetSignalName     = _resetSignalName.value_or("");
    std::string customCodeFile      = _customCodeFile.value_or("");
    std::string customCodeStr       = _customCodeStr.value_or("");
    std::string customCodeOuterFile = _customCodeOuterFile.value_or("");
    std::string customCodeStrOuter  = _customCodeStrOuter.value_or("");
    int period                      = _period.value_or(10);
    bool verbose                    = _verbose.value_or(false);
    bool checkOutput                = _checkOutput.value_or(false);
    bool nodpi                      = _checkOutput.value_or(true);

    size_t fileCount = 0;
    std::ofstream slangOptFile(outdir + "/slang.opt");
    ASSERT(slangOptFile.is_open(), "Failed to open slang.opt file");
    for (auto buffer : driver.sourceLoader.loadSources()) {
        fileCount++;

        auto fullpath = driver.sourceManager.getFullPath(buffer.id).string();
        fmt::println("[testbench_gen] [{}] get file: {}", fileCount, fullpath);
        fflush(stdout);

        slangOptFile << fullpath << "\n"; // TODO: save other options
    }
    slangOptFile << outdir + "/" + tbtopName + ".sv" << "\n";
    slangOptFile << outdir + "/" + "others.sv" << "\n";
    slangOptFile << "--top " << tbtopName << "\n";
    slangOptFile.close();

    ASSERT(driver.parseAllSources());
    ASSERT(driver.reportParseDiags());

    auto compilation = driver.createCompilation();

    bool compileSuccess = driver.reportCompilation(*compilation, false);
    ASSERT(compileSuccess);

    std::string topName     = "";
    auto &rootSymbol        = compilation->getRoot();
    std::string rootTopName = "";
    ASSERT(rootSymbol.topInstances.size() >= 1, "Root symbol should have at least 1 top instance");

    if (rootSymbol.topInstances.size() == 1) {
        topName = std::string(rootSymbol.topInstances[0]->getDefinition().name);
    } else {
        PANIC("TODO:");
    }

    if (dutName == "") {
        dutName = std::string("u_") + topName;
    }

    fmt::println("[testbench_gen] topName: {} dutName: {}", topName, dutName);

    TestbenchGenParser parser(topName, verbose);
    compilation->getRoot().visit(parser);

    bool clockSignalHasMatch = false;
    bool resetSignalHasMatch = false;
    for (auto &port : parser.portInfos) {
        if (clockSignalName != "" && port.name == clockSignalName) {
            clockSignalHasMatch = true;
        }

        if (resetSignalName != "" && port.name == resetSignalName) {
            resetSignalHasMatch = true;
        }

        if (clockSignalName == "" && (port.name == "clock" || port.name == "clock_i" || port.name == "clk" || port.name == "clk_i")) {
            clockSignalHasMatch = true;
            clockSignalName     = port.name;
        }

        if (resetSignalName == "" && (port.name == "reset" || port.name == "reset_i" || port.name == "rst" || port.name == "rst_i")) {
            resetSignalHasMatch = true;
            resetSignalName     = port.name;
        }
    }

    ASSERT(clockSignalHasMatch, "Clock signal not match", clockSignalName);
    ASSERT(resetSignalHasMatch, "Reset signal not match", resetSignalName);

    { // Generate tbtop file
        auto tbtopFileContent = R"(
// -----------------------------------------
// test bench generated by VERILUA
// -----------------------------------------

// -----------------------------------------
// user custom code
//    use `--custom-code-outer/-cco <file>` to pass in the custom code file.
//       |_ e.g. `testbench_gen [...] --custom-code-outer path/to/file`
//    use `--custom-code-str-outer/-ccso <string>` to pass in the custom code string.
//       |_ e.g. `testbench_gen [...] --custom-code-str-outer "`define a 1"`
// -----------------------------------------

{{customCodeStrOuter}}
{{customCodeOuterFileContent}} 

module {{tbtopName}}(
`ifdef SIM_VERILATOR
    input wire clock,
    input wire reset,
    output wire [63:0] cycles_o
`endif // SIM_VERILATOR
);


// -----------------------------------------
// macro define check
// -----------------------------------------
`ifdef SIM_VERILATOR
  `ifdef SIM_VCS
    initial begin
      $error("Both SIM_VERILATOR and SIM_VCS are defined. Only one should be defined.");
      $finish;
    end
  `endif
`else
  `ifndef SIM_VCS
    `ifndef SIM_IVERILOG
        initial begin
          $error("One of [SIM_VERILATOR / SIM_VCS / SIM_IVERILOG] is not defined! One must be defined.");
          $finish;
        end
    `endif
  `endif
`endif


// -----------------------------------------
// deal with clock, reset, cycles
// -----------------------------------------   
`ifndef SIM_VERILATOR
reg {{clockSignalName}};
reg {{resetSignalName}};

initial begin
    {{clockSignalName}} = 0;
    {{resetSignalName}} = 1;
end

always #{{clockPeriod}} {{clockSignalName}} = ~{{clockSignalName}};
`endif // SIM_VERILATOR

{{clockAndResetAlias}}

reg [63:0] cycles; // A timestamp counter for simulation, start from 0 and never reset

initial cycles = 0;
always@(posedge {{clockSignalName}}) begin
    cycles <= cycles + 1; // Increment the timestamp counter every clock cycle
end 

`ifdef SIM_VERILATOR
assign cycles_o = cycles; // Tie the timestamp counter to the output port for verilator
`endif

// -----------------------------------------
// reg/wire declaration
// -----------------------------------------  
{{signalDecl}}


// -----------------------------------------
//  reg initialize
// -----------------------------------------
initial begin
    $display("[INFO] @%0t [%s:%d] hello from {{tbtopName}}", $time, `__FILE__, `__LINE__);
{{regInitialize}}
end


// -----------------------------------------
// verilua mode selection (only for vcs)
// -----------------------------------------

`ifdef SIM_VCS
// VeriluaMode
parameter NormalMode = 1;
parameter StepMode = 2;
parameter DominantMode = 3;

export "DPI-C" function vcs_get_mode;
function int vcs_get_mode;
    `ifdef STEP_MODE
        $display("[INFO] @%0t [%s:%d] vcs using StepMode", $time, `__FILE__, `__LINE__);
        return StepMode;
    `else
        `ifdef DOMINANT_MODE
            $display("[INFO] @%0t [%s:%d] TODO: DominantMode", $time, `__FILE__, `__LINE__); $fatal;
            return DominantMode;
        `else
            $display("[INFO] @%0t [%s:%d] vcs using NormalMode", $time, `__FILE__, `__LINE__);
            return NormalMode;
        `endif
    `endif
endfunction

`ifdef STEP_MODE
import "DPI-C" function void verilua_init();
import "DPI-C" function void verilua_main_step();
import "DPI-C" function void verilua_final();

initial begin
    verilua_init();
end

// always@(posedge {{clockSignalName}}) begin
//  #1 verilua_main_step();
// end

always@(negedge {{clockSignalName}}) begin
    verilua_main_step();
end

final begin
    verilua_final();
end
`endif // STEP_MODE

`endif // SIM_VCS


// -----------------------------------------
//  DUT module instantiate
// ----------------------------------------- 
{{topName}} {{dutName}} (
{{signalConnect}}
); // {{dutName}}


// -----------------------------------------
// tracing functions
// https://github.com/chipsalliance/chisel/blob/main/svsim/src/main/scala/Workspace.scala
// -----------------------------------------
`ifndef SIM_IVERILOG
    export "DPI-C" function simulation_initializeTrace;
    export "DPI-C" function simulation_enableTrace;
    export "DPI-C" function simulation_disableTrace;

    function void simulation_initializeTrace;
        input string traceFilePath;
    `ifdef SIM_VERILATOR
        $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => VCD", $time, `__FILE__, `__LINE__);
        $dumpfile({traceFilePath, ".vcd"});
        $dumpvars(0, {{tbtopName}});
    `endif

    `ifdef SIM_VCS
        $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => FSDB", $time, `__FILE__, `__LINE__);

        `ifdef FSDB_AUTO_SWITCH
        `ifndef FILE_SIZE
            `define FILE_SIZE 25
        `endif
        
        `ifndef NUM_OF_FILES
            `define NUM_OF_FILES 1000
        `endif

        $fsdbAutoSwitchDumpfile(`FILE_SIZE, {traceFilePath, ".fsdb"}, `NUM_OF_FILES);
        `else
        $fsdbDumpfile({traceFilePath, ".fsdb"});
        `endif

        //
        // $fsdbDumpvars([depth, instance][, "option"]);
        // options:
        //   +all: Record all signals, including memories, MDA (Memory Data Array), packed arrays, structures, etc.
        //   +mda: Record all memory and MDA signals. MDA (Memory Data Array) signals refer to those related to memory data arrays.
        //   +IO_Only: Record only input and output port signals.
        //   +Reg_Only: Record only signals of register type.
        //   +parameter: Record parameters.
        //   +fsdbfile+filename: Specify the fsdb file name.
        // 
        $fsdbDumpvars(0, {{tbtopName}}, "+all");
    `endif
    endfunction

    function void simulation_enableTrace;
    `ifdef SIM_VERILATOR
        $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
        $dumpon;
    `endif

    `ifdef SIM_VCS
        $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => FSDB", $time, `__FILE__, `__LINE__);
        $fsdbDumpon;
        // $fsdbDumpMDA(); // enable dump Multi-Dimension-Array
    `endif
    endfunction

    function void simulation_disableTrace;
    `ifdef SIM_VERILATOR
        $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
        $dumpoff;
    `endif

    `ifdef SIM_VCS
        $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => FSDB", $time, `__FILE__, `__LINE__);
        $fsdbDumpoff;
    `endif
    endfunction
`endif // SIM_IVERILOG

`ifdef SIM_IVERILOG
reg simulation_initializeTrace;
reg simulation_initializeTrace_latch;

reg simulation_enableTrace;
reg simulation_enableTrace_latch;

reg simulation_disableTrace;
reg simulation_disableTrace_latch;

initial begin
    simulation_initializeTrace = 0;
    simulation_initializeTrace_latch = 0;

    simulation_enableTrace = 0;
    simulation_enableTrace_latch = 0;

    simulation_disableTrace = 0;
    simulation_disableTrace_latch = 0;
end

always@(posedge {{clockSignalName}} or negedge {{clockSignalName}}) begin
    if(simulation_initializeTrace && !simulation_initializeTrace_latch) begin
        integer file;
        string trace_name = "dump.vcd";
        file = $fopen("iverilog_trace_name.txt", "r");
        $fscanf(file, "%s", trace_name);
        $fclose(file);

        $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => VCD", $time, `__FILE__, `__LINE__);
        $dumpfile(trace_name);
        $dumpvars(0, tb_top);

        simulation_initializeTrace_latch <= 1;
    end

    if(simulation_enableTrace && !simulation_enableTrace_latch) begin
        $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
        $dumpon;

        simulation_enableTrace_latch <= 1;
    end

    if(simulation_disableTrace && !simulation_disableTrace_latch) begin
        $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
        $dumpoff;

        simulation_disableTrace_latch <= 1;
    end
end
`endif // SIM_IVERILOG


// -----------------------------------------
// tracing command interface
// -----------------------------------------
`ifdef SIM_VCS
initial begin
    string dump_file = "dump";
    integer dump_start_cycle = 0;
            
    if ($test$plusargs("dump_enable=1")) begin
        // 1. set dump file name
        if ($value$plusargs("dump_file=%s", dump_file))
            $display("[INFO] @%0t [%s:%d] dump_file => %s ", $time, `__FILE__, `__LINE__, dump_file);
        else
            $display("[INFO] @%0t [%s:%d] [default] dump_file => %s ", $time, `__FILE__, `__LINE__, dump_file);

        // 2. set dump start cycle
        if ($value$plusargs("dump_start_cycle=%d", dump_start_cycle))
            $display("[INFO] @%0t [%s:%d] dump_start_cycle: %d ", $time, `__FILE__, `__LINE__, dump_start_cycle);

        // 3. set dump type
        if ($test$plusargs("dump_vcd")) begin
            $display("[INFO] @%0t [%s:%d] enable dump_vcd ", $time, `__FILE__, `__LINE__);

            repeat(dump_start_cycle) @(posedge {{clockSignalName}});
            $display("[INFO] @%0t [%s:%d] start dump_vcd at cycle => %d... ", $time, `__FILE__, `__LINE__, dump_start_cycle);

            $dumpfile({dump_file, ".vcd"});
            $dumpvars(0, {{tbtopName}});
        end else if ($test$plusargs("dump_fsdb")) begin
            $display("[INFO] @%0t [%s:%d] enable dump_fsdb ", $time, `__FILE__, `__LINE__);

            repeat(dump_start_cycle) @(posedge {{clockSignalName}});
            $display("[INFO] @%0t [%s:%d] start dump_fsdb at cycle => %d... ", $time, `__FILE__, `__LINE__, dump_start_cycle);
            $fsdbDumpfile({dump_file, ".fsdb"});
            $fsdbDumpvars(0, {{tbtopName}});
        end else begin
            $display("[ERROR] @%0t [%s:%d] neither dump_vcd or dump_fsdb are not pass in", $time, `__FILE__, `__LINE__);
            $fatal;
        end
    end
end
`endif // SIM_VCS


// -----------------------------------------
// other user code...
// -----------------------------------------
Others u_others(
  .clock({{clockSignalName}}),
  .reset({{resetSignalName}})
);


// -----------------------------------------
// user custom code 
//    use `--custom-code/-cc <file>` to pass in the custom code file.
//       |_ e.g. `testbench_gen [...] --custom-code path/to/file`
//    use `--custom-code-str/-ccs <string>` to pass in the custom code string.
//       |_ e.g. `testbench_gen [...] --custom-code-str "reg a; initial a = 1;"`
// -----------------------------------------

{{customCodeStr}}

{{customCodeFileContent}}


endmodule
)";

        std::string clockAndResetAlias         = "";
        std::string signalDecl                 = "";
        std::string regInitialize              = "";
        std::string signalConnect              = "";
        std::string customCodeFileContent      = "";
        std::string customCodeOuterFileContent = "";

        if (customCodeFile != "") {
            std::fstream file(customCodeFile);
            ASSERT(file.is_open(), "Cannot open custom code file", customCodeFile);

            std::stringstream ss;
            ss << file.rdbuf();
            customCodeFileContent = ss.str();
        }

        if (customCodeOuterFile != "") {
            std::fstream file(customCodeOuterFile);
            ASSERT(file.is_open(), "Cannot open custom code file(outer)", customCodeFile);

            std::stringstream ss;
            ss << file.rdbuf();
            customCodeOuterFileContent = ss.str();
        }

        auto lastId = parser.portInfos.back().id;
        for (auto &port : parser.portInfos) {
            if (port.id != lastId) {
                signalConnect = signalConnect + fmt::format("\t.{:<30} ({:<30}), // direction: {:<10} dataType: {}\n", port.name, port.name, port.dir, port.pType);
            } else {
                // is last element
                signalConnect = signalConnect + fmt::format("\t.{:<30} ({:<30})  // direction: {:<10} dataType: {}\n", port.name, port.name, port.dir, port.pType);
            }

            if (port.name == clockSignalName || port.name == resetSignalName) {
                continue;
            } else {
                if (port.isInput()) {
                    if (port.isArray()) {
                        signalDecl = signalDecl + fmt::format("{}; // Input\n", port.declStr);
                        for (int i = 0; i < port.arraySize; i++) {
                            if (i % 8 == 0 && i != 0)
                                regInitialize = regInitialize + "\n";
                            regInitialize = regInitialize + fmt::format("\t{}[{:<3}] = 0; ", port.name, i); // TODO:
                        }
                        regInitialize = regInitialize + "\n";
                    } else {
                        signalDecl    = signalDecl + fmt::format("{:<20} {:<30}; // Input\n", replaceString(port.pType, "logic", "reg"), port.name);
                        regInitialize = regInitialize + fmt::format("\t{:<30} = 0;\n", port.name);
                    }
                } else if (port.isOutput()) {
                    if (port.isArray()) {
                        signalDecl = signalDecl + fmt::format("{}; // Output\n", port.declStr);
                    } else {
                        if (port.pType.find("logic") != std::string::npos) {
                            signalDecl = signalDecl + fmt::format("{:<20} {:<30}; // Output\n", replaceString(port.pType, "logic", "wire"), port.name);
                        } else if (port.pType.find("reg") != std::string::npos) {
                            signalDecl = signalDecl + fmt::format("{:<20} {:<30}; // Output\n", replaceString(port.pType, "reg", "wire"), port.name);
                        } else {
                            ASSERT(false, "Port type is not supported", port.pType);
                        }
                    }
                } else {
                    ASSERT(false, "Port direction is not supported", port.dir);
                }
            }
        }
        ASSERT(signalConnect.length() > 2, "No signals to connect");
        signalConnect.erase(signalConnect.length() - 2);

        if (clockSignalName != "clock") {
            clockAndResetAlias = fmt::format(R"(`ifdef SIM_VERILATOR
wire {};
assign {} = clock;
`else // SIM_VERILATOR
wire clock;
assign clock = {};
`endif // SIM_VERILATOR
)",
                                             clockSignalName, clockSignalName, clockSignalName);
        }

        if (resetSignalName != "reset") {
            clockAndResetAlias = fmt::format(R"(`ifdef SIM_VERILATOR
wire {};
assign {} = reset;
`else // SIM_VERILATOR
wire reset;
assign reset = {};
`endif // SIM_VERILATOR
)",
                                             resetSignalName, resetSignalName, resetSignalName);
        }

        json tbtopData;
        tbtopData["tbtopName"]                  = tbtopName;
        tbtopData["topName"]                    = topName;
        tbtopData["dutName"]                    = dutName;
        tbtopData["clockPeriod"]                = period;
        tbtopData["clockSignalName"]            = clockSignalName;
        tbtopData["resetSignalName"]            = resetSignalName;
        tbtopData["clockAndResetAlias"]         = clockAndResetAlias;
        tbtopData["signalDecl"]                 = signalDecl;
        tbtopData["regInitialize"]              = regInitialize;
        tbtopData["signalConnect"]              = signalConnect;
        tbtopData["customCodeStr"]              = customCodeStr;
        tbtopData["customCodeFileContent"]      = customCodeFileContent;
        tbtopData["customCodeStrOuter"]         = customCodeStrOuter;
        tbtopData["customCodeOuterFileContent"] = customCodeOuterFileContent;

        if (!std::filesystem::is_directory(outdir)) {
            fmt::println("[testbench_gen] Creating directory: {}", outdir);
            std::filesystem::create_directory(outdir);
        }

        std::ofstream tbtopFile(outdir + "/" + tbtopName + ".sv");
        ASSERT(tbtopFile.is_open(), "Can't open file", outdir + "/" + tbtopName + ".sv");

        tbtopFile << inja::render(tbtopFileContent, tbtopData);
        tbtopFile.close();

        if (!std::filesystem::exists(outdir + "/" + "others.sv")) {
            fmt::println("[testbench_gen] Creating others.sv...");
            std::ofstream othersFile(outdir + "/" + "others.sv");
            ASSERT(othersFile.is_open(), "Cannot open others.sv");
            othersFile << R"(
module Others (
    input wire clock,
    input wire reset
);

// -----------------------------------------
// other user code...
// -----------------------------------------
// ...

endmodule
)";
            othersFile.close();
        }
    }

    if (checkOutput) {
        fmt::println("\n[testbench_gen] Checking output files...");

        std::string tbtopFile  = outdir + "/" + tbtopName + ".sv";
        std::string othersFile = outdir + "/" + "others.sv";

        driver.sourceLoader.addFiles(tbtopFile);
        driver.sourceLoader.addFiles(othersFile);
        driver.options.topModules.clear();
        driver.options.topModules.push_back(tbtopName);

        ASSERT(driver.processOptions());
        ASSERT(driver.parseAllSources());

        auto compilationForCheck = driver.createCompilation();
        ASSERT(driver.reportCompilation(*compilationForCheck, false));
    }
}
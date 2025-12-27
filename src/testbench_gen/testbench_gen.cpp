#include "testbench_gen.h"

using json   = nlohmann::json;
namespace fs = std::filesystem;

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
    std::optional<std::string> _luaMetaFile;
    std::optional<double> _period;
    std::optional<bool> _verbose;
    std::optional<bool> _checkOutput;
    std::optional<bool> _dryrun;
    std::optional<bool> _regen;
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
    driver.cmdLine.add("--lm,--lua-meta-file", _luaMetaFile, "output lua meta file(type annotation file)", "<file>");
    driver.cmdLine.add("--fl,--filelist", _files, "input file or filelist", "<file/filelist>");
    driver.cmdLine.add("-p,--period", _period, "clock period", "<period value>");
    driver.cmdLine.add("--vb,--verbose", _verbose, "verbose output");
    driver.cmdLine.add("--co,--check-output", _checkOutput, "check output");
    driver.cmdLine.add("--dr,--dryrun", _dryrun, "do not generate testbench");
    driver.cmdLine.add("-r,--regen", _regen, "force regeneration of testbench");

    // TODO: remove this
    driver.cmdLine.add("--nd,--nodpi", _nodpi, "disable dpi generation");

    std::optional<bool> showHelp;
    driver.cmdLine.add("-h,--help", showHelp, "Display available options");

    driver.addStandardArgs();
    ASSERT(driver.parseCommandLine(argc, argv));

    if (showHelp) {
        std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText(fmt::format("testbench_gen(verilua@{})", VERILUA_VERSION)).c_str());
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
    std::string luaMetaFile         = _luaMetaFile.value_or("");
    double period                   = _period.value_or(20);
    bool verbose                    = _verbose.value_or(false);
    bool checkOutput                = _checkOutput.value_or(false);
    bool regen                      = _regen.value_or(false);
    bool nodpi                      = _checkOutput.value_or(true);

    const std::string tbtopFilePath    = outdir + "/" + tbtopName + ".sv";
    const std::string othersFilePath   = outdir + "/" + "others.sv";
    const std::string metaInfoFilePath = outdir + "/tb_gen.meta.json";

    bool shouldRegen = !fs::exists(tbtopFilePath) || !fs::exists(othersFilePath) || regen;

    // Get command line into string
    std::string cmdLineStr = "";
    for (int i = 0; i < argc; i++) {
        cmdLineStr += argv[i];
        cmdLineStr += " ";
    }

    json metaInfoJson;
    std::set<std::string> filelistSet;
    std::ifstream metaInfoFile(metaInfoFilePath);
    if (metaInfoFile.is_open()) {
        metaInfoJson = json::parse(metaInfoFile);
        metaInfoFile.close();

        filelistSet = metaInfoJson["filelist"].get<std::set<std::string>>();
        if (metaInfoJson["cmdLine"] != cmdLineStr) {
            fmt::println("[testbench_gen] cmdLine changed, regenerating...");
            shouldRegen = true;
        }

        if (fs::exists(othersFilePath) && metaInfoJson["othersFileMTime"] != to_time_t(fs::last_write_time(othersFilePath))) {
            fmt::println("[testbench_gen] {} changed, regenerating...", othersFilePath);
            shouldRegen = true;
        }
    } else {
        fmt::println("[testbench_gen] {} not found, regenerating...", metaInfoFilePath);
        shouldRegen = true;
    }

    std::vector<std::string> fileVec;
    size_t fileCount = 0;
    for (auto buffer : driver.sourceLoader.loadSources()) {
        fileCount++;

        auto fullpath = driver.sourceManager.getFullPath(buffer.id).string();
        fmt::println("[testbench_gen] [{}] get file: {}", fileCount, fullpath);
        fflush(stdout);

        if (!shouldRegen) {
            if (!filelistSet.contains(fullpath)) {
                fmt::println("[testbench_gen] [{}] file not found in meta.filelist, regenerating...", fileCount);
                shouldRegen = true;
            }

            if (isFileNewer(fullpath, tbtopFilePath)) {
                fmt::println("[testbench_gen] [{}] file is newer, regenerating...", fileCount);
                shouldRegen = true;
            }
        }
        fileVec.push_back(fullpath);
    }

    if (shouldRegen) {
        metaInfoJson["filelist"] = fileVec;
        metaInfoJson["cmdLine"]  = cmdLineStr;
    } else {
        fmt::println("[testbench_gen] No need to regenerate");
        return 0;
    }

    ASSERT(driver.parseAllSources());
    ASSERT(driver.reportParseDiags());

    // Check compilation errors
    bool compileSuccess = driver.runFullCompilation(false);
    ASSERT(compileSuccess);

    auto compilation = driver.createCompilation();

    std::string topName = "";
    auto &rootSymbol    = compilation->getRoot();
    ASSERT(rootSymbol.topInstances.size() >= 1, "Root symbol should have at least 1 top instance");

    // Try get topName from rootSymbol, there should be only one top instance
    if (rootSymbol.topInstances.size() == 1) {
        topName = std::string(rootSymbol.topInstances[0]->getDefinition().name);
    } else {
        PANIC("TODO: Multiple top instances found!");
    }

    if (dutName == "") {
        dutName = std::string("u_") + topName;
    }

    fmt::println("[testbench_gen] topName: {} dutName: {}", topName, dutName);

    // Start iterate the whole design to get all available ports
    TestbenchGenParser parser(topName, verbose);
    auto &portInfos          = parser.portInfos;
    auto &portParamStmts     = parser.portParamStmts;
    auto &portParamInstStmts = parser.portParamInstStmts;
    compilation->getRoot().visit(parser);

    // Save portInfos, portParamStmts into meta file
    metaInfoJson["portInfos"]      = portInfos;
    metaInfoJson["portParamStmts"] = portParamStmts;

    // Check whether clock and reset signal has been matched
    bool clockSignalHasMatch = false;
    bool resetSignalHasMatch = false;
    bool userSpecifiedClock  = _clockSignalName.has_value() && !_clockSignalName.value().empty();
    bool userSpecifiedReset  = _resetSignalName.has_value() && !_resetSignalName.value().empty();

    // Clock signal name patterns (case-insensitive)
    // Patterns: clk, clock, clk_*, clock_*, *_clk, *_clock, i_clk, sys_clk, etc.
    auto isClockSignal = [](const std::string &name) -> bool {
        std::string lowerName = name;
        std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);

        // Exact matches
        if (lowerName == "clk" || lowerName == "clock")
            return true;

        // Prefix patterns: clk_*, clock_*, i_clk*, i_clock*
        if (lowerName.substr(0, 4) == "clk_" || lowerName.substr(0, 6) == "clock_")
            return true;
        if (lowerName.substr(0, 5) == "i_clk" || lowerName.substr(0, 7) == "i_clock")
            return true;

        // Suffix patterns: *_clk, *_clock
        if (lowerName.length() > 4 && lowerName.substr(lowerName.length() - 4) == "_clk")
            return true;
        if (lowerName.length() > 6 && lowerName.substr(lowerName.length() - 6) == "_clock")
            return true;

        // Common patterns
        if (lowerName == "sys_clk" || lowerName == "sys_clock")
            return true;
        if (lowerName == "clk_i" || lowerName == "clock_i")
            return true;

        return false;
    };

    // Reset signal name patterns (case-insensitive)
    // Patterns: rst, reset, rst_*, reset_*, *_rst, *_reset, rst_n, reset_n, etc.
    auto isResetSignal = [](const std::string &name) -> bool {
        std::string lowerName = name;
        std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);

        // Exact matches (including active-low variants)
        if (lowerName == "rst" || lowerName == "reset")
            return true;
        if (lowerName == "rst_n" || lowerName == "reset_n" || lowerName == "rstn" || lowerName == "resetn")
            return true;

        // Prefix patterns: rst_*, reset_*, i_rst*, i_reset*
        if (lowerName.substr(0, 4) == "rst_" || lowerName.substr(0, 6) == "reset_")
            return true;
        if (lowerName.substr(0, 5) == "i_rst" || lowerName.substr(0, 7) == "i_reset")
            return true;

        // Suffix patterns: *_rst, *_reset, *_rst_n, *_reset_n
        if (lowerName.length() > 4 && lowerName.substr(lowerName.length() - 4) == "_rst")
            return true;
        if (lowerName.length() > 6 && lowerName.substr(lowerName.length() - 6) == "_reset")
            return true;
        if (lowerName.length() > 6 && lowerName.substr(lowerName.length() - 6) == "_rst_n")
            return true;
        if (lowerName.length() > 8 && lowerName.substr(lowerName.length() - 8) == "_reset_n")
            return true;

        // Common patterns
        if (lowerName == "sys_rst" || lowerName == "sys_reset")
            return true;
        if (lowerName == "sys_rst_n" || lowerName == "sys_reset_n")
            return true;
        if (lowerName == "rst_i" || lowerName == "reset_i")
            return true;

        return false;
    };

    for (auto &port : portInfos) {
        // If user specified clock signal, check exact match
        if (userSpecifiedClock && port.name == clockSignalName) {
            clockSignalHasMatch = true;
        }

        // If user specified reset signal, check exact match
        if (userSpecifiedReset && port.name == resetSignalName) {
            resetSignalHasMatch = true;
        }

        // If user didn't specify clock signal, use smart detection
        if (!userSpecifiedClock && !clockSignalHasMatch && isClockSignal(port.name)) {
            clockSignalHasMatch = true;
            clockSignalName     = port.name;
        }

        // If user didn't specify reset signal, use smart detection
        if (!userSpecifiedReset && !resetSignalHasMatch && isResetSignal(port.name)) {
            resetSignalHasMatch = true;
            resetSignalName     = port.name;
        }
    }

    if (!clockSignalHasMatch) {
        if (parser.hasProceduralBlock) {
            PANIC("Clock signal not match", clockSignalName);
        } else {
            clockSignalName = "clock";
            fmt::println("[testbench_gen] Warning: Clock signal not match! hasProceduralBlock = false");
        }
    } else {
        fmt::println("[testbench_gen] clock signal: {}", clockSignalName);
    }

    if (!resetSignalHasMatch) {
        fmt::println("[testbench_gen] Warning: Reset signal not match!");
    } else {
        fmt::println("[testbench_gen] reset signal: {}", resetSignalName);
    }

    { // Generate tbtop file
        auto tbtopFileContent = R"(
//VCS coverage exclude_file
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

module {{tbtopName}} {{tbtopPortParamDecl}}(
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
  `ifdef SIM_XCELIUM
    initial begin
      $error("Both SIM_VERILATOR and SIM_XCELIUM are defined. Only one should be defined.");
      $finish;
    end
  `endif
`else
  `ifndef SIM_VCS
    `ifndef SIM_IVERILOG
      `ifndef SIM_XCELIUM
        initial begin
          $error("One of [SIM_VERILATOR / SIM_VCS / SIM_IVERILOG / SIM_XCELIUM] is not defined! One must be defined.");
          $finish;
        end
      `endif
    `endif
  `endif
`endif


// -----------------------------------------
// deal with clock, reset, cycles
// -----------------------------------------
`ifndef SIM_VERILATOR
reg {{clockSignalName}};
{% if resetSignalName == "" %}// no reset signal found!{% else %}reg {{resetSignalName}};{% endif %}

initial begin
    {{clockSignalName}} = 0;
    {% if resetSignalName == "" %}// no reset signal found!{% else %}{{resetSignalName}} = 1;{% endif %}
end

`ifndef NO_INTERNAL_CLOCK
always #{{clockPeriod}} {{clockSignalName}} = ~{{clockSignalName}};
`endif // NO_INTERNAL_CLOCK
`endif // SIM_VERILATOR

{% if clockSignalName != "clock" and clockSignalName != "" %}
`ifdef SIM_VERILATOR
wire {{clockSignalName}};
assign {{clockSignalName}} = clock;
`else // SIM_VERILATOR
wire clock;
assign clock = {{clockSignalName}};
`endif // SIM_VERILATOR
{% endif %}

{% if resetSignalName != "reset" and resetSignalName != "" %}
`ifdef SIM_VERILATOR
wire {{resetSignalName}};
assign {{resetSignalName}} = reset;
`else // SIM_VERILATOR
wire reset;
assign reset = {{resetSignalName}};
`endif // SIM_VERILATOR
{% endif %}


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
    // $display("[INFO] @%0t [%s:%d] hello from {{tbtopName}}", $time, `__FILE__, `__LINE__);
{{regInitialize}}
end

// -----------------------------------------
//  DUT module instantiate
// -----------------------------------------
{{topName}} {{dutPortParamDecl}} {{dutName}} (
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
            $dumpfile(traceFilePath);
            $dumpvars(0, {{tbtopName}});
        `endif // SIM_VERILATOR

        `ifdef SIM_VCS
            `ifdef VCS_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => VCD", $time, `__FILE__, `__LINE__);
                $dumpfile(traceFilePath);
                $dumpvars(0, {{tbtopName}});
            `else // VCS_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => FSDB", $time, `__FILE__, `__LINE__);

                `ifdef FSDB_AUTO_SWITCH
                    `ifndef FILE_SIZE
                        `define FILE_SIZE 25
                    `endif

                    `ifndef NUM_OF_FILES
                        `define NUM_OF_FILES 1000
                    `endif

                    $fsdbAutoSwitchDumpfile(`FILE_SIZE, {traceFilePath, ".fsdb"}, `NUM_OF_FILES);
                `else // FSDB_AUTO_SWITCH
                    $fsdbDumpfile({traceFilePath, ".fsdb"});
                `endif // FSDB_AUTO_SWITCH

                `ifdef FSDB_DUMP_SVA
                    //
                    // Dump System Verilog Assertions
                    // Notice: To enable this feature, you also need to add `+fsdb+sva_success`
                    //         to your `./simv` command line args at runtime or in your `vcs`
                    //         command line args at build time.
                    //
                    $fsdbDumpSVA(0, {{tbtopName}});
                `endif // FSDB_DUMP_SVA

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
            `endif // VCS_DUMP_VCD
        `endif // SIM_VCS

        `ifdef SIM_XCELIUM
            `ifdef XCELIUM_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => VCD", $time, `__FILE__, `__LINE__);
                $dumpfile(traceFilePath);
                $dumpvars(0, {{tbtopName}});
            `elsif XCELIUM_DUMP_FSDB
                $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => FSDB", $time, `__FILE__, `__LINE__);

                `ifdef FSDB_AUTO_SWITCH
                    `ifndef FILE_SIZE
                        `define FILE_SIZE 25
                    `endif

                    `ifndef NUM_OF_FILES
                        `define NUM_OF_FILES 1000
                    `endif

                    $fsdbAutoSwitchDumpfile(`FILE_SIZE, {traceFilePath, ".fsdb"}, `NUM_OF_FILES);
                `else // FSDB_AUTO_SWITCH
                    $fsdbDumpfile({traceFilePath, ".fsdb"});
                `endif // FSDB_AUTO_SWITCH

                `ifdef FSDB_DUMP_SVA
                    $fsdbDumpSVA(0, {{tbtopName}});
                `endif // FSDB_DUMP_SVA

                $fsdbDumpvars(0, {{tbtopName}}, "+all");
            `else // Default to SHM for XCELIUM
                $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => SHM", $time, `__FILE__, `__LINE__);

                // Notice: $shm_open cannot accept string variable as the input file name.
                //          e.g. $shm_open({traceFilePath, ".shm"});
                $shm_open("waves.shm");

                $shm_probe({{tbtopName}}, "AS");
            `endif // XCELIUM_DUMP_VCD
        `endif // SIM_XCELIUM
    endfunction

    function void simulation_enableTrace;
        `ifdef SIM_VERILATOR
            $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
            $dumpon;
        `endif

        `ifdef SIM_VCS
            `ifdef VCS_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
                $dumpon;
            `else // VCS_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => FSDB", $time, `__FILE__, `__LINE__);
                $fsdbDumpon;
                // $fsdbDumpMDA(); // enable dump Multi-Dimension-Array
            `endif // VCS_DUMP_VCD
        `endif

        `ifdef SIM_XCELIUM
            `ifdef XCELIUM_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
                $dumpon;
            `elsif XCELIUM_DUMP_FSDB
                $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => FSDB", $time, `__FILE__, `__LINE__);
                $fsdbDumpon;
            `else // Default to SHM for XCELIUM
                $display("[INFO] @%0t [%s:%d] simulation_enableTrace trace type => SHM", $time, `__FILE__, `__LINE__);
                // SHM tracing is enabled by default when $shm_probe is called
            `endif // XCELIUM_DUMP_VCD
        `endif // SIM_XCELIUM
    endfunction

    function void simulation_disableTrace;
        `ifdef SIM_VERILATOR
            $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
            $dumpoff;
        `endif

        `ifdef SIM_VCS
            `ifdef VCS_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
                $dumpoff;
            `else // VCS_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => FSDB", $time, `__FILE__, `__LINE__);
                $fsdbDumpoff;
            `endif // VCS_DUMP_VCD
        `endif

        `ifdef SIM_XCELIUM
            `ifdef XCELIUM_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => VCD", $time, `__FILE__, `__LINE__);
                $dumpoff;
            `elsif XCELIUM_DUMP_FSDB
                $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => FSDB", $time, `__FILE__, `__LINE__);
                $fsdbDumpoff;
            `else // Default to SHM for XCELIUM
                $display("[INFO] @%0t [%s:%d] simulation_disableTrace trace type => SHM", $time, `__FILE__, `__LINE__);
                $shm_close;
            `endif // XCELIUM_DUMP_VCD
        `endif // SIM_XCELIUM
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
        // +dump_file=<file_name>
        if ($value$plusargs("dump_file=%s", dump_file))
            $display("[INFO] @%0t [%s:%d] dump_file => %s ", $time, `__FILE__, `__LINE__, dump_file);
        else
            $display("[INFO] @%0t [%s:%d] [default] dump_file => %s ", $time, `__FILE__, `__LINE__, dump_file);

        // 2. set dump start cycle
        // +dump_start_cycle=<cycle_number>
        if ($value$plusargs("dump_start_cycle=%d", dump_start_cycle))
            $display("[INFO] @%0t [%s:%d] dump_start_cycle: %d ", $time, `__FILE__, `__LINE__, dump_start_cycle);

        // 3. set dump type
        // +dump_vcd
        if ($test$plusargs("dump_vcd")) begin
            $display("[INFO] @%0t [%s:%d] enable dump_vcd ", $time, `__FILE__, `__LINE__);

            repeat(dump_start_cycle) @(posedge {{clockSignalName}});
            $display("[INFO] @%0t [%s:%d] start dump_vcd at cycle => %d... ", $time, `__FILE__, `__LINE__, dump_start_cycle);

            $dumpfile({dump_file, ".vcd"});
            $dumpvars(0, {{tbtopName}});
        // +dump_fsdb
        end else if ($test$plusargs("dump_fsdb")) begin
            `ifndef VCS_DUMP_VCD
                $display("[INFO] @%0t [%s:%d] enable dump_fsdb ", $time, `__FILE__, `__LINE__);

                repeat(dump_start_cycle) @(posedge {{clockSignalName}});
                $display("[INFO] @%0t [%s:%d] start dump_fsdb at cycle => %d... ", $time, `__FILE__, `__LINE__, dump_start_cycle);
                $fsdbDumpfile({dump_file, ".fsdb"});
                $fsdbDumpvars(0, {{tbtopName}});
            `else // VCS_DUMP_VCD
                $error("VCS_DUMP_VCD is defined, but dump_fsdb is requested. Please check your configuration.");
            `endif // VCS_DUMP_VCD
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
  .reset({% if resetSignalName == "" %}0{% else %}{{resetSignalName}}{% endif %})
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

        auto lastId = 0;
        if (!portInfos.empty()) {
            lastId = portInfos.back().id;
        }
        std::vector<std::string> signalConnVec;
        std::vector<std::string> signalDeclVec;
        std::vector<std::string> regInitializeVec;
        for (auto &port : parser.portInfos) {
            signalConnVec.push_back(fmt::format("\t.{:<30} ({:<30}) /* direction: {:<10} dataType: {} */", port.name, port.name, port.dir, port.type));

            if (port.name == clockSignalName || port.name == resetSignalName) {
                continue;
            } else {
                signalDeclVec.push_back(fmt::format("{} // {}", port.toDeclString(), port.toString()));
                if (port.isInput()) {
                    std::string regInitializeStr = "";
                    if (port.dimensions.size() > 0) {
                        std::string indexStr = "";
                        for (int i = 0; i < port.dimensions.size(); i++) {
                            std::string indexName = fmt::format("i{}", i);
                            regInitializeStr += fmt::format("\tfor(int {0} = 0; {0} < ({1}); {0}++)\n", indexName, port.dimSizes[i]);
                            indexStr += fmt::format("[{}]", indexName);
                        }
                        regInitializeStr += "\t" + fmt::format("\t{}{} = 0;", port.name, indexStr);
                    } else {
                        regInitializeStr += "\t" + fmt::format("{} = 0;", port.name);
                    }
                    regInitializeVec.push_back(regInitializeStr);
                }
            }
        }
        signalDecl    = joinStrVec(signalDeclVec, "\n");
        signalConnect = joinStrVec(signalConnVec, ",\n");
        regInitialize = joinStrVec(regInitializeVec, "\n");

        std::string tbtopPortParamDecl = "";
        std::string dutPortParamDecl   = "";
        if (portParamStmts.size() > 0) {
            tbtopPortParamDecl = fmt::to_string(fmt::join(portParamStmts, ",\n"));
            tbtopPortParamDecl = fmt::format("#(\n{}\n)", tbtopPortParamDecl);
            dutPortParamDecl   = fmt::to_string(fmt::join(portParamInstStmts, ",\n"));
            dutPortParamDecl   = fmt::format("#(\n{}\n)", dutPortParamDecl);
        }

        json tbtopData;
        tbtopData["tbtopName"]                  = tbtopName;
        tbtopData["tbtopPortParamDecl"]         = tbtopPortParamDecl;
        tbtopData["topName"]                    = topName;
        tbtopData["dutName"]                    = dutName;
        tbtopData["dutPortParamDecl"]           = dutPortParamDecl;
        tbtopData["clockPeriod"]                = (double)(period / 2.0); // half period for clock toggle
        tbtopData["clockSignalName"]            = clockSignalName;
        tbtopData["resetSignalName"]            = resetSignalName;
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

        std::ofstream tbtopFile(tbtopFilePath);
        ASSERT(tbtopFile.is_open(), "Can't open file", tbtopFilePath);

        tbtopFile << inja::render(tbtopFileContent, tbtopData);
        tbtopFile.close();

        if (!std::filesystem::exists(othersFilePath)) {
            fmt::println("[testbench_gen] Creating others.sv...");
            std::ofstream othersFile(othersFilePath);
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

        // Save othersFileMTime into meta info
        auto othersFileMTime            = std::filesystem::last_write_time(othersFilePath);
        metaInfoJson["othersFileMTime"] = to_time_t(othersFileMTime);

        // Save other infos into meta info
        metaInfoJson["outputFiles"] = {tbtopFilePath, othersFilePath};
        metaInfoJson["buildTime"]   = get_current_time_as_string();

        // Write meta info into a json file, which can be used next time to check if the output is up to date
        std::ofstream o(metaInfoFilePath);
        o << metaInfoJson.dump(4) << "\n";
        o.close();

        // Generate lua meta file
        if (luaMetaFile != "") {
            std::vector<std::string> luaMetaFileContentVec;
            luaMetaFileContentVec.reserve(parser.portInfos.size() + 2);
            luaMetaFileContentVec.emplace_back("---@meta");
            luaMetaFileContentVec.emplace_back("");
            luaMetaFileContentVec.emplace_back("------------------------------------------------------------------------");
            luaMetaFileContentVec.emplace_back("--- This file is generated by testbench_gen, do not edit it manually!");
            luaMetaFileContentVec.emplace_back("------------------------------------------------------------------------");
            luaMetaFileContentVec.emplace_back("");
            luaMetaFileContentVec.emplace_back("--- Usage example:");
            luaMetaFileContentVec.emplace_back("--- ```lua");
            luaMetaFileContentVec.emplace_back("--- ---@cast _G.dut DUT");
            luaMetaFileContentVec.emplace_back("--- local dut = _G.dut;");
            luaMetaFileContentVec.emplace_back("--- -- Now you can use `dut` with type annotation!");
            luaMetaFileContentVec.emplace_back("--- ```");
            luaMetaFileContentVec.emplace_back("");
            luaMetaFileContentVec.emplace_back("---@class DUT: verilua.handles.ProxyTableHandle");

            for (auto &port : parser.portInfos) {
                luaMetaFileContentVec.emplace_back(fmt::format("---@field {} verilua.handles.CallableHDL {}", port.name, port.toString()));
            }

            std::ofstream o(luaMetaFile);
            ASSERT(o.is_open(), "Cannot open lua meta file", luaMetaFile);
            o << fmt::to_string(fmt::join(luaMetaFileContentVec, "\n")) << "\n";
            o.close();
        }
    }

    if (checkOutput) {
        fmt::println("\n[testbench_gen] Checking output files...");

        driver.sourceLoader.addFiles(tbtopFilePath);
        driver.sourceLoader.addFiles(othersFilePath);
        driver.options.topModules.clear();
        driver.options.topModules.push_back(tbtopName);

        ASSERT(driver.processOptions());
        ASSERT(driver.parseAllSources());

        ASSERT(driver.runFullCompilation(false));
    }
}

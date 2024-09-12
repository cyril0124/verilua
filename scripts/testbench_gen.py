import argparse
import pyslang
import fnmatch
import os

CLOCK_PATTERNS = ["clock", "clock_i", "clk", "clk_i", "enq_clock"]
RESET_PATTERNS = ["reset", "reset_i", "rst", "rst_i", "enq_reset"]

REG_STR = "reg"
WIRE_STR = "wire"

class PortInfo:
  def __init__(self, name, width, dir, array_size = 0, is_disable=False):
    assert name  != None
    assert width != None
    assert dir   != None
    self.name       = name
    self.width      = width
    self.array_size = array_size
    self.dir        = dir
    self.is_disable = is_disable
  
  def is_array(self):
    return self.array_size != 0
  
  def is_input(self):
    return self.dir == "In"

  def is_output(self):
    return self.dir == "Out"
  
  def is_clock(self):
    return self.name in CLOCK_PATTERNS and self.width == 1
  
  def is_reset(self):
    return self.name in RESET_PATTERNS and self.width == 1

  def is_settable(self):
    return self.is_input()

def extract_filelist(file):
  assert file.endswith(".f")
  filelist = []
  with open(os.path.abspath(file), "r") as f:
    dirname = os.path.dirname(os.path.abspath(file))
    for line in f:
      if line.strip():
        ff = line.strip()
        if not os.path.exists(ff):
          basename = os.path.basename(ff)
          new_ff = f"{dirname}/{basename}"
          assert os.path.exists(new_ff)
          ff = new_ff
        else:
          ff = os.path.abspath(ff)
        filelist.append(ff)
  s = "\n".join(filelist)
  print(f"get filelist => \n{s}")
  return filelist

parser = argparse.ArgumentParser(description='A script used for automatically generating Verilua testbenchs.')
parser.add_argument('--top', '-t', dest="top", type=str, required=True, help='top module name')
parser.add_argument('--file', '-f', dest="file", action='append', required=True, help='input verilog file')
parser.add_argument('--dir', '-d', dest="dir", type=str, help='output dir')
parser.add_argument('--period', '-p', dest="period", type=int, help='clock period')
parser.add_argument('--tbtop', dest="tbtop", type=str, help='testbench top level name')
parser.add_argument('--dut-name', dest="dut_name", type=str, help='testbench dut inst name')
parser.add_argument('--dsignals', '-ds', dest="dsignals", type=str, help='signal patterns (a pattern file) indicated which signal should be ignore while generate port interface functions')
parser.add_argument('--nodpi', '-nd', dest="nodpi", action='store_true', help='whether generate DPI-C port interface functions or not')
parser.add_argument('--ignore-error', '-ne', dest="ignore_error", action='store_true', help='ignore the slang compilation error')
parser.add_argument('--verbose', '-v', dest="verbose", action='store_true', help='verbose')
parser.add_argument('--custom-code', '-cc', dest="custom_code", type=str, help='input custom code <file>, will be inserted in the bottom of the testbench module')
parser.add_argument('--custom-code-str', '-ccs', dest="custom_code_str", type=str, help='input custom code <string>, will be inserted in the bottom of the testbench module')
parser.add_argument('--custom-code-outer', '-cco', dest="custom_code_outer", type=str, help='input custom code <file>, will be inserted in outer of the testbench module')
parser.add_argument('--custom-code-str-outer', '-ccso', dest="custom_code_str_outer", type=str, help='input custom code <string>, will be inserted in outer of the testbench module')
args = parser.parse_args()

assert args.top != None, "top module name is not specified!"

clock_period      = args.period or 5
tb_top_name       = args.tbtop or "tb_top"
expected_top_name = args.top
dsignals_file     = args.dsignals
out_dir           = os.path.abspath(args.dir or "./")
verbose           = args.verbose
design_files      = [os.path.abspath(f) for f in args.file]

assert len(design_files) != 0, "you should use <--file/-f> to point out the design files"
for f in design_files:
  assert os.path.isfile(f), f"input verilog file is not exist ==> {f}"

###############################################
# disable pattern
###############################################
disable_patterns = []
if dsignals_file != None:
  with open(dsignals_file, 'r') as file:
    for i, line in enumerate(file.readlines()):
      print(i, line)
      if fnmatch.fnmatch(line, "//*") or fnmatch.fnmatch(line, '#*'):
        continue
      disable_patterns.append(line.strip("\n"))

def check_disable(port_name):
  if len(disable_patterns) == 0:
    return False
  else:
    for p in disable_patterns:
      match = fnmatch.fnmatch(port_name, p)
      if match:
        verbose and print(f"disable match => {p} {port_name}")
        return True
    return False


###############################################
# parse design file
###############################################
c = pyslang.Compilation()
for f in design_files:
  if f.endswith(".f"):
    file_list = extract_filelist(f)
    for ff in file_list:
      print(f"[testbench_gen] append syntaxTree => {ff}")
      tree = pyslang.SyntaxTree.fromFile(ff)
      c.addSyntaxTree(tree)
  else:
    print(f"[testbench_gen] append syntaxTree => {f}")
    tree = pyslang.SyntaxTree.fromFile(f)
    c.addSyntaxTree(tree)


###############################################
# check diagnostics
###############################################
diags = c.getAllDiagnostics()
if len(diags) != 0 and not args.ignore_error:
  for diag in diags:
    if diag.isError():
      err = pyslang.DiagnosticEngine.reportAll(pyslang.SyntaxTree.getDefaultSourceManager(), diags)
      assert False, f"There are some errors in your rtl file! => {err}"

parsed_top_name = c.getRoot().topInstances[0].name
top_name        = parsed_top_name
assert parsed_top_name == expected_top_name, f"{parsed_top_name} =/= {expected_top_name}"

root = c.getRoot().find(expected_top_name)
assert root != None, "root not found!"

ports = []
port_max_len = 0
root_body = root.body
for i, port in enumerate(root_body.portList):
  assert port.isAnsiPort
  name       = port.name
  direction  = port.direction.name
  ptype      = port.type.__str__()
  print(f"[{i}]\tname: {name}\tport_type: {ptype}\tdirection: {direction}")
  
  if isinstance(port.type, pyslang.FixedSizeUnpackedArrayType):
    # FixedSizeArray, e.g. logic[31:0]$[0:59] => 60 elements, ecach element has bit width of 32
    # logic [arrayElementType_width]$[fixedRange_width]
    arrayElementType_width = port.type.arrayElementType.getBitVectorRange().width
    fixedRange_width = port.type.fixedRange.width
    
    width = arrayElementType_width
    array_size = fixedRange_width
    
    ports.append(PortInfo(name, width, direction, array_size, is_disable))
    verbose and print(f"find array port({type(port.type).__name__}) => name: {name:<30} type: {ptype:<15} width: {width:<5} array_size: {array_size:<5} direction: {direction:<4} is_disable: {is_disable}")
    
    # assert False, f"TODO: [{i}] " + f"name: {name} " + f"ptype: {ptype} " + f"arrayElement_width: {arrayElementType_width} " + f"fixedRange_width: {fixedRange_width}"
  elif isinstance(port.type, pyslang.ScalarType) or isinstance(port.type, pyslang.PackedArrayType):
    width      = port.type.getBitVectorRange().width
    is_disable = check_disable(name)
    
    if port_max_len < len(name):
        port_max_len = len(name)
    
    verbose and print(f"find port({type(port.type).__name__}) => name: {name:<30} type: {ptype:<15} width: {width:<5} direction: {direction:<4} is_disable: {is_disable}")
    ports.append(PortInfo(name, width, direction, 0, is_disable))
  else:
    assert False, f"Unknown type => {type(port.type)}"


# assert False
# ast = None
# with open(ast_json, 'r') as file:
#   ast = json.load(file)
# assert ast != None

# ###############################################
# # read top level module info from ast
# ###############################################
# top = ast["members"][1]["body"]
# top_name = top["name"]
# assert top_name == expected_top_name, f"{top_name} =/= {expected_top_name}"
# print(f"top module is {top_name}")


# ###############################################
# # parse port info from ast
# ###############################################

# port_width_pattern = r'\[(\d+):0\]'
# for member in top["members"]:
#   if member["kind"] == "Port":
#     port_name = member["name"]
#     port_type = member["type"]
#     port_dir = member["direction"]
        
#     matches = re.findall(port_width_pattern, member["type"])
#     port_width = 1
#     if matches != []:
#       assert len(matches) == 1
#       port_width = int(matches[0]) + 1
    
#     if port_max_len < len(port_name):
#       port_max_len = len(port_name)
    
#     is_disable = check_disable(port_name)
#     verbose and print(f"find port => name: {port_name:<30} type: {port_type:<15} width: {port_width:<5} direction: {port_dir:<4} is_disable: {is_disable}")
#     ports.append(PortInfo(port_name, port_width, port_dir, 0, is_disable))


###############################################
# check for existence of clock and reset signal
###############################################
has_clock = False
has_reset = False
clock_port = None
reset_port = None
for port in ports:
  if port.name in CLOCK_PATTERNS and port.width == 1 and not port.is_disable:
    assert has_clock == False
    has_clock = True
    clock_port = port
  if port.name in RESET_PATTERNS and port.width == 1 and not port.is_disable:
    assert has_reset == False
    has_reset = True
    reset_port = port
assert has_clock and has_reset, f"has_clock: {has_clock}  has_reset: {has_reset}"

nr_ports = len(ports)


###############################################
# a simple DSL for code generation
###############################################
f = None
def p(*args, file=None):
  if file is None:
    file = f
  print(*args, file=file)

f = open(f"{out_dir}/{tb_top_name}.sv", "w")


###############################################
# test bench generate
###############################################
p("""
`timescale 1ns/1ns

// -----------------------------------------
// test bench generated by VERILUA
// -----------------------------------------""")
p(f"""
// -----------------------------------------
// user custom code 
//    use `--custom-code-outer/-cco <file>` to pass in the custom code file.
//       |_ e.g. `python3 testbench_gen.py [...] --custom-code-outer path/to/file`
//    use `--custom-code-str-outer/-ccso <string>` to pass in the custom code string.
//       |_ e.g. `python3 testbench_gen.py [...] --custom-code-str-outer "`define a 1"`
// -----------------------------------------
""")
if args.custom_code_outer != None:
  custom_code_file = os.path.abspath(args.custom_code_outer)
  assert os.path.exists(custom_code_file), f"custom_code file does not exist! ==> {custom_code_file}"
  content = None
  with open(custom_code_file, 'r') as ff:
    content = ff.read()
  assert content != None
  content_str = str(content)
  p(
f"""
{content_str}
""")
else:
  p("// ... \n")
if args.custom_code_str_outer != None:
  content_str = str(args.custom_code_str_outer)
  p(
f"""
{content_str}
""")
else:
  p("// ... \n")
p(f"module {tb_top_name}(")
p(
f"""
`ifdef SIM_VERILATOR
  input wire {clock_port.name},
  input wire {reset_port.name}
`endif // SIM_VERILATOR""")
p(");\n")

p(
f"""
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
""")

p("""
// -----------------------------------------
// reg/wire declaration
// -----------------------------------------""")
for i, port in enumerate(ports):
  if port.is_clock() or port.is_reset():
    continue
  if port.is_input():
    if port.is_array():
      if port.width == 1:
        p(f"{REG_STR:<15} {port.name}[0:{port.array_size - 1}];")
      else:
        tmp_str = f"reg [{port.width-1}:0]"
        p(f"{tmp_str:<15} {port.name}[0:{port.array_size - 1}];")
    else:
      if port.width == 1:
        p(f"{REG_STR:<15} {port.name};")
      else:
        tmp_str = f"reg [{port.width-1}:0]"
        p(f"{tmp_str:<15} {port.name};")
  else:
    assert port.is_output()
    if port.is_array():
      if port.width == 1:
        p(f"{WIRE_STR:<15} {port.name}[0:{port.array_size - 1}];")
      else:
        tmp_str = f"wire [{port.width-1}:0]"
        p(f"{tmp_str:<15} {port.name}[0:{port.array_size - 1}];")
    else:
      if port.width == 1:
        p(f"{WIRE_STR:<15} {port.name};")
      else:
        tmp_str = f"wire [{port.width-1}:0]"
        p(f"{tmp_str:<15} {port.name};")
p()


total_array_count = 0
array_count = 0
for port in ports:
  if port.is_input() and port.is_array():
    total_array_count = total_array_count + 1

p("""
// -----------------------------------------
//  reg initialize
// ----------------------------------------- """)
p("initial begin")
for i, port in enumerate(ports):
  if i == 0:
    for idx in range(total_array_count):
      p(f"\tinteger i_{idx};")
    p(f'\t$display("[INFO] @%0t [%s:%d] hello from {tb_top_name}", $time, `__FILE__, `__LINE__);')
    
  if port.is_clock() or port.is_reset():
    continue
  if port.is_input():
    if port.is_array():
      index_var = f"i_{array_count}"
      # p(f"\tinteger {index_var};")
      p(f"\tfor({index_var} = 0; {index_var} < {port.array_size}; {index_var}++) begin")
      for i in range(port.array_size):
        p(f"\t\t{port.name}[{i}] = 0;")
      p(f"\tend")
      array_count = array_count + 1
    else:
      p(f"\t{port.name:<{port_max_len}} = 0;")
p("end\n")

p(f"""
// -----------------------------------------
// deal with clock, reset, cycles
// -----------------------------------------""")
p(
f"""`ifndef SIM_VERILATOR
  {REG_STR:<15} {clock_port.name};
  {REG_STR:<15} {reset_port.name};
  
  initial begin
    {clock_port.name:<10} = 0;
    {reset_port.name:<10} = 1;
  end
  
  always #{clock_period} {clock_port.name} <= ~{clock_port.name};
`endif // SIM_VERILATOR""")
p(
f"""
reg [63:0] cycles;

initial cycles = 0;

always@(posedge {clock_port.name}) begin
  if ({reset_port.name})
    cycles <= 0;
  else
    cycles <= cycles + 1;
end\n""")

p(f"""
// -----------------------------------------
// verilua mode selection (only for vcs)
// -----------------------------------------""")
p(
f"""
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

// always@(posedge {clock_port.name}) begin
// 	#1 verilua_main_step();
// end

always@(negedge {clock_port.name}) begin
	verilua_main_step();
end

final begin
  verilua_final();
end
`endif

`endif\n""")

if not args.nodpi:
  p(
  f"""
export "DPI-C" function getBitWidth_cycles;
export "DPI-C" function getBits_cycles;
function void getBitWidth_cycles;
  output int value;
  value = 64;
endfunction
function void getBits_cycles;
  output bit [63:0] value_cycles;
  value_cycles = cycles;
endfunction\n""")

# TOP module instantiate
dut_name = f"u_{top_name}"
if args.dut_name != None:
  dut_name = args.dut_name
p("""
// -----------------------------------------
//  TOP module instantiate
// -----------------------------------------""")
p(f"{top_name} {dut_name} (")
for i, port in enumerate(ports):
  if i == nr_ports - 1:
    p(f"\t.{port.name:<{port_max_len+1}}({port.name})")
  else:
    p(f"\t.{port.name:<{port_max_len+1}}({port.name}),")
p(f"); // u_{top_name}\n")

if not args.nodpi:
  p(f"""
// -----------------------------------------
// port access functions
// https://github.com/chipsalliance/chisel/blob/main/svsim/src/main/scala/Workspace.scala
// -----------------------------------------""")
  for i, port in enumerate(ports):
    set_value_str = f"{port.name} =  value_{port.name};"
    unsupport_set_value_str = f'$display("[ERROR] @%0t [%s:%d] read-only port => {port.name}", $time, `__FILE__, `__LINE__); $fatal;'
    cond_str = set_value_str if port.is_settable() else unsupport_set_value_str
    bit_width_str = f"[{port.width-1}:0]" if port.width > 1 else ""
    
    if port.is_disable:
      verbose and print(f"ignore port => {port.name}")
      continue
    
    if port.is_clock() or port.is_reset():
      p(f"""
`ifndef SIM_VERILATOR
// [{i}] {port.name}
export "DPI-C" function getBitWidth_{port.name};
export "DPI-C" function setBits_{port.name};
export "DPI-C" function getBits_{port.name};
function void getBitWidth_{port.name};
  output int value;
  value = {port.width};
endfunction
function void setBits_{port.name};
  input bit {bit_width_str} value_{port.name};
  {cond_str}
endfunction
function void getBits_{port.name};
  output bit {bit_width_str} value_{port.name};
  value_{port.name} = {port.name};
endfunction
`endif // SIM_VERILATOR""")
      continue
      
    p(
    f"""
// [{i}] {port.name}
export "DPI-C" function getBitWidth_{port.name};
export "DPI-C" function setBits_{port.name};
export "DPI-C" function getBits_{port.name};
function void getBitWidth_{port.name};
  output int value;
  value = {port.width};
endfunction
function void setBits_{port.name};
  input bit {bit_width_str} value_{port.name};
  {cond_str}
endfunction
function void getBits_{port.name};
  output bit {bit_width_str} value_{port.name};
  value_{port.name} = {port.name};
endfunction""")
  p()
  
p(f"""
// -----------------------------------------
// tracing functions
// https://github.com/chipsalliance/chisel/blob/main/svsim/src/main/scala/Workspace.scala
// -----------------------------------------""")
p(
f"""
`ifndef SIM_IVERILOG
  export "DPI-C" function simulation_initializeTrace;
  export "DPI-C" function simulation_enableTrace;
  export "DPI-C" function simulation_disableTrace;

  function void simulation_initializeTrace;
    input string traceFilePath;
  `ifdef SIM_VERILATOR
    $display("[INFO] @%0t [%s:%d] simulation_initializeTrace trace type => VCD", $time, `__FILE__, `__LINE__);
    $dumpfile({{traceFilePath, ".vcd"}});
    $dumpvars(0, {tb_top_name});
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

      $fsdbAutoSwitchDumpfile(`FILE_SIZE, {{traceFilePath, ".fsdb"}}, `NUM_OF_FILES);
    `else
      $fsdbDumpfile({{traceFilePath, ".fsdb"}});
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
    $fsdbDumpvars(0, {tb_top_name}, "+all");
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
`endif

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

always@(posedge clock or negedge clock) begin
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
`endif\n""")

p(f"""
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

        repeat(dump_start_cycle) @(posedge {clock_port.name});
        $display("[INFO] @%0t [%s:%d] start dump_vcd at cycle => %d... ", $time, `__FILE__, `__LINE__, dump_start_cycle);

        $dumpfile({{dump_file, ".vcd"}});
        $dumpvars(0, {tb_top_name});
      end else if ($test$plusargs("dump_fsdb")) begin
        $display("[INFO] @%0t [%s:%d] enable dump_fsdb ", $time, `__FILE__, `__LINE__);
        
        repeat(dump_start_cycle) @(posedge {clock_port.name});
        $display("[INFO] @%0t [%s:%d] start dump_fsdb at cycle => %d... ", $time, `__FILE__, `__LINE__, dump_start_cycle);
        $fsdbDumpfile({{dump_file, ".fsdb"}});
        $fsdbDumpvars(0, {tb_top_name});
      end else begin
        $display("[ERROR] @%0t [%s:%d] neither dump_vcd or dump_fsdb are not pass in", $time, `__FILE__, `__LINE__);
        $fatal;
      end
    end
  end
`endif\n""")

# p(
# f"""
# // -----------------------------------------
# // misc code
# // -----------------------------------------
# reg clean;
# reg dump;
# reg logEnable;
# wire [63:0] timer;

# initial begin
#   clean = 0;
#   dump = 0;
#   logEnable = 0;
# end

# assign timer = cycles;

# """)


p(f"""
// -----------------------------------------
// user custom code 
//    use `--custom-code/-cc <file>` to pass in the custom code file.
//       |_ e.g. `python3 testbench_gen.py [...] --custom-code path/to/file`
//    use `--custom-code-str/-ccs <string>` to pass in the custom code string.
//       |_ e.g. `python3 testbench_gen.py [...] --custom-code-str "reg a; initial a = 1;"`
// -----------------------------------------
""")
if args.custom_code != None:
  custom_code_file = os.path.abspath(args.custom_code)
  assert os.path.exists(custom_code_file), f"custom_code file does not exist! ==> {custom_code_file}"
  content = None
  with open(custom_code_file, 'r') as ff:
    content = ff.read()
  assert content != None
  content_str = str(content)
  p(
f"""
{content_str}
""")
else:
  p("// ... \n")
if args.custom_code_str != None:
  content_str = str(args.custom_code_str)
  p(
f"""
{content_str}
""")
else:
  p("// ... \n")


p(
f"""
// -----------------------------------------
// other user code...
// -----------------------------------------
Others u_others(
  .clock({clock_port.name}),
  .reset({reset_port.name})
);
""")

p(f"\nendmodule // {tb_top_name}")
f.close()

others_file = f"{out_dir}/others.sv"
if not os.path.isfile(others_file):
  f = open(others_file, "w")
  p(
  f"""
  module Others (
    input wire clock,
    input wire reset
  );

  // -----------------------------------------
  // other user code...
  // -----------------------------------------
  // ...

  endmodule
  """)
  f.close()


print("FINISH!")

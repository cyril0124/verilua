import argparse
import pyslang
import fnmatch
import json
import os
import re

class PortInfo:
  def __init__(self, name, width, dir, is_disable=False):
    assert name  != None
    assert width != None
    assert dir   != None
    self.name       = name
    self.width      = width
    self.dir        = dir
    self.is_disable = is_disable
  
  def is_input(self):
    return self.dir == "In"

  def is_output(self):
    return self.dir == "Out"
  
  def is_clock(self):
    return self.name == "clock" and self.width == 1
  
  def is_reset(self):
    return self.name == "reset" and self.width == 1

  def is_settable(self):
    return self.is_input()


parser = argparse.ArgumentParser(description='')
parser.add_argument('--top', '-t', dest="top", type=str, help='top module name')
parser.add_argument('--file', '-f', dest="file", type=str, help='input verilog file')
# parser.add_argument('--ast', '-a', dest="ast", type=str, help='ast json file')
parser.add_argument('--dir', '-d', dest="dir", type=str, help='output dir')
parser.add_argument('--period', '-p', dest="period", type=int, help='clock period')
parser.add_argument('--tbtop', dest="tbtop", type=str, help='testbench top level name')
parser.add_argument('--dsignals', '-ds', dest="dsignals", type=str, help='signal patterns (a pattern file) indicated which signal should be ignore while generate port interface functions')
parser.add_argument('--nodpi', '-nd', dest="nodpi", action='store_true', help='whether generate DPI-C port interface functions or not')
parser.add_argument('--verbose', '-v', dest="verbose", action='store_true', help='verbose')
args = parser.parse_args()

assert args.top != None, "top module name is not specified!"
# assert args.ast != None, "ast json file is not specified!"

clock_period      = args.period or 5
tb_top_name       = args.tbtop or "tb_top"
expected_top_name = args.top
# ast_json          = args.ast
dsignals_file     = args.dsignals
out_dir           = os.path.abspath(args.dir or "./")
verbose           = args.verbose
design_file       = args.file

assert design_file != None, "you should use <--file> to point out the design file"
assert os.path.isfile(design_file), "input verilog file is not exist"

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
tree = pyslang.SyntaxTree.fromFile(design_file)
c    = pyslang.Compilation()
c.addSyntaxTree(tree)

parsed_top_name = c.getRoot().topInstances[0].name
top_name        = parsed_top_name
assert parsed_top_name == expected_top_name, f"{parsed_top_name} =/= {expected_top_name}"

root = c.getRoot().find(expected_top_name)
assert root != None, "root not found!"

ports = []
port_max_len = 0
root_body = root.body
for port in root_body.portList:
  assert port.isAnsiPort
  name       = port.name
  direction  = port.direction.name
  ptype      = port.type.__str__()
  width      = port.type.getBitVectorRange().width
  is_disable = check_disable(name)
  
  if port_max_len < len(name):
      port_max_len = len(name)
  
  verbose and print(f"find port => name: {name:<30} type: {ptype:<15} width: {width:<5} direction: {direction:<4} is_disable: {is_disable}")
  ports.append(PortInfo(name, width, direction, is_disable))


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
#     ports.append(PortInfo(port_name, port_width, port_dir, is_disable))


###############################################
# check for existence of clock and reset signal
###############################################
has_clock = False
has_reset = False
clock_port = None
reset_port = None
for port in ports:
  if port.name == "clock" and port.width == 1 and not port.is_disable:
    assert has_clock == False
    has_clock = True
    clock_port = port
  if port.name == "reset" and port.width == 1 and not port.is_disable:
    assert has_reset == False
    has_reset = True
    reset_port = port
assert has_clock and has_reset

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
    initial begin
      $error("Neither SIM_VERILATOR nor SIM_VCS is defined. One must be defined.");
      $finish;
    end
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
    if port.width == 1:
      p(f"{f"reg":<15} {port.name};")
    else:
      p(f"{f"reg [{port.width-1}:0]":<15} {port.name};")
  else:
    assert port.is_output()
    if port.width == 1:
      p(f"{f"wire":<15} {port.name};")
    else:
      p(f"{f"wire [{port.width-1}:0]":<15} {port.name};")
p()

p("""
// -----------------------------------------
//  reg initialize
// ----------------------------------------- """)
p("initial begin")
p(f'\t$display("[INFO] @%0t [%s:%d] hello from {tb_top_name}", $time, `__FILE__, `__LINE__);')
for port in ports:
  if port.is_clock() or port.is_reset():
    continue
  if port.is_input():
    p(f"\t{port.name:<{port_max_len}} = 0;")
p("end\n")

p(f"""
// -----------------------------------------
// deal with clock, reset, cycles
// -----------------------------------------""")
p(
f"""`ifndef SIM_VERILATOR
  {f"reg":<15} {clock_port.name};
  {f"reg":<15} {reset_port.name};
  
  initial begin
    {clock_port.name:<10} = 0;
    {reset_port.name:<10} = 0;
  end
  
  always #{clock_period} {clock_port.name} <= ~{clock_port.name};
`endif // SIM_VERILATOR""")
p(
f"""
reg [63:0] cycles;

initial cycles = 0;

always@(posedge {clock_port.name}) begin
  if (reset)
    cycles <= 0;
  else
    cycles <= cycles + 1;
end\n""")

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
p("""
// -----------------------------------------
//  TOP module instantiate
// -----------------------------------------""")
p(f"{top_name} u_{top_name} (")
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
  $fsdbDumpfile({{traceFilePath, ".fsdb"}});
  $fsdbDumpvars(0, {tb_top_name});
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
endfunction\n""")

p(f"""
// -----------------------------------------
// tracing command interface
// -----------------------------------------
`ifndef SIM_VERILATOR
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

        repeat(dump_start_cycle) @(posedge clock);
        $display("[INFO] @%0t [%s:%d] start dump_vcd at cycle => %d... ", $time, `__FILE__, `__LINE__, dump_start_cycle);

        $dumpfile({{dump_file, ".vcd"}});
        $dumpvars(0, {tb_top_name});
      end else if ($test$plusargs("dump_fsdb")) begin
        $display("[INFO] @%0t [%s:%d] enable dump_fsdb ", $time, `__FILE__, `__LINE__);
        
        repeat(dump_start_cycle) @(posedge clock);
        `ifdef SIM_VCS
          $display("[INFO] @%0t [%s:%d] start dump_fsdb at cycle => %d... ", $time, `__FILE__, `__LINE__, dump_start_cycle);
          $fsdbDumpfile({{dump_file, ".fsdb"}});
          $fsdbDumpvars(0, {tb_top_name});
        `else
          $display("[ERROR] @%0t [%s:%d] SIM_VCS is not defined!... ", $time, `__FILE__, `__LINE__);
          $fatal;
        `endif
      end else begin
        $display("[ERROR] @%0t [%s:%d] neither dump_vcd or dump_fsdb are not pass in", $time, `__FILE__, `__LINE__);
        $fatal;
      end
    end
  end
`endif\n""")

p(
f"""
// -----------------------------------------
// misc code
// -----------------------------------------
reg clean;
reg dump;
reg logEnable;
wire [63:0] timer;

initial begin
  clean = 0;
  dump = 0;
  logEnable = 0;
end

assign timer = cycles;

""")

p(
f"""
// -----------------------------------------
// other user code...
// -----------------------------------------
Others u_others(
  .clock(clock),
  .reset(reset)
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

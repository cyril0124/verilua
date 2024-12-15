module tb_top(
`ifdef VERILATOR
    input wire clk,
    input wire reset
`endif
);

`ifndef VERILATOR
reg clk;
reg reset;
`endif

wire clock;
assign clock = clk;

wire [7:0] count0;
wire [7:0] count1;
wire [7:0] count2;

Top uut (
    .clk(clk),
    .reset(reset),
    .count0(count0),
    .count1(count1),
    .count2(count2)
);

`ifndef VERILATOR
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

initial begin
    reset = 1;
    #10;
    reset = 0;
end
`endif

`ifdef VERILUA

// When using verilua as HSE(Hardware Script Engine), you should call `verilua_init()` at
// the start of the simulation and call `verilua_final()` at the end of the simulation.
// Also, you should call `verilua_main_step_safe()` every clock step either on posedge or
// negedge of the clock. We recommend the negedge.
import "DPI-C" function void verilua_init();
import "DPI-C" function void verilua_final();
import "DPI-C" function void verilua_main_step_safe();

`ifdef VERILATOR
    initial verilua_init();
`else
    initial #1 verilua_init();
`endif

always @ (negedge clk) begin
  verilua_main_step_safe();
end

final verilua_final();

`endif

endmodule

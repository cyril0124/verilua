module top(
`ifdef VERILATOR
    input wire clock
`endif
);

`ifndef VERILATOR
reg clock;

initial begin
    clock = 1'b0;
    forever #5 clock = ~clock;
end
`endif

reg [63:0] cycles;

initial begin
    cycles = 0;
end

always @(posedge clock) begin
    cycles <= cycles + 1;
end

reg [31:0] accumulator;

wire acc_valid;
wire [31:0] acc_value;

initial begin
    accumulator = 0;
end

always @(posedge clock) begin
    if (acc_valid) begin
        accumulator <= accumulator + acc_value;
    end
end

empty u_empty(
    .clock(clock),
    .cycles(cycles),
    .accumulator(accumulator),
    .valid(acc_valid),
    .value(acc_value)
);


wire [31:0] value32;
wire [63:0] value64;
wire [127:0] value128;

empty2 u_empty2(
    .clock(clock),
    .value32(value32),
    .value64(value64),
    .value128(value128)
);

import "DPI-C" function void verilua_init();
import "DPI-C" function void verilua_final();
import "DPI-C" function void verilua_main_step_safe();

initial verilua_init();

always @ (negedge clock) begin
  verilua_main_step_safe();
end

final verilua_final();

endmodule

module empty(
    input wire clock,
    input wire [63:0] cycles,
    input wire [31:0] accumulator,
    output reg valid,
    output reg [31:0] value
);

// The real logic is not implemented here.
// See `main.lua` for the real logic. It is all implemented in Lua script using HSE with dummy-vpi support.

endmodule

module empty2(
    input wire clock,
    output reg [31:0] value32,
    output reg [63:0] value64,
    output reg [127:0] value128
);

// The real logic is not implemented here.
// See `main.lua` for the real logic. It is all implemented in Lua script using HSE with dummy-vpi support.

endmodule

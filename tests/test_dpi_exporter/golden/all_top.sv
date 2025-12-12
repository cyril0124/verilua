
module A(
    input wire clock,
    input wire reset,
    
    input wire [31:0] i_value_0,
    input wire [63:0] i_value_1,
    input wire [128:0] i_value_2,
    input wire [66:0] i_value_3,

    output reg o_value_0,
    output reg o_value_1,
    output reg o_value_2
);

reg test;

C c_inst (
    .clock(clock),
    .reset(reset)
);

endmodule

module B(
    input wire clock,
    input wire reset
);

wire valid;
wire valid1;

reg i_value_0;
reg i_value_1;
reg i_value_2;

wire o_value_0;
wire o_value_1;
wire o_value_2;

A a_inst_0 (
    .clock(clock),
    .reset(reset),
    .i_value_0(i_value_0),
    .i_value_1(i_value_1),
    .i_value_2(i_value_2),
    .o_value_0(o_value_0),
    .o_value_1(o_value_1),
    .o_value_2(o_value_2)
);


reg i_value_4;
reg i_value_5;
reg i_value_6;

wire o_value_4;
wire o_value_5;
wire o_value_6;

A a_inst_1 (
    .clock(clock),
    .reset(reset),
    .i_value_0(i_value_4),
    .i_value_1(i_value_5),
    .i_value_2(i_value_6),
    .o_value_0(o_value_4),
    .o_value_1(o_value_5),
    .o_value_2(o_value_6)
);

reg [63:0] signal;
reg signal1;
reg signal2;

endmodule

module C(
    input wire i_value_0,
    input wire i_value_1,
    input wire i_value_2,

    // output wire w_value_0, // NET should not be marked as writable
    output reg w_value_1,
    output reg [7:0] w_value_2,
    output reg [63:0] w_value_3,
    output reg [127:0] w_value_4,
    output reg [66:0] w_value_5,

    input wire clock,
    input wire reset
); 

endmodule

module D;

reg value_0;
reg value_test_1;
reg value_2;

endmodule

module top(
    input wire clock,
    input wire reset,
    output reg [7:0] value,
    output reg [63:0] value64
);

reg clk;

reg i_value_0;
reg i_value_1;
reg i_value_2;

wire o_value_0;
wire o_value_1;
wire o_value_2;

A a_inst_0 (
    .clock(clock),
    .reset(reset),
    .i_value_0(i_value_0),
    .i_value_1(i_value_1),
    .i_value_2(i_value_2),
    .o_value_0(o_value_0),
    .o_value_1(o_value_1),
    .o_value_2(o_value_2)
);

initial begin
    $display("current line: %d", `__LINE__);
end

reg i_value_4;
reg i_value_5;
reg i_value_6;

wire o_value_4;
wire o_value_5;
wire o_value_6;

A a_inst_1 (
    .clock(clock),
    .reset(reset),
    .i_value_0(i_value_4),
    .i_value_1(i_value_5),
    .i_value_2(i_value_6),
    .o_value_0(o_value_4),
    .o_value_1(o_value_5),
    .o_value_2(o_value_6)
);

B b_inst (
    .clock(clock),
    .reset(reset)
);

D d_inst();

reg [7:0] counter;
always @(posedge clock) begin
    if (reset) begin
        counter <= 0;
    end else begin
        counter <= counter + 1;
    end
end

import "DPI-C" function void dpi_exporter_tick(
	input bit [31:0] top_b_inst_a_inst_0_i_value_0,
	input bit [63:0] top_b_inst_a_inst_0_i_value_1,
	input bit [128:0] top_b_inst_a_inst_0_i_value_2,
	input bit [66:0] top_b_inst_a_inst_0_i_value_3,
	output bit top_a_inst_0_c_inst_w_value_1,
	output bit top_a_inst_1_c_inst_w_value_1,
	output bit top_b_inst_a_inst_1_c_inst_w_value_1,
	output bit [7:0] top_a_inst_0_c_inst_w_value_2,
	output bit [7:0] top_a_inst_1_c_inst_w_value_2,
	output bit [7:0] top_b_inst_a_inst_1_c_inst_w_value_2,
	output bit [63:0] top_a_inst_0_c_inst_w_value_3,
	output bit [63:0] top_a_inst_1_c_inst_w_value_3,
	output bit [63:0] top_b_inst_a_inst_1_c_inst_w_value_3,
	output bit [127:0] top_a_inst_0_c_inst_w_value_4,
	output bit [127:0] top_a_inst_1_c_inst_w_value_4,
	output bit [127:0] top_b_inst_a_inst_1_c_inst_w_value_4,
	output bit [66:0] top_a_inst_0_c_inst_w_value_5,
	output bit [66:0] top_a_inst_1_c_inst_w_value_5,
	output bit [66:0] top_b_inst_a_inst_1_c_inst_w_value_5,
	output bit top_b_inst_a_inst_0_c_inst_w_value_1,
	output bit [7:0] top_b_inst_a_inst_0_c_inst_w_value_2,
	output bit [63:0] top_b_inst_a_inst_0_c_inst_w_value_3,
	output bit [127:0] top_b_inst_a_inst_0_c_inst_w_value_4,
	output bit [66:0] top_b_inst_a_inst_0_c_inst_w_value_5,
	input bit top_d_inst_value_0,
	input bit top_d_inst_value_2
);



`ifndef MANUALLY_CALL_DPI_EXPORTER_TICK
/*
Sensitive group name: i_signals
Sensitive trigger signals:
	top_b_inst_valid
*/
bit top_b_inst_valid__LAST;
import "DPI-C" function void dpi_exporter_tick_i_signals(
	input bit top_b_inst_valid,
	input bit top_b_inst_i_value_0,
	input bit top_b_inst_i_value_1,
	input bit top_b_inst_i_value_2,
	input bit top_b_inst_i_value_4,
	input bit top_b_inst_i_value_5,
	input bit top_b_inst_i_value_6
);
`endif // MANUALLY_CALL_DPI_EXPORTER_TICK

`ifndef MANUALLY_CALL_DPI_EXPORTER_TICK
/*
Sensitive group name: o_signals
Sensitive trigger signals:
	top_b_inst_valid1
*/
bit top_b_inst_valid1__LAST;
import "DPI-C" function void dpi_exporter_tick_o_signals(
	input bit top_b_inst_valid1,
	input bit top_b_inst_o_value_0,
	input bit top_b_inst_o_value_1,
	input bit top_b_inst_o_value_2,
	input bit top_b_inst_o_value_4,
	input bit top_b_inst_o_value_5,
	input bit top_b_inst_o_value_6
);
`endif // MANUALLY_CALL_DPI_EXPORTER_TICK

`ifndef MANUALLY_CALL_DPI_EXPORTER_TICK
/*
Sensitive group name: UNKNOWN_3
Sensitive trigger signals:
	top_b_inst_signal1
	top_b_inst_signal2
*/
bit top_b_inst_signal1__LAST;
bit top_b_inst_signal2__LAST;
import "DPI-C" function void dpi_exporter_tick_UNKNOWN_3(
	input bit [63:0] top_b_inst_signal,
	input bit top_b_inst_signal1,
	input bit top_b_inst_signal2
);
`endif // MANUALLY_CALL_DPI_EXPORTER_TICK

`ifndef MANUALLY_CALL_DPI_EXPORTER_TICK
/*
Sensitive group name: n2
Sensitive trigger signals:
	top_i_value_0
*/
bit top_i_value_0__LAST;
import "DPI-C" function void dpi_exporter_tick_n2(
	input bit top_i_value_0,
	input bit top_i_value_1,
	input bit top_i_value_2,
	input bit top_i_value_4,
	input bit top_i_value_5,
	input bit top_i_value_6
);
`endif // MANUALLY_CALL_DPI_EXPORTER_TICK

`ifndef MANUALLY_CALL_DPI_EXPORTER_TICK
/*
Sensitive group name: n3
Sensitive trigger signals:
	top_o_value_0
*/
bit top_o_value_0__LAST;
import "DPI-C" function void dpi_exporter_tick_n3(
	input bit top_o_value_0,
	input bit top_o_value_1,
	input bit top_o_value_2,
	input bit top_o_value_4,
	input bit top_o_value_5,
	input bit top_o_value_6
);
`endif // MANUALLY_CALL_DPI_EXPORTER_TICK


`define DECL_DPI_EXPORTER_TICK \
    import "DPI-C" function void dpi_exporter_tick( \
	input bit [31:0] top_b_inst_a_inst_0_i_value_0, \
	input bit [63:0] top_b_inst_a_inst_0_i_value_1, \
	input bit [128:0] top_b_inst_a_inst_0_i_value_2, \
	input bit [66:0] top_b_inst_a_inst_0_i_value_3, \
	output bit top_a_inst_0_c_inst_w_value_1, \
	output bit top_a_inst_1_c_inst_w_value_1, \
	output bit top_b_inst_a_inst_1_c_inst_w_value_1, \
	output bit [7:0] top_a_inst_0_c_inst_w_value_2, \
	output bit [7:0] top_a_inst_1_c_inst_w_value_2, \
	output bit [7:0] top_b_inst_a_inst_1_c_inst_w_value_2, \
	output bit [63:0] top_a_inst_0_c_inst_w_value_3, \
	output bit [63:0] top_a_inst_1_c_inst_w_value_3, \
	output bit [63:0] top_b_inst_a_inst_1_c_inst_w_value_3, \
	output bit [127:0] top_a_inst_0_c_inst_w_value_4, \
	output bit [127:0] top_a_inst_1_c_inst_w_value_4, \
	output bit [127:0] top_b_inst_a_inst_1_c_inst_w_value_4, \
	output bit [66:0] top_a_inst_0_c_inst_w_value_5, \
	output bit [66:0] top_a_inst_1_c_inst_w_value_5, \
	output bit [66:0] top_b_inst_a_inst_1_c_inst_w_value_5, \
	output bit top_b_inst_a_inst_0_c_inst_w_value_1, \
	output bit [7:0] top_b_inst_a_inst_0_c_inst_w_value_2, \
	output bit [63:0] top_b_inst_a_inst_0_c_inst_w_value_3, \
	output bit [127:0] top_b_inst_a_inst_0_c_inst_w_value_4, \
	output bit [66:0] top_b_inst_a_inst_0_c_inst_w_value_5, \
	input bit top_d_inst_value_0, \
	input bit top_d_inst_value_2); \
    bit top_b_inst_valid__LAST; \
	import "DPI-C" function void dpi_exporter_tick_i_signals( \
		input bit top_b_inst_valid, \
		input bit top_b_inst_i_value_0, \
		input bit top_b_inst_i_value_1, \
		input bit top_b_inst_i_value_2, \
		input bit top_b_inst_i_value_4, \
		input bit top_b_inst_i_value_5, \
		input bit top_b_inst_i_value_6 \
	); \
	bit top_b_inst_valid1__LAST; \
	import "DPI-C" function void dpi_exporter_tick_o_signals( \
		input bit top_b_inst_valid1, \
		input bit top_b_inst_o_value_0, \
		input bit top_b_inst_o_value_1, \
		input bit top_b_inst_o_value_2, \
		input bit top_b_inst_o_value_4, \
		input bit top_b_inst_o_value_5, \
		input bit top_b_inst_o_value_6 \
	); \
	bit top_b_inst_signal1__LAST; \
	bit top_b_inst_signal2__LAST; \
	import "DPI-C" function void dpi_exporter_tick_UNKNOWN_3( \
		input bit [63:0] top_b_inst_signal, \
		input bit top_b_inst_signal1, \
		input bit top_b_inst_signal2 \
	); \
	bit top_i_value_0__LAST; \
	import "DPI-C" function void dpi_exporter_tick_n2( \
		input bit top_i_value_0, \
		input bit top_i_value_1, \
		input bit top_i_value_2, \
		input bit top_i_value_4, \
		input bit top_i_value_5, \
		input bit top_i_value_6 \
	); \
	bit top_o_value_0__LAST; \
	import "DPI-C" function void dpi_exporter_tick_n3( \
		input bit top_o_value_0, \
		input bit top_o_value_1, \
		input bit top_o_value_2, \
		input bit top_o_value_4, \
		input bit top_o_value_5, \
		input bit top_o_value_6 \
	); 
            

`define CALL_DPI_EXPORTER_TICK \
    if((top.b_inst.valid ^ top_b_inst_valid__LAST) ||top.b_inst.valid ) begin \
        dpi_exporter_tick_i_signals( \
			top.b_inst.valid, \
			top.b_inst.i_value_0, \
			top.b_inst.i_value_1, \
			top.b_inst.i_value_2, \
			top.b_inst.i_value_4, \
			top.b_inst.i_value_5, \
			top.b_inst.i_value_6); \
    end \
    top_b_inst_valid__LAST <= top.b_inst.valid;  \
    if((top.b_inst.valid1 ^ top_b_inst_valid1__LAST) ||top.b_inst.valid1 ) begin \
        dpi_exporter_tick_o_signals( \
			top.b_inst.valid1, \
			top.b_inst.o_value_0, \
			top.b_inst.o_value_1, \
			top.b_inst.o_value_2, \
			top.b_inst.o_value_4, \
			top.b_inst.o_value_5, \
			top.b_inst.o_value_6); \
    end \
    top_b_inst_valid1__LAST <= top.b_inst.valid1;  \
    if((top.b_inst.signal1 ^ top_b_inst_signal1__LAST) ||(top.b_inst.signal2 ^ top_b_inst_signal2__LAST) ||top.b_inst.signal1 ||top.b_inst.signal2 ) begin \
        dpi_exporter_tick_UNKNOWN_3( \
			top.b_inst.signal, \
			top.b_inst.signal1, \
			top.b_inst.signal2); \
    end \
    top_b_inst_signal1__LAST <= top.b_inst.signal1; \
	top_b_inst_signal2__LAST <= top.b_inst.signal2;  \
    if((top.i_value_0 ^ top_i_value_0__LAST) ||top.i_value_0 ) begin \
        dpi_exporter_tick_n2( \
			top.i_value_0, \
			top.i_value_1, \
			top.i_value_2, \
			top.i_value_4, \
			top.i_value_5, \
			top.i_value_6); \
    end \
    top_i_value_0__LAST <= top.i_value_0;  \
    if((top.o_value_0 ^ top_o_value_0__LAST) ||top.o_value_0 ) begin \
        dpi_exporter_tick_n3( \
			top.o_value_0, \
			top.o_value_1, \
			top.o_value_2, \
			top.o_value_4, \
			top.o_value_5, \
			top.o_value_6); \
    end \
    top_o_value_0__LAST <= top.o_value_0;  \
    begin \
        dpi_exporter_tick( \
			top.b_inst.a_inst_0.i_value_0, \
			top.b_inst.a_inst_0.i_value_1, \
			top.b_inst.a_inst_0.i_value_2, \
			top.b_inst.a_inst_0.i_value_3, \
			top.a_inst_0.c_inst.w_value_1, \
			top.a_inst_1.c_inst.w_value_1, \
			top.b_inst.a_inst_1.c_inst.w_value_1, \
			top.a_inst_0.c_inst.w_value_2, \
			top.a_inst_1.c_inst.w_value_2, \
			top.b_inst.a_inst_1.c_inst.w_value_2, \
			top.a_inst_0.c_inst.w_value_3, \
			top.a_inst_1.c_inst.w_value_3, \
			top.b_inst.a_inst_1.c_inst.w_value_3, \
			top.a_inst_0.c_inst.w_value_4, \
			top.a_inst_1.c_inst.w_value_4, \
			top.b_inst.a_inst_1.c_inst.w_value_4, \
			top.a_inst_0.c_inst.w_value_5, \
			top.a_inst_1.c_inst.w_value_5, \
			top.b_inst.a_inst_1.c_inst.w_value_5, \
			top.b_inst.a_inst_0.c_inst.w_value_1, \
			top.b_inst.a_inst_0.c_inst.w_value_2, \
			top.b_inst.a_inst_0.c_inst.w_value_3, \
			top.b_inst.a_inst_0.c_inst.w_value_4, \
			top.b_inst.a_inst_0.c_inst.w_value_5, \
			top.d_inst.value_0, \
			top.d_inst.value_2); \
    end
    
            

// If this macro(`MANUALLY_CALL_DPI_EXPORTER_TICK`) is defined, the DPI tick function will be called manually in other places. 
// Users can use with `DECL_DPI_EXPORTER_TICK` and `CALL_DPI_EXPORTER_TICK` to call the DPI tick function manually.
`ifndef MANUALLY_CALL_DPI_EXPORTER_TICK
always @(negedge top.clock) begin
`CALL_DPI_EXPORTER_TICK
end
`endif // MANUALLY_CALL_DPI_EXPORTER_TICK




endmodule

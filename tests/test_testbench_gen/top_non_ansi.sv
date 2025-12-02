module TopNonAnsi#(
    parameter integer VAL = 11,
    parameter MASK = 8'hff,
    parameter real RATIO = 0.75,
    parameter string NAME = "default",
    // Extended parameter types
    parameter shortint SHORT_VAL = 16'h1234,
    parameter longint LONG_VAL = 64'h123456789ABCDEF0,
    parameter byte BYTE_VAL = 8'hAB,
    parameter bit [7:0] BIT_PARAM = 8'hCD,
    parameter logic [15:0] LOGIC_PARAM = 16'hEF01
)
(
    clk, reset,
    count0, count1, count2,
    oo1, oo2, oo3, oo4, oo5,
    o, o3, o4, o5, o6, o7, o8, o9, o10,
    ii1, ii2, ii3, ii4, ii5, ii6, ii7,
    i, i2, i3, i4, i5, i6, i7, i10, i11, i12,
    sda, scl, bidir_data, bidir_bus
);

input clk;
input reset;
input i;
input [7:0] i2 [3:0][3:0];
input [VAL-1:0] i3 [3:0][VAL-1:0][VAL-1:0];
input i4;
input i5;
input [7:0] i6;
input [VAL-1:0] i7 [3:0];
input i10;

input wire [7:0] i11[VAL-1:0], i12[1:0][2:0];

input ii1;
input ii2;
input ii3;

input [7:0] ii4;
input [7:0] ii5;
input [7:0] ii6;
input ii7;

output [7:0] count0;
output [7:0] count1;
output [VAL-1:0] count2;
output o;
output o3;
output o4;
output [7:0] o5;
output [7:0] o6;
output [7:0] o7;
output [7:0] o8 [3:0];
output [VAL-1:0] o9 [3:0][VAL-1:0][VAL-1:0];
output [7:0] o10 [0:9];

output oo1;
output oo2;

output [7:0] oo3;
output [7:0] oo4;

output oo5;

// inout ports for bidirectional signals
inout wire sda;
inout wire scl;
inout wire [7:0] bidir_data;
inout wire [15:0] bidir_bus;

reg [7:0] count0;
reg [7:0] count1;
reg [VAL-1:0] count2;
reg o3;
reg [7:0] o6;

reg oo1;
reg oo2;

reg [7:0] oo3;
reg [7:0] oo4;



endmodule
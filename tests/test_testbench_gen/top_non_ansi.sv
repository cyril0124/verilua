module TopNonAnsi#(
    parameter integer VAL = 11,
    parameter MASK = 8'hff,
    parameter real RATIO = 0.75,
    parameter string NAME = "default"
)
(
    clk, reset,
    count0, count1, count2,
    o, o3, o4, o5, o6, o7, o8, o9, o10,
    i, i2, i3, i4, i5, i6, i7, i10, i11, i12
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


reg [7:0] count0;
reg [7:0] count1;
reg [VAL-1:0] count2;
reg o3;
reg [7:0] o6;



endmodule
module top(
    input wire clock,
    input wire reset
);

wire w1;
wire [7:0] w8;
wire [127:0] w128;

reg r1;
reg [7:0] r8;
reg [127:0] r128;

logic l1;
logic [7:0] l8;
logic [127:0] l128;

bit b1;
bit [7:0] b8;
bit [127:0] b128;

Sub u_sub(
    .clock(clock),
    .reset(reset)
);

Sub u_sub2(
    .clock(clock),
    .reset(reset)
);

endmodule;


module Sub(
    input wire clock,
    input wire reset
);

wire w1;
wire [7:0] w8;
wire [127:0] w128;

reg r1;
reg [7:0] r8;
reg [127:0] r128;

endmodule
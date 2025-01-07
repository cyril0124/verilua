module Top (
    input wire clk,
    input wire reset,
    output reg [7:0] count0,
    output reg [7:0] count1,
    output reg [7:0] count2 
);

reg clock;
reg [7:0] value;

always @(posedge clk) begin
    if (reset) begin
        count0 <= 0;
        count1 <= 0;
        count2 <= 0;
        value <= 0;
    end else begin
        count0 <= count0 + 1;
        count1 <= count1 + 2;
        count2 <= count2 + 3;
        value <= value + 4;
    end
end

Sub u_sub(
    .clock(clk),
    .signal(count2[0]),
    .value(count0),
    .value1(count1),
    .value2(count2),
    .value3({count0, count1, count2}),
    .value5({count0, count1}),
    .value4()
);

Sub u_sub1(
    .clock(clk),
    .signal(count2[0]),
    .value(count0),
    .value1(count1),
    .value2(count2),
    .value3({count0, count1, count2}),
    .value5({count0, count1}),
    .value4()
);

Another u_sub2(
    .clock(clk),
    .value(count0),
    .value1(count1),
    .value2(count2),
    .value3({count0, count1, count2}),
    .value5({count0, count1}),
    .value4()
);

endmodule

module Sub(
    input wire clock,
    input wire signal,
    input wire [7:0] value,
    input wire [33:0] value1,
    input wire [63:0] value2,
    input wire [255:0] value3,
    input wire [53:0] value5,
    output reg value4
);

reg test;

endmodule

module Another(
    input wire clock,
    input wire [7:0] value,
    input wire [33:0] value1,
    input wire [63:0] value2,
    input wire [255:0] value3,
    input wire [60:0] value5,
    output reg value4
);

reg test;

endmodule
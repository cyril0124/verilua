module TopAnsi#(
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
    input wire clk,
    input wire reset,
    output reg [7:0] count0,
    output reg [7:0] count1,
    output reg [VAL-1:0] count2,

    output reg oo1,
               oo2,

    output reg [7:0] oo3,
                     oo4,

    output oo5,

    output logic o,
    output reg o3,
    output wire o4,
    output logic [7:0] o5,
    output reg [7:0] o6,
    output wire [7:0] o7,
    output logic [7:0] o8 [3:0],
    output logic [VAL-1:0] o9 [3:0][VAL-1:0][VAL-1:0],
    output logic [7:0] o10 [0:9],

    input   ii1,
            ii2,
            ii3,

    input [7:0] ii4,
                ii5,
                ii6,

    input ii7,

    input logic i,
    input wire [7:0] i2 [3:0][3:0],
    input logic [VAL-1:0] i3 [3:0][VAL-1:0][VAL-1:0],
    input bit i4,
    input i5,
    input [7:0] i6,
    input [VAL-1:0] i7[3:0],

    input wire [3:0] io_axi_cfg_awregion,

    input bit i10,

    // inout ports for bidirectional signals (e.g., I2C, SPI)
    inout wire sda,
    inout wire scl,
    inout wire [7:0] bidir_data,
    inout wire [15:0] bidir_bus
);

function void test_func;
    input string _test_func_i;
    output bit _test_func_o;
endfunction

endmodule

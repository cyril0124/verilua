module top(
    input wire clock,
    input wire reset,

    input wire i_valid,
    output wire i_ready,
    input wire [7:0] i_data,

    output wire o_valid,
    input wire o_ready,
    output wire [7:0] o_data,

    output wire _tmp
);

reg reg1;
reg [7:0] reg8;
reg [15:0] reg16;
reg [31:0] reg32;
reg [63:0] reg64;
reg [67:0] reg68;
reg [127:0] reg128;
initial begin
    reg1 = 1;
    reg8 = 8;
    reg16 = 16;
    reg32 = 32;
    reg64 = 64;
    reg68 = 68;
    reg128 = 128;
end

bit bit1;
bit [7:0] bit8;
bit [15:0] bit16;
bit [31:0] bit32;
bit [63:0] bit64;
bit [67:0] bit68;
bit [127:0] bit128;
initial begin
    bit1 = 1;
    bit8 = 8;
    bit16 = 16;
    bit32 = 32;
    bit64 = 64;
    bit68 = 68;
    bit128 = 128;
end

logic logic1;
logic [7:0] logic8;
logic [15:0] logic16;
logic [31:0] logic32;
logic [63:0] logic64;
logic [67:0] logic68;
logic [127:0] logic128;
initial begin
    logic1 = 1;
    logic8 = 8;
    logic16 = 16;
    logic32 = 32;
    logic64 = 64;
    logic68 = 68;
    logic128 = 128;
end

reg [7:0] two_dim_reg[0:3];
initial begin
    for(integer i = 0; i < 4; i = i + 1) begin
        two_dim_reg[i] = i;
    end
end


endmodule
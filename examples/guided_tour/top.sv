module top (
    input wire clock,
    input wire reset
);

reg [7:0] internal_reg;
initial begin
    internal_reg = 0;
end
always @(posedge clock) begin
    if (reset) begin
        internal_reg <= 0;
    end else begin
        internal_reg <= internal_reg + 1;
    end
end

reg [3:0] reg4;
reg [31:0] reg32;
reg [47:0] reg48;
reg [63:0] reg64;
reg [127:0] reg128;
initial begin
    reg4 = 4;
    reg32 = 32;
    reg48 = 48;
    reg64 = 64'hffffffffffffffff;
    reg128 = 128;
end

sub u_sub(
    .clock(clock),
    .reset(reset),
    .some_prefix_valid(internal_reg[0]),
    .some_prefix_ready(),
    .some_prefix_bits_data_0(reg128[7:0]),
    .some_prefix_bits_data_1(reg128[15:8]),
    .some_prefix_bits_data_2(reg128[23:16])
);

endmodule

module sub(
    input wire clock,   
    input wire reset,
    input wire some_prefix_valid,
    output wire some_prefix_ready,
    input wire [7:0] some_prefix_bits_data_0,
    input wire [7:0] some_prefix_bits_data_1,
    input wire [7:0] some_prefix_bits_data_2
);

endmodule
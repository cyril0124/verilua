module tb_top(
    input wire clk,
    input wire reset
);

wire i_ready;
wire o_valid;
wire [7:0] o_data;
wire _tmp;

top uut (
    .clock(clk),
    .reset(reset),
    .i_valid(1'b0),
    .i_ready(i_ready),
    .i_data(8'h0),
    .o_valid(o_valid),
    .o_ready(1'b0),
    .o_data(o_data),
    ._tmp(_tmp)
);

endmodule

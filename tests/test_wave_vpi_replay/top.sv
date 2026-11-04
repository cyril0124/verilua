module top(
    input wire clock,
    input wire reset
);

reg [63:0] count;
reg [49:0] value;
reg [127:0] wide_value;

always @(posedge clock) begin
    if (reset) begin
        count <= 0;
        value <= 50'h10000000;
        wide_value <= 128'h123456789abcdef0123456789abcdef0;
    end else begin
        count <= count + 1;
        value <= value + 1'b1;
        wide_value <= wide_value + 1'b1;
    end
end

`ifdef SIM_IVERILOG
// Capture the first clock edge before Icarus applies Lua trace controls.
initial begin
    $dumpfile("random_order.vcd");
    $dumpvars(0);
end
`endif

endmodule

module top(
    input  wire        clock,
    input  wire        reset,
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    input  wire        valid,
    output wire [7:0]  sum,      // comb: a + b
    output wire        ready,    // comb: valid && (counter < 4)
    output wire [7:0]  product,  // comb: a * b (truncated to 8-bit)
    output wire [7:0]  chain,    // comb: 4-level chain fed by a/b
    output reg  [7:0]  counter
);

assign sum     = a + b;
assign ready   = valid && (counter < 4);
assign product = a * b;

// Multi-level combinational chain: a single await_rw() must observe the
// fully settled value even when propagation needs several delta rounds.
wire [7:0] c1 = a ^ b;
wire [7:0] c2 = c1 + 8'd1;
wire [7:0] c3 = c2 & 8'h7F;
assign chain  = c3 ^ 8'h55;

always @(posedge clock) begin
    if (reset)
        counter <= 0;
    else if (valid && ready)
        counter <= counter + 1;
end

endmodule

// Free-running 8-bit counter observed by the coverage bridge test. It has no reset
// input, so its value is deterministic from time 0.
module top (
    input  wire       clock,
    output wire [7:0] count
);

reg [7:0] cnt;

// Explicit initialization keeps the count deterministic even when the simulator
// starts with random register values.
initial cnt = 8'h0;

always @(posedge clock) begin
    cnt <= cnt + 1'b1;
end

assign count = cnt;

endmodule

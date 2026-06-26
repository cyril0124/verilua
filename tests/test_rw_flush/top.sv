// `d` is a plain input wire with no combinational fan-out, so the test
// only checks whether set(d) is flushed before await_rw() resumes.
module top(
    input  wire        clock,
    input  wire        reset,
    input  wire [31:0] d,
    output reg  [31:0] q
);

always @(posedge clock) begin
    if (reset)
        q <= 0;
    else
        q <= d;
end

endmodule

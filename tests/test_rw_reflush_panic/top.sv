// Repro DUT for the cbReadWriteSynch re-flush cross-queue dedup panic.
// `trig` and `shared` are Lua-driven inputs; an observer waits posedge(trig)
// and writes `shared` while it is still queued. `q` just consumes the regs.
module top(
    input  wire        clock,
    input  wire        reset,
    input  wire        trig,
    input  wire [7:0]  shared,
    output reg  [7:0]  q
);

always @(posedge clock) begin
    if (reset)
        q <= 0;
    else
        q <= shared;
end

endmodule

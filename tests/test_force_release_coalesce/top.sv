// Valid/ready handshake used to check same-timeslot set_release + set_force
// coalescing on a continuously backpressured ready.
//
// ready is DUT-driven to 1. The TB forces it low, then each cycle does
// release followed immediately by force again. If those two ops coalesce,
// ready never rises; if they take effect immediately one after another,
// ready glitches 0->1->0 and the async edge detector latches ready_glitch.
module top (
    input  wire       clock,
    input  wire       reset,
    input  wire       valid,
    input  wire       bp_armed, // TB: ready is expected to stay forced low
    output wire       ready,
    output reg  [7:0] count,
    output reg        ready_glitch
);

    // Always-ready sink unless the TB forces ready low.
    assign ready = 1'b1;

    always @(posedge clock) begin
        if (reset) begin
            count <= 8'd0;
        end else if (valid && ready) begin
            count <= count + 8'd1;
        end
    end

    // Catch a mid-timeslot ready rising edge while backpressure should hold.
    always @(posedge ready or posedge reset) begin
        if (reset) begin
            ready_glitch <= 1'b0;
        end else if (bp_armed) begin
            ready_glitch <= 1'b1;
        end
    end

endmodule

// The `verilua.infer_nosim_flags = "vcs"` target's RTL. It only references what `vcs.flags`
// provides, so it elaborates only when the switch restricted the inference to that one source.
module top(
    input  wire        clk,
    input  wire        reset,
    output logic [7:0] probe_out
);
    `include "vcs_a_probe.svh"
    `include "vcs_b_probe.svh"

    logic [7:0] probe_counter;

    always @(posedge clk) begin
        if (reset) begin
            probe_counter <= 8'h00;
        end else begin
            probe_counter <= probe_counter + 8'h01;
        end
    end

    assign probe_out = probe_counter;
endmodule

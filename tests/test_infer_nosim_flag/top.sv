// Each probe header lives in a directory that only one source simulator's flags can add to the
// include search path, and each header references a macro that only that simulator's flags define.
// The module therefore only elaborates when `verilua.infer_nosim_flag` translated the flags of
// verilator/vcs/iverilog/xcelium into `nosim.flags`.
module top(
    input  wire        clk,
    input  wire        reset,
    output logic [7:0] probe_out
);
    `include "vcs_a_probe.svh"
    `include "vcs_b_probe.svh"
    `include "verilator_probe.svh"
    `include "iverilog_probe.svh"
    `include "xcelium_probe.svh"

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

// RTL module for wave_vpi benchmarks.
// Contains 1024 32-bit registers driven by a generate block,
// providing a large number of signals for hot-signal read benchmarks.
module wave_vpi_bench (
    input wire clock,
    input wire reset
);

    genvar gi;
    generate
        for (gi = 0; gi < 1024; gi = gi + 1) begin : r
            reg [31:0] sig;
            always @(posedge clock) begin
                if (reset)
                    sig <= gi[31:0];
                else
                    sig <= sig + 1;
            end
        end
    endgenerate

endmodule

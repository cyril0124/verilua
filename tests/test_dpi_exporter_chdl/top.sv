// Simple DUT for dpi_exporter + dpi-only CallableHDL integration.
module top (
    input  wire       clock,
    input  wire       reset,
    output reg  [7:0] count,
    output wire       valid,
    output reg [63:0] wide64
);
    assign valid = count[0];

    always @(posedge clock) begin
        if (reset) begin
            count  <= 8'd0;
            wide64 <= 64'd0;
        end else begin
            count  <= count + 8'd1;
            wide64 <= wide64 + 64'd3;
        end
    end
endmodule

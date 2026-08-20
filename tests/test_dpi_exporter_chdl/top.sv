// Simple DUT for dpi_exporter + dpi-only CallableHDL integration.
module top (
    input  wire        clock,
    input  wire        reset,
    output reg   [7:0] count,
    output wire        valid,
    output reg  [63:0] wide64,
    output reg [127:0] wide128
);
    assign valid = count[0];

    // meta_only export target: no DPI accessor is generated for it; value is
    // read through a real VPI handle (verilua rule defaults to public-flat-rw).
    reg [15:0] meta16;

    always @(posedge clock) begin
        if (reset) begin
            count   <= 8'd0;
            wide64  <= 64'd0;
            wide128 <= 128'd0;
            meta16  <= 16'd0;
        end else begin
            count   <= count + 8'd1;
            wide64  <= wide64 + 64'd3;
            wide128 <= wide128 + 128'd5;
            meta16  <= meta16 + 16'd2;
        end
    end
endmodule

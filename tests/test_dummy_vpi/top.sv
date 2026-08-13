// DUT for dummy_vpi + DpiExporter CallableHDL (keep VPI handle).
module top (
    input  wire        clock,
    input  wire        reset,
    output reg   [7:0] count,
    output wire        valid,
    output reg  [63:0] wide64,
    output reg [127:0] wide128
);
    assign valid = count[0];

    always @(posedge clock) begin
        if (reset) begin
            count   <= 8'd0;
            wide64  <= 64'd0;
            wide128 <= 128'd0;
        end else begin
            count   <= count + 8'd1;
            wide64  <= wide64 + 64'd3;
            wide128 <= wide128 + 128'd5;
        end
    end
endmodule

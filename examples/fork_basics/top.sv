module top (
    input wire clock,
    input wire reset,
    input wire enable,
    output reg [7:0] counter
);

always @(posedge clock) begin
    if (reset) begin
        counter <= 8'd0;
    end else begin
        if (enable) begin
            counter <= counter + 8'd1;
        end
    end
end

endmodule

module top(
    input clock,
    input reset,
    input enable,
    input [7:0] data_in,
    output reg [7:0] data_out,
    output reg [3:0] counter,
    output reg valid
);

// Simple counter that increments on each clock cycle when enabled
always @(posedge clock or posedge reset) begin
    if (reset) begin
        counter <= 4'h0;
    end else if (enable) begin
        counter <= counter + 1;
    end
end

// Simple data register with valid signal
always @(posedge clock or posedge reset) begin
    if (reset) begin
        data_out <= 8'h00;
        valid <= 1'b0;
    end else if (enable) begin
        data_out <= data_in;
        valid <= 1'b1;
    end else begin
        valid <= 1'b0;
    end
end

endmodule
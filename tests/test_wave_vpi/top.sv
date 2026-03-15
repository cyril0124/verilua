module top(
    input wire clock,
    input wire reset
);

reg [63:0] count;
reg [49:0] value;

always @(posedge clock) begin
    if (reset) begin
        count <= 0;
        value <= 50'h10000000;
    end else begin
        count <= count + 1;
        value <= value + 1'b1;
    end
end

endmodule

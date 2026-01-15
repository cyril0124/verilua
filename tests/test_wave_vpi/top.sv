module top(
    input wire clock,
    input wire reset
);

reg [63:0] count;

always_ff @(clock) begin
    if (reset) begin
        count <= 0;
    end else begin
        count <= count + 1;
    end
end

endmodule

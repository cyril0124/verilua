module Counter (
    input wire clock,
    input wire reset,
    output wire [7:0] count
);

reg [7:0] count_reg;

initial begin
    count_reg = 0;
end

always @(posedge clock) begin
    if (reset) begin
        count_reg <= 0;
    end else if (count_reg < 10) begin
        count_reg <= count_reg + 1;
    end else begin
        count_reg <= 0;
    end
end

assign count = count_reg;

endmodule
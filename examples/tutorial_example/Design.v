module Design(
    input  wire clock,
    input  wire reset,
    input  wire inc,
    output wire [7:0] value
);

reg [7:0] value_reg;

always@(posedge clock) begin
    if (reset) 
        value_reg <= 8'd0;
    else if (inc == 1'b1) begin
        value_reg <= value_reg + 1'b1;
    end 
end

assign value = value_reg;

endmodule

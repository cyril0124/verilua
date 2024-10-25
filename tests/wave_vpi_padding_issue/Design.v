module Design (
    input wire clock,
    input wire reset,
    output reg[49:0] value
);  

always @(posedge clock) begin
    if (reset) 
        value <= 'h10000000;
    else
        value <= value + 1'b1;
end

endmodule
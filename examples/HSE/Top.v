module Top (
    input wire clk,
    input wire reset,
    output reg [7:0] count0,
    output reg [7:0] count1,
    output reg [7:0] count2 
);

reg [7:0] value;
always @(posedge clk) begin
    if (reset) begin
        count0 <= 0;
        count1 <= 0;
        count2 <= 0;
        value <= 0;
    end else begin
        count0 <= count0 + 1;
        count1 <= count1 + 2;
        count2 <= count2 + 3;
        value <= value + 4;
    end
end

endmodule

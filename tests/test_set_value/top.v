module top (
    input wire clock,
    input wire reset,
    input wire [7:0] inc,
    output reg [7:0] count
);

wire [7:0] count_val;
wire [7:0] count_val2;

assign count_val = count;
assign count_val2 = count_val & {8{inc[0]}};

always @(posedge clock) begin
    if (reset) begin
        count <= 8'b0;
    end else begin
        count <= count + inc;
    end
end

reg [7:0] counter;
initial begin
    counter = 0;
end
always @(posedge clock) begin
    if (reset) begin
        counter <= 8'b0;
    end else begin
        counter <= counter + 1'b1;
    end
end

endmodule

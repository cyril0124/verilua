module top(
    input wire clock,
    input wire clock1,
    input wire clock2,
    input wire clock3,
    input wire clock4,

    input wire reset,
    input wire reset1,
    input wire reset2,
    input wire reset3,
    input wire reset4,

    output reg[7:0] count,
    output reg[7:0] count1,
    output reg[7:0] count2,
    output reg[7:0] count3,
    output reg[7:0] count4
);

initial begin
    count = 0;
    count1 = 0;
    count2 = 0;
    count3 = 0;
    count4 = 0;
end

always @(posedge clock) begin
    if (reset) begin
        count <= 0;
    end else begin
        count <= count + 1;
    end
end

always @(posedge clock1) begin
    if (reset1) begin
        count1 <= 0;
    end else begin
        count1 <= count1 + 1;
    end
end

always @(posedge clock2) begin
    if (reset2) begin
        count2 <= 0;
    end else begin
        count2 <= count2 + 1;
    end
end

always @(posedge clock3) begin
    if (reset3) begin
        count3 <= 0;
    end else begin
        count3 <= count3 + 1;
    end
end

always @(posedge clock4) begin
    if (reset4) begin
        count4 <= 0;
    end else begin
        count4 <= count4 + 1;
    end
end

endmodule

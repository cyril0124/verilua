module leaf (
    input wire clock,
    input wire reset,
    output reg [7:0] data
);

always @(posedge clock) begin
    if (reset) begin
        data <= 8'h00;
    end else begin
        data <= data + 1'b1;
    end
end

endmodule

module mid (
    input wire clock,
    input wire reset,
    output wire [7:0] data
);

leaf u_leaf (
    .clock(clock),
    .reset(reset),
    .data(data)
);

endmodule

module top (
    input wire clock,
    input wire reset
);

wire [7:0] data;

mid u_mid (
    .clock(clock),
    .reset(reset),
    .data(data)
);

endmodule

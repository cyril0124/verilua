module top(
    input clock,
    input reset,
    input valid
);

reg en;
initial en = 0;
always @(posedge clock) begin
    en <= en + 1;
end

wire en2;
assign en2 = en & valid;

reg en3;
initial en3 = 0;
always @(posedge clock) begin
    en3 <= en2;
end






reg c_valid;
initial c_valid = 0;

always @(posedge clock) begin
    c_valid <= c_valid + 1;
end

wire c_en2;
assign c_en2 = en & c_valid;

reg c_en3;
initial c_en3 = 0;
always @(posedge clock) begin
    c_en3 <= c_en2;
end


reg [255:0] data;
initial data = 0;
always @(posedge clock) begin
    data <= $urandom();
end

endmodule

module top(
    input clock,
    input reset,
    input wire valid,
    output wire ready
);

reg ready_reg;
reg [63:0] cycles;
initial begin
    ready_reg = 0;
    cycles = 0;
end

always@(posedge clock) begin
    if(reset) begin
        cycles <= 0;
        ready_reg <= 1;
    end else begin
        cycles <= cycles + 1;
        if(cycles == 2) begin
            ready_reg <= 0;
        end
    end
end

assign ready = ready_reg && valid;

endmodule

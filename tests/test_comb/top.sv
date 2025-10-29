
module top(
    input clock,
    input reset,
    output wire [3:0] raddr,
    output wire rvalid,
    input wire [7:0] rdata,
    input wire rresp
);

reg [3:0] step = 0;
initial begin
    @(posedge clock);
    @(posedge clock);
    @(posedge clock);
    @(posedge clock);
    step = 2;
    @(posedge clock);
    step = 3;
    @(posedge clock);
    step = 4;
    @(posedge clock);
    step = 5;
    @(posedge clock);
    step = 6;
end

assign raddr = step;
assign rvalid = step == 2 || step == 4 || step == 5;

always@(negedge clock) begin
    if(step == 2) begin
        if(rdata != 10) $fatal;
        if(rresp != 1) $fatal;
    end else if(step == 3) begin
        if(rresp != 0) $fatal;
    end else if(step == 4) begin
        if(rdata != 20) $fatal;
        if(rresp != 1) $fatal;
    end else if(step == 5) begin
        if(rdata != 20) $fatal;
        if(rresp != 1) $fatal;
    end else if(step == 6) begin
        if(rresp != 0) $fatal;
    end
end

endmodule

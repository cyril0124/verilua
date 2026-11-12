module top (
    input logic clock,
    input logic reset,
    input logic req_valid,
    output logic req_ready,
    input logic [127:0] req_data,
    output logic rsp_valid,
    input logic rsp_ready,
    output logic [127:0] rsp_data
);
    timeunit 1ns;
    timeprecision 1ps;

    int unsigned stall_cycles = 3;
    int unsigned response_delay = 0;
    logic [127:0] pending_data = '0;

    initial begin
        req_ready = 1'b0;
        rsp_valid = 1'b0;
        rsp_data = '0;
    end

    always @(posedge clock) begin
        if (reset) begin
            stall_cycles <= 3;
            response_delay <= 0;
            pending_data <= '0;
            req_ready <= 1'b0;
            rsp_valid <= 1'b0;
            rsp_data <= '0;
        end else begin
            if (stall_cycles > 0) begin
                stall_cycles <= stall_cycles - 1;
                if (stall_cycles == 1) req_ready <= 1'b1;
            end
            if (req_valid && req_ready) begin
                req_ready <= 1'b0;
                pending_data <= req_data;
                response_delay <= 2;
            end else if (response_delay > 0) begin
                response_delay <= response_delay - 1;
                if (response_delay == 1) begin
                    rsp_data <= pending_data;
                    rsp_valid <= 1'b1;
                end
            end
            if (rsp_valid && rsp_ready) begin
                rsp_valid <= 1'b0;
                stall_cycles <= 3;
            end
        end
    end
endmodule

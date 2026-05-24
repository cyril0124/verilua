module top (
    input wire clock,
    input wire reset,
    input wire [7:0] queued_in,
    input wire [7:0] imm_in,
    input wire resp_valid,
    input wire [7:0] resp_data,
    output reg [7:0] sampled_queued,
    output reg [7:0] sampled_imm,
    output wire [7:0] comb_imm,
    output wire req_valid,
    output wire [7:0] req_addr,
    output wire resp_seen_comb,
    output reg resp_seen_sampled,
    output reg [7:0] resp_data_sampled
);

assign comb_imm = imm_in + 8'h11;

reg req_active;
reg req_index;
reg [7:0] dut_owned;

assign req_valid = req_active;
assign req_addr = (req_index == 1'b0) ? 8'h05 :
                  (req_index == 1'b1) ? 8'h09 :
                  8'h00;
assign resp_seen_comb = req_valid && resp_valid && (resp_data == (req_addr + 8'h40));

always @(posedge clock) begin
    if (reset) begin
        sampled_queued <= 8'h00;
        sampled_imm <= 8'h00;
        req_active = 1'b0;
        req_index = 1'b0;
        dut_owned <= 8'h10;
        resp_seen_sampled <= 1'b0;
        resp_data_sampled <= 8'h00;
    end else begin
        sampled_queued <= queued_in;
        sampled_imm <= imm_in;
        dut_owned <= dut_owned + 8'h11;
        resp_seen_sampled <= resp_seen_comb;

        if (!req_active) begin
            req_active = 1'b1;
        end else if (resp_seen_comb) begin
            resp_data_sampled <= resp_data;
            req_active = !req_index;
            req_index = 1'b1;
        end
    end
end

endmodule

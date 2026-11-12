module CombArbiter (
    input  logic        input0_valid,
    input  logic [31:0] input0_data,
    output logic        input0_ready,

    input  logic        input1_valid,
    input  logic [31:0] input1_data,
    output logic        input1_ready,

    output logic        output_valid,
    output logic [31:0] output_data,
    input  logic        output_ready
);
    timeunit 1ns;
    timeprecision 1ps;

    always_comb begin
        output_valid = 1'b0;
        output_data = 32'b0;

        if (input0_valid) begin
            output_valid = 1'b1;
            output_data = input0_data;
        end else if (input1_valid) begin
            output_valid = 1'b1;
            output_data = input1_data;
        end

        input0_ready = output_ready;
        input1_ready = output_ready && !input0_valid;
    end
endmodule

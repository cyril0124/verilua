module top (
    input logic clock
);

    // Basic signals for testing
    logic [7:0]  data_0;
    logic [7:0]  data_1;
    logic [7:0]  data_2;
    logic [15:0] data_wide;

    // Signals for Bundle testing
    logic        valid;
    logic        ready;
    logic [7:0]  bits_field1;
    logic [7:0]  bits_field2;
    logic [15:0] bits_field3;

    // Signals with prefix for Bundle testing
    logic        prefix_valid;
    logic        prefix_ready;
    logic [7:0]  prefix_bits_data;
    logic [7:0]  prefix_bits_addr;

    // Signals for AliasBundle testing
    logic [7:0]  orig_signal_0;
    logic [7:0]  orig_signal_1;
    logic [7:0]  orig_signal_2;

    // Signals for auto_bundle testing with various patterns
    logic [7:0]  axi_aw_valid;
    logic [7:0]  axi_ar_valid;
    logic [7:0]  axi_w_valid;
    logic [7:0]  axi_r_valid;

    logic [7:0]  io_in_value_0;
    logic [7:0]  io_in_value_1;
    logic [7:0]  io_in_value_2;

    logic [7:0]  signal_ending_suffix;
    logic [7:0]  another_ending_suffix;

    logic [31:0] wide_signal_32;
    logic [63:0] wide_signal_64;
    logic [7:0]  narrow_signal_8;

    // Array signals for testing array operations
    logic [7:0]  array_signal [0:3];

    // Optional signals for testing
    logic [7:0]  opt_valid;
    logic [7:0]  opt_data;

    // Submodule for ProxyTableHandle testing
    sub_module u_sub (
        .clock(clock),
        .sub_data_0(data_0),
        .sub_data_1(data_1)
    );

    initial begin
        // Initialize signals
        data_0 = 8'h00;
        data_1 = 8'h01;
        data_2 = 8'h02;
        data_wide = 16'hABCD;

        valid = 1'b0;
        ready = 1'b0;
        bits_field1 = 8'h10;
        bits_field2 = 8'h20;
        bits_field3 = 16'h3030;

        prefix_valid = 1'b0;
        prefix_ready = 1'b0;
        prefix_bits_data = 8'hAA;
        prefix_bits_addr = 8'hBB;

        orig_signal_0 = 8'h55;
        orig_signal_1 = 8'h66;
        orig_signal_2 = 8'h77;

        axi_aw_valid = 8'h01;
        axi_ar_valid = 8'h02;
        axi_w_valid = 8'h03;
        axi_r_valid = 8'h04;

        io_in_value_0 = 8'h10;
        io_in_value_1 = 8'h11;
        io_in_value_2 = 8'h12;

        signal_ending_suffix = 8'hAA;
        another_ending_suffix = 8'hBB;

        wide_signal_32 = 32'hDEADBEEF;
        wide_signal_64 = 64'hCAFEBABEDEADBEEF;
        narrow_signal_8 = 8'h42;

        array_signal[0] = 8'h10;
        array_signal[1] = 8'h20;
        array_signal[2] = 8'h30;
        array_signal[3] = 8'h40;

        opt_valid = 8'h99;
        opt_data = 8'h88;
    end

    always @(posedge clock) begin
        // Simple counter behavior
        data_0 <= data_0 + 1;
        data_1 <= data_1 + 2;
    end

endmodule

module sub_module (
    input  logic       clock,
    input  logic [7:0] sub_data_0,
    input  logic [7:0] sub_data_1
);
    logic [7:0] internal_reg;

    initial begin
        internal_reg = 8'hCC;
    end

    always @(posedge clock) begin
        internal_reg <= sub_data_0;
    end
endmodule

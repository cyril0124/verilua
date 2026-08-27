// Signals cover every beat class the CHDL access layer generates code for:
//   Single  beat_num == 1   (<= 32 bit)
//   Double  beat_num == 2   (33 ~ 64 bit)
//   Multi   beat_num >= 3   (> 64 bit)
// Widths are multiples of 4 so get_hex_str() maps to a fixed nibble count.
module top (
    input logic clock
);

    logic [7:0]   single_8;
    logic [31:0]  single_32;
    logic [63:0]  double_64;
    logic [127:0] multi_128;

    logic [7:0]   arr_single [0:3];
    logic [63:0]  arr_double [0:3];
    logic [127:0] arr_multi  [0:1];

    // force / release / freeze targets, marked forceable for Verilator
    logic [7:0]   force_single;
    logic [63:0]  force_double;
    logic [127:0] force_multi;

    logic [7:0]   force_arr_single [0:1];
    logic [63:0]  force_arr_double [0:1];
    logic [127:0] force_arr_multi  [0:1];

    initial begin
        single_8  = 8'h00;
        single_32 = 32'h0;
        double_64 = 64'h0;
        multi_128 = 128'h0;

        force_single = 8'h00;
        force_double = 64'h0;
        force_multi  = 128'h0;

        for (int i = 0; i < 2; i++) begin
            force_arr_single[i] = 8'h00;
            force_arr_double[i] = 64'h0;
            force_arr_multi[i]  = 128'h0;
        end

        for (int i = 0; i < 4; i++) begin
            arr_single[i] = 8'h00;
            arr_double[i] = 64'h0;
        end
        for (int i = 0; i < 2; i++) begin
            arr_multi[i] = 128'h0;
        end
    end

endmodule

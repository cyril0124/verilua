`timescale 1ns / 1ps

// HSE testbench: Verilator C++ drives clock/reset; VCS generates them here.
module tb_top (
`ifdef VERILATOR
    input wire clock,
    input wire reset
`endif
);

`ifndef VERILATOR
    reg clock;
    reg reset;
`endif

    wire [7:0] count;
    wire valid;
    wire [63:0] wide64;
    wire [127:0] wide128;

    top u_top (
        .clock(clock),
        .reset(reset),
        .count(count),
        .valid(valid),
        .wide64(wide64),
        .wide128(wide128)
    );

`ifndef VERILATOR
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end

    initial begin
        reset = 1;
        #10;
        reset = 0;
    end
`endif

`ifdef VERILUA
    import "DPI-C" function void verilua_init();
    import "DPI-C" function void verilua_final();
    import "DPI-C" function void verilua_main_step();

    initial verilua_init();

    always @(negedge clock) begin
        verilua_main_step();
    end

    final verilua_final();
`endif
endmodule

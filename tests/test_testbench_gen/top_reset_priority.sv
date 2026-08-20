module TopResetPriority(
    input wire clock,
    input wire io_sys_snapshot_reset,
    input wire reset,
    input wire data_in,
    output reg data_out
);

always @(posedge clock) begin
    if (reset)
        data_out <= 1'b0;
    else
        data_out <= data_in;
end

endmodule

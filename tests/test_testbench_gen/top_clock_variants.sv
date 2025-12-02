// Test file for clock/reset signal smart detection
// This module uses various clock/reset naming conventions

module TopClockVariants(
    // Clock variants - should all be detected as clock signals
    input wire sys_clk,        // sys_clk pattern
    input wire i_clock,        // i_clock pattern
    input wire clk_core,       // clk_* pattern
    input wire main_clock,     // *_clock pattern
    
    // Reset variants - should all be detected as reset signals  
    input wire sys_rst_n,      // sys_rst_n pattern (active low)
    input wire i_reset,        // i_reset pattern
    input wire rst_core,       // rst_* pattern
    input wire main_reset_n,   // *_reset_n pattern (active low)
    
    // Regular signals
    input wire [7:0] data_in,
    output reg [7:0] data_out
);

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        data_out <= 8'h00;
    else
        data_out <= data_in;
end

endmodule

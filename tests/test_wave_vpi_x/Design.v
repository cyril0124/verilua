module Design (
    input wire clock,
    input wire reset,
    output reg [7:0] data_a,
    output wire [7:0] data_b,
    output reg [15:0] data_wide
);

// data_a: starts as X (uninitialized), then gets a known value after reset
always @(posedge clock) begin
    if (reset)
        data_a <= 8'hAB;
    else
        data_a <= data_a + 1'b1;
end

// data_b: upper nibble is always known, lower nibble transitions to X then back
reg [3:0] data_b_hi;
reg [3:0] data_b_lo;
reg uninit_flag; // Never assigned — always X in 4-state sim
assign data_b = {data_b_hi, data_b_lo};

// Initialize data_b_lo to a known value so the X transition is a value change
initial begin
    data_b_hi = 4'h0;
    data_b_lo = 4'h0;
end

always @(posedge clock) begin
    if (reset) begin
        data_b_hi <= 4'hA;  // 1010
        // Assign from uninitialized reg to create X as a value change (0 -> X)
        data_b_lo <= {4{uninit_flag}};
    end else begin
        data_b_hi <= 4'hF;
        data_b_lo <= 4'hF;
    end
end

// data_wide: starts as X, then assigned a known value
always @(posedge clock) begin
    if (reset)
        data_wide <= 16'hDEAD;
    else
        data_wide <= data_wide + 1'b1;
end

endmodule

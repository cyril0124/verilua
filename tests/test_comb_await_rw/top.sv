module top(
    input  wire        clock,
    input  wire        reset,
    input  wire        valid,
    output wire        ready,
    output reg  [7:0]  counter
);

// Combinational: ready depends on valid AND internal state
assign ready = valid && (counter < 4);

always @(posedge clock) begin
    if (reset)
        counter <= 0;
    else if (valid && ready)
        counter <= counter + 1;
end

endmodule

module top(
    input  wire        clock,
    input  wire        reset,
    input  wire        valid,
    output wire        ready,    // combinational: ready = valid && (counter < 4)
    output reg  [7:0]  counter
);

assign ready = valid && (counter < 4);

always @(posedge clock) begin
    if (reset)
        counter <= 0;
    else if (valid && ready)
        counter <= counter + 1;
end

endmodule

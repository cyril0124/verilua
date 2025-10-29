module mux(
    output wire out,
    input wire sel,
    input wire a,
    input wire b
);

assign out = sel ? b : a;

endmodule

// Minimal DUT for reproducing issue #11:
// set() behavior inconsistency after value-change callback.
// The observable timing of edge_write:set(1) should not depend on
// whether the source edge originates from RTL or from Verilua.
module top(
    input wire clock,
    input wire reset
);

// Verilua-driven source signal (toggled by Lua set())
reg verilua_driven_reg;
initial verilua_driven_reg = 0;

// SV/RTL-driven source signal (toggled by always block)
reg sv_driven_reg;
initial sv_driven_reg = 0;
always @(posedge clock) begin
    sv_driven_reg <= ~sv_driven_reg;
end

// Target signals written by Lua after observing the source edge
reg edge_write_from_verilua_src;
initial edge_write_from_verilua_src = 0;

reg edge_write_from_sv_src;
initial edge_write_from_sv_src = 0;

endmodule

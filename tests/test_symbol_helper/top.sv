module top;

// A simple C function exported via DPI-C for SymbolHelper to find
import "DPI-C" function int sym_add(input int a, input int b);
import "DPI-C" function int sym_mul(input int a, input int b);

// An SV-exported function for SymbolHelper to call from Lua
export "DPI-C" function sv_square;

function int sv_square;
    input int x;
    sv_square = x * x;
endfunction

endmodule

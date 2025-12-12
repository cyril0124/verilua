module top;

export "DPI-C" function sv_func;

function sv_func;
    input string content;
    $display("[sv_func] got: %s", content);
endfunction

import "DPI-C" function void dpic_func(
    input string content
);

initial begin
    dpic_func("4444");
end

endmodule

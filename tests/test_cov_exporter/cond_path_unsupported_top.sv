// cond_path_unsupported_top — exercises conditions the cov-exporter cannot
// model as path coverage. Each unsupported condition should:
//   * trigger a warning entry in the generated `unsupportedCondStmts`
//     comment block, and
//   * not produce an `_<id>__COV_BIN_EXPR_CNT` counter for the unsupported
//     branch.
module cond_path_unsupported_top(
    input  logic        clock,
    input  logic        reset,
    input  logic [3:0]  pat,
    output logic [3:0]  hit
);

function automatic logic side_effect_call(input logic [3:0] x);
    return x[0];
endfunction

always @(posedge clock) begin
    // Function call inside the if-condition: we must skip it.
    if (side_effect_call(pat)) begin
        hit <= 4'h1;
    end

    // Pattern-matching condition: we must skip it.
    case (pat) inside
        4'h0: hit <= 4'h2;
        default: hit <= 4'h3;
    endcase
end

endmodule

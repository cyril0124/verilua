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

`ifndef NO_COVERAGE

bit _COV_EN = 1;

int _hit__COV_CNT = 0;
int _pat__COV_CNT = 0;
int _reset__COV_CNT = 0;
int _clock__COV_CNT = 0;
bit[3:0] _hit__LAST;
bit[3:0] _pat__LAST;
bit _reset__LAST;
bit _clock__LAST;

always @(posedge clock) begin if(_COV_EN) begin if(hit ^ _hit__LAST) _hit__COV_CNT++; _hit__LAST <= hit; end end
always @(posedge clock) begin if(_COV_EN) begin if(pat ^ _pat__LAST) _pat__COV_CNT++; _pat__LAST <= pat; end end
always @(posedge clock) begin if(_COV_EN) begin if(reset ^ _reset__LAST) _reset__COV_CNT++; _reset__LAST <= reset; end end
always @(posedge clock) begin if(_COV_EN) begin if(clock ^ _clock__LAST) _clock__COV_CNT++; _clock__LAST <= clock; end end



function void coverageCtrl(input bit enable);
    _COV_EN = enable;
endfunction

export "DPI-C" function coverageCtrl;


function void getCoverageCount(output int totalCount, output int totalBinExprCount);
    totalCount = int'((_hit__COV_CNT >= 1 ? 1 : 0) + (_pat__COV_CNT >= 1 ? 1 : 0) + (_reset__COV_CNT >= 1 ? 1 : 0) + (_clock__COV_CNT >= 1 ? 1 : 0));
    totalBinExprCount = int'(0);
endfunction

export "DPI-C" function getCoverageCount;



// scopes:
//   cond_path_unsupported_top
function void getCoverage(output real value);
    value = real'((_hit__COV_CNT >= 1 ? 1 : 0) + (_pat__COV_CNT >= 1 ? 1 : 0) + (_reset__COV_CNT >= 1 ? 1 : 0) + (_clock__COV_CNT >= 1 ? 1 : 0)) / 4.0;
endfunction

export "DPI-C" function getCoverage;



// scopes:
//   cond_path_unsupported_top
function void getCondCoverage(output real value);
    value = real'(1) / 1.0;
endfunction

export "DPI-C" function getCondCoverage;



function void resetCoverage();
_hit__COV_CNT = 0; _pat__COV_CNT = 0; _reset__COV_CNT = 0; _clock__COV_CNT = 0;
endfunction

export "DPI-C" function resetCoverage;



function void showCoverageCount();
$display("// ----------------------------------------");
$display("// Show Coverage Count[cond_path_unsupported_top]");
$display("// ----------------------------------------");
$display("// Column description:");
$display("//   Module    - module name where the coverage point resides");
$display("//   Line      - source line number of the coverage point");
$display("//   Count     - number of times the point was hit during simulation");
$display("//   SignalType - Net (wire toggle), Var (reg toggle), or CondPath {branch entry}");
$display("//   Status    - COVERED {count > 0} or MISSED {count == 0}");
$display("//   Source    - source file path and line");
$display("//   Guard     - {CondPath only} the path condition required to enter this branch");
$display("// ----------------------------------------");
$display("| Module | Line | Count | SignalType | Status | Source | Guard |");
$display("[cond_path_unsupported_top]      7: %6d\t`Var`\t%s	.cov_exporter_unsupported/cond_path_unsupported_top.sv:7", _clock__COV_CNT, _clock__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_unsupported_top]      8: %6d\t`Var`\t%s	.cov_exporter_unsupported/cond_path_unsupported_top.sv:8", _reset__COV_CNT, _reset__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_unsupported_top]      9: %6d\t`Var`\t%s	.cov_exporter_unsupported/cond_path_unsupported_top.sv:9", _pat__COV_CNT, _pat__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_unsupported_top]     10: %6d\t`Var`\t%s	.cov_exporter_unsupported/cond_path_unsupported_top.sv:10", _hit__COV_CNT, _hit__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("| Module | Line | Count | SignalType | Status | Source | Guard |");
$display("");
endfunction

export "DPI-C" function showCoverageCount;



// ==========================================================
//  cov_exporter Statistic
// ----------------------------------------------------------
//   net coverage points    : 0
//   var coverage points    : 4
//   cond-path points       : 0
//   duplicate nets removed : 0
//   unsupported cond stmts : 1
// ----------------------------------------------------------
//   literalEqualNet (excluded):
//       (none)
//   identifierEqualNet (excluded):
//       (none)
//   unsupportedCondStmts:
//       unsupported expression in if-condition: side_effect_call(pat)
// ==========================================================

`endif // NO_COVERAGE

endmodule


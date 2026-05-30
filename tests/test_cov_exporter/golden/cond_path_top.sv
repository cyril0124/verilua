// cond_path_top — exercises nested if/else-if/else paths so the cov-exporter
// instrumentation produces exactly 8 cond-path coverage points:
//   1. reset
//   2. a
//   3. !a && b
//   4. !a && b && c
//   5. !a && !b && d
//   6. !a && !b && !d   (explicit else)
//   7. e                (independent if)
//   8. a & e            (nested inside for-loop)
module cond_path_top(
    input  logic       clock,
    input  logic       reset,
    input  logic       a,
    input  logic       b,
    input  logic       c,
    input  logic       d,
    input  logic       e,
    output logic [7:0] hit
);
`ifndef NO_COVERAGE
bit _COV_EN = 1;
int _0__COV_BIN_EXPR_CNT = 0; // guard: (reset)
int _1__COV_BIN_EXPR_CNT = 0; // guard: (a)
int _2__COV_BIN_EXPR_CNT = 0; // guard: (!(a)) && (b) && (c)
int _3__COV_BIN_EXPR_CNT = 0; // guard: (!(a)) && (b)
int _4__COV_BIN_EXPR_CNT = 0; // guard: (!(a) && !(b)) && (d)
int _5__COV_BIN_EXPR_CNT = 0; // guard: (!(a) && !(b) && !(d))
int _6__COV_BIN_EXPR_CNT = 0; // guard: (e)
int _7__COV_BIN_EXPR_CNT = 0; // guard: (a & e)
`endif // NO_COVERAGE


// Reset-only path. No explicit `else`, so only one cond-path entry is emitted.
always @(posedge clock or posedge reset) begin
if (reset) begin
`ifndef NO_COVERAGE
if(_COV_EN) _0__COV_BIN_EXPR_CNT++;
`endif
 
        hit <= 8'h01;  end
end

// Decision tree for the non-reset cases. Each `if`/`else if`/`else` branch
// becomes its own cond-path coverage point.
always @(posedge clock) begin
if (a) begin
`ifndef NO_COVERAGE
if(_COV_EN) _1__COV_BIN_EXPR_CNT++;
`endif
 
        hit <= 8'h02;  end
else if (b) begin
`ifndef NO_COVERAGE
if(_COV_EN) _3__COV_BIN_EXPR_CNT++;
`endif
 
        hit <= 8'h03;
if (c) begin
`ifndef NO_COVERAGE
if(_COV_EN) _2__COV_BIN_EXPR_CNT++;
`endif
 
            hit <= 8'h04;  end

  end
else if (d) begin
`ifndef NO_COVERAGE
if(_COV_EN) _4__COV_BIN_EXPR_CNT++;
`endif
 
        hit <= 8'h05;  end
else begin
`ifndef NO_COVERAGE
if(_COV_EN) _5__COV_BIN_EXPR_CNT++;
`endif
 
        hit <= 8'h06;  end
if (e) begin
`ifndef NO_COVERAGE
if(_COV_EN) _6__COV_BIN_EXPR_CNT++;
`endif
 
        hit <= 8'h07;  end

    // For-loop containing a nested if to exercise loop-body recursion.
    for (int i = 0; i < 2; i++) begin
if (a & e) begin
`ifndef NO_COVERAGE
if(_COV_EN) _7__COV_BIN_EXPR_CNT++;
`endif
 
            hit <= 8'h08;  end
    end
end

`ifndef NO_COVERAGE

int _hit__COV_CNT = 0;
int _c__COV_CNT = 0;
int _b__COV_CNT = 0;
int _d__COV_CNT = 0;
int _a__COV_CNT = 0;
int _reset__COV_CNT = 0;
int _e__COV_CNT = 0;
int _clock__COV_CNT = 0;
bit[7:0] _hit__LAST;
bit _c__LAST;
bit _b__LAST;
bit _d__LAST;
bit _a__LAST;
bit _reset__LAST;
bit _e__LAST;
bit _clock__LAST;

always @(posedge clock) begin if(_COV_EN) begin if(hit ^ _hit__LAST) _hit__COV_CNT++; _hit__LAST <= hit; end end
always @(posedge clock) begin if(_COV_EN) begin if(c ^ _c__LAST) _c__COV_CNT++; _c__LAST <= c; end end
always @(posedge clock) begin if(_COV_EN) begin if(b ^ _b__LAST) _b__COV_CNT++; _b__LAST <= b; end end
always @(posedge clock) begin if(_COV_EN) begin if(d ^ _d__LAST) _d__COV_CNT++; _d__LAST <= d; end end
always @(posedge clock) begin if(_COV_EN) begin if(a ^ _a__LAST) _a__COV_CNT++; _a__LAST <= a; end end
always @(posedge clock) begin if(_COV_EN) begin if(reset ^ _reset__LAST) _reset__COV_CNT++; _reset__LAST <= reset; end end
always @(posedge clock) begin if(_COV_EN) begin if(e ^ _e__LAST) _e__COV_CNT++; _e__LAST <= e; end end
always @(posedge clock) begin if(_COV_EN) begin if(clock ^ _clock__LAST) _clock__COV_CNT++; _clock__LAST <= clock; end end



function void coverageCtrl(input bit enable);
    _COV_EN = enable;
endfunction

export "DPI-C" function coverageCtrl;


function void getCoverageCount(output int totalCount, output int totalBinExprCount);
    totalCount = int'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_5__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_6__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_7__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_hit__COV_CNT >= 1 ? 1 : 0) + (_c__COV_CNT >= 1 ? 1 : 0) + (_b__COV_CNT >= 1 ? 1 : 0) + (_d__COV_CNT >= 1 ? 1 : 0) + (_a__COV_CNT >= 1 ? 1 : 0) + (_reset__COV_CNT >= 1 ? 1 : 0) + (_e__COV_CNT >= 1 ? 1 : 0) + (_clock__COV_CNT >= 1 ? 1 : 0));
    totalBinExprCount = int'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_5__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_6__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_7__COV_BIN_EXPR_CNT >= 1 ? 1 : 0));
endfunction

export "DPI-C" function getCoverageCount;



// scopes:
//   cond_path_top
function void getCoverage(output real value);
    value = real'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_5__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_6__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_7__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_hit__COV_CNT >= 1 ? 1 : 0) + (_c__COV_CNT >= 1 ? 1 : 0) + (_b__COV_CNT >= 1 ? 1 : 0) + (_d__COV_CNT >= 1 ? 1 : 0) + (_a__COV_CNT >= 1 ? 1 : 0) + (_reset__COV_CNT >= 1 ? 1 : 0) + (_e__COV_CNT >= 1 ? 1 : 0) + (_clock__COV_CNT >= 1 ? 1 : 0)) / 16.0;
endfunction

export "DPI-C" function getCoverage;



// scopes:
//   cond_path_top
function void getCondCoverage(output real value);
    value = real'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_5__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_6__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_7__COV_BIN_EXPR_CNT >= 1 ? 1 : 0)) / 8.0;
endfunction

export "DPI-C" function getCondCoverage;



function void resetCoverage();
_0__COV_BIN_EXPR_CNT = 0; _1__COV_BIN_EXPR_CNT = 0; _2__COV_BIN_EXPR_CNT = 0; _3__COV_BIN_EXPR_CNT = 0; _4__COV_BIN_EXPR_CNT = 0; _5__COV_BIN_EXPR_CNT = 0; _6__COV_BIN_EXPR_CNT = 0; _7__COV_BIN_EXPR_CNT = 0; _hit__COV_CNT = 0; _c__COV_CNT = 0; _b__COV_CNT = 0; _d__COV_CNT = 0; _a__COV_CNT = 0; _reset__COV_CNT = 0; _e__COV_CNT = 0; _clock__COV_CNT = 0;
endfunction

export "DPI-C" function resetCoverage;



function void showCoverageCount();
$display("// ----------------------------------------");
$display("// Show Coverage Count[cond_path_top]");
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
$display("[cond_path_top]     11: %6d\t`Var`\t%s	.cov_exporter_cond_path/cond_path_top.sv:11", _clock__COV_CNT, _clock__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     12: %6d\t`Var`\t%s	.cov_exporter_cond_path/cond_path_top.sv:12", _reset__COV_CNT, _reset__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     13: %6d\t`Var`\t%s	.cov_exporter_cond_path/cond_path_top.sv:13", _a__COV_CNT, _a__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     14: %6d\t`Var`\t%s	.cov_exporter_cond_path/cond_path_top.sv:14", _b__COV_CNT, _b__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     15: %6d\t`Var`\t%s	.cov_exporter_cond_path/cond_path_top.sv:15", _c__COV_CNT, _c__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     16: %6d\t`Var`\t%s	.cov_exporter_cond_path/cond_path_top.sv:16", _d__COV_CNT, _d__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     17: %6d\t`Var`\t%s	.cov_exporter_cond_path/cond_path_top.sv:17", _e__COV_CNT, _e__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     18: %6d\t`Var`\t%s	.cov_exporter_cond_path/cond_path_top.sv:18", _hit__COV_CNT, _hit__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     23: %6d\t`CondPath`\t%s	.cov_exporter_cond_path/cond_path_top.sv:23\t(reset)", _0__COV_BIN_EXPR_CNT, _0__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     31: %6d\t`CondPath`\t%s	.cov_exporter_cond_path/cond_path_top.sv:31\t(a)", _1__COV_BIN_EXPR_CNT, _1__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     33: %6d\t`CondPath`\t%s	.cov_exporter_cond_path/cond_path_top.sv:33\t(!(a)) && (b)", _3__COV_BIN_EXPR_CNT, _3__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     35: %6d\t`CondPath`\t%s	.cov_exporter_cond_path/cond_path_top.sv:35\t(!(a)) && (b) && (c)", _2__COV_BIN_EXPR_CNT, _2__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     38: %6d\t`CondPath`\t%s	.cov_exporter_cond_path/cond_path_top.sv:38\t(!(a) && !(b)) && (d)", _4__COV_BIN_EXPR_CNT, _4__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     40: %6d\t`CondPath`\t%s	.cov_exporter_cond_path/cond_path_top.sv:40\t(!(a) && !(b) && !(d))", _5__COV_BIN_EXPR_CNT, _5__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     45: %6d\t`CondPath`\t%s	.cov_exporter_cond_path/cond_path_top.sv:45\t(e)", _6__COV_BIN_EXPR_CNT, _6__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[cond_path_top]     51: %6d\t`CondPath`\t%s	.cov_exporter_cond_path/cond_path_top.sv:51\t(a & e)", _7__COV_BIN_EXPR_CNT, _7__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("| Module | Line | Count | SignalType | Status | Source | Guard |");
$display("");
endfunction

export "DPI-C" function showCoverageCount;



// ==========================================================
//  cov_exporter Statistic
// ----------------------------------------------------------
//   net coverage points    : 0
//   var coverage points    : 8
//   cond-path points       : 8
//   duplicate nets removed : 0
//   unsupported cond stmts : 0
// ----------------------------------------------------------
//   literalEqualNet (excluded):
//       (none)
//   identifierEqualNet (excluded):
//       (none)
//   unsupportedCondStmts:
//       (none)
// ==========================================================

`endif // NO_COVERAGE

endmodule


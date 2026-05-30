module top(
    input wire clock,
    input wire reset,
    output reg [7:0] value,
    output reg [63:0] value64
);
`ifndef NO_COVERAGE
bit _COV_EN = 1;
int _0__COV_BIN_EXPR_CNT = 0; // guard: (reset)
int _1__COV_BIN_EXPR_CNT = 0; // guard: (!(reset)) && (counter[0] & counter[1])
int _2__COV_BIN_EXPR_CNT = 0; // guard: (!(reset)) && (!(counter[0] & counter[1])) && (counter[2] | counter[3])
int _3__COV_BIN_EXPR_CNT = 0; // guard: (!(reset)) && (enable) && (state == 4'd5)
int _4__COV_BIN_EXPR_CNT = 0; // guard: (!(reset)) && (enable) && (!(state == 4'd5))
int _5__COV_BIN_EXPR_CNT = 0; // guard: (!(reset)) && (enable)
int _6__COV_BIN_EXPR_CNT = 0; // guard: (!(reset))
`endif // NO_COVERAGE


reg [7:0] counter;
reg [7:0] accumulator;
wire valid;
wire [7:0] result;

// Test literal equal net (should be excluded)
wire literal_net = 1'b1;

// Test identifier equal net (should be excluded)
wire ident_net = valid;

// Test continuous assignment (not literal equal)
wire assign_net;
assign assign_net = counter[0] & counter[1];

// Test variable
reg [3:0] state;
reg enable;

// Test conditional statement with binary expression
always @(posedge clock) begin
if (reset) begin
`ifndef NO_COVERAGE
if(_COV_EN) _0__COV_BIN_EXPR_CNT++;
`endif
 
        counter <= 0;

        accumulator <= 0;

        state <= 0;

        enable <= 0;
  end
else begin
`ifndef NO_COVERAGE
if(_COV_EN) _6__COV_BIN_EXPR_CNT++;
`endif
 
        counter <= counter + 1;
if (counter[0] & counter[1]) begin
`ifndef NO_COVERAGE
if(_COV_EN) _1__COV_BIN_EXPR_CNT++;
`endif
 
            accumulator <= accumulator + 1;  end
else if (counter[2] | counter[3]) begin
`ifndef NO_COVERAGE
if(_COV_EN) _2__COV_BIN_EXPR_CNT++;
`endif
 
            accumulator <= accumulator - 1;  end

if (enable) begin
`ifndef NO_COVERAGE
if(_COV_EN) _5__COV_BIN_EXPR_CNT++;
`endif
 if (state == 4'd5) begin
`ifndef NO_COVERAGE
if(_COV_EN) _3__COV_BIN_EXPR_CNT++;
`endif
 
                state <= 0;  end
else begin
`ifndef NO_COVERAGE
if(_COV_EN) _4__COV_BIN_EXPR_CNT++;
`endif
 
                state <= state + 1;  end
  end


        
        enable <= ~enable;
  end
end

// Output assignment
assign valid = (counter > 8'd10);
assign result = accumulator + counter;

always @(posedge clock) begin
    value <= result;
    value64 <= {56'b0, counter};
end

`ifndef NO_COVERAGE


int _assign_net__COV_CNT = 0;
int _result__COV_CNT = 0;
int _valid__COV_CNT = 0;
bit _assign_net__LAST;
bit[7:0] _result__LAST;
bit _valid__LAST;

always @(posedge clock) begin
if(_COV_EN) begin
if(assign_net ^ _assign_net__LAST) _assign_net__COV_CNT++; _assign_net__LAST <= assign_net;
if(result ^ _result__LAST) _result__COV_CNT++; _result__LAST <= result;
if(valid ^ _valid__LAST) _valid__COV_CNT++; _valid__LAST <= valid;
end
end



int _enable__COV_CNT = 0;
int _accumulator__COV_CNT = 0;
int _counter__COV_CNT = 0;
int _value64__COV_CNT = 0;
int _state__COV_CNT = 0;
int _value__COV_CNT = 0;
bit _enable__LAST;
bit[7:0] _accumulator__LAST;
bit[7:0] _counter__LAST;
bit[63:0] _value64__LAST;
bit[3:0] _state__LAST;
bit[7:0] _value__LAST;

always @(posedge clock) begin
if(_COV_EN) begin
if(enable ^ _enable__LAST) _enable__COV_CNT++; _enable__LAST <= enable;
if(accumulator ^ _accumulator__LAST) _accumulator__COV_CNT++; _accumulator__LAST <= accumulator;
if(counter ^ _counter__LAST) _counter__COV_CNT++; _counter__LAST <= counter;
if(value64 ^ _value64__LAST) _value64__COV_CNT++; _value64__LAST <= value64;
if(state ^ _state__LAST) _state__COV_CNT++; _state__LAST <= state;
if(value ^ _value__LAST) _value__COV_CNT++; _value__LAST <= value;
end
end



function void coverageCtrl(input bit enable);
    _COV_EN = enable;
endfunction

export "DPI-C" function coverageCtrl;


function void getCoverageCount(output int totalCount, output int totalBinExprCount);
    totalCount = int'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_5__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_6__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_assign_net__COV_CNT >= 1 ? 1 : 0) + (_result__COV_CNT >= 1 ? 1 : 0) + (_valid__COV_CNT >= 1 ? 1 : 0) + (_enable__COV_CNT >= 1 ? 1 : 0) + (_accumulator__COV_CNT >= 1 ? 1 : 0) + (_counter__COV_CNT >= 1 ? 1 : 0) + (_value64__COV_CNT >= 1 ? 1 : 0) + (_state__COV_CNT >= 1 ? 1 : 0) + (_value__COV_CNT >= 1 ? 1 : 0));
    totalBinExprCount = int'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_5__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_6__COV_BIN_EXPR_CNT >= 1 ? 1 : 0));
endfunction

export "DPI-C" function getCoverageCount;



// scopes:
//   top
function void getCoverage(output real value);
    value = real'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_5__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_6__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_assign_net__COV_CNT >= 1 ? 1 : 0) + (_result__COV_CNT >= 1 ? 1 : 0) + (_valid__COV_CNT >= 1 ? 1 : 0) + (_enable__COV_CNT >= 1 ? 1 : 0) + (_accumulator__COV_CNT >= 1 ? 1 : 0) + (_counter__COV_CNT >= 1 ? 1 : 0) + (_value64__COV_CNT >= 1 ? 1 : 0) + (_state__COV_CNT >= 1 ? 1 : 0) + (_value__COV_CNT >= 1 ? 1 : 0)) / 16.0;
endfunction

export "DPI-C" function getCoverage;



// scopes:
//   top
function void getCondCoverage(output real value);
    value = real'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_5__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_6__COV_BIN_EXPR_CNT >= 1 ? 1 : 0)) / 7.0;
endfunction

export "DPI-C" function getCondCoverage;



function void resetCoverage();
_0__COV_BIN_EXPR_CNT = 0; _1__COV_BIN_EXPR_CNT = 0; _2__COV_BIN_EXPR_CNT = 0; _3__COV_BIN_EXPR_CNT = 0; _4__COV_BIN_EXPR_CNT = 0; _5__COV_BIN_EXPR_CNT = 0; _6__COV_BIN_EXPR_CNT = 0; _assign_net__COV_CNT = 0; _result__COV_CNT = 0; _valid__COV_CNT = 0; _enable__COV_CNT = 0; _accumulator__COV_CNT = 0; _counter__COV_CNT = 0; _value64__COV_CNT = 0; _state__COV_CNT = 0; _value__COV_CNT = 0;
endfunction

export "DPI-C" function resetCoverage;



function void showCoverageCount();
$display("// ----------------------------------------");
$display("// Show Coverage Count[top]");
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
$display("[top]      3: %6d\t`Var`\t%s	.cov_exporter_no_sep_always/top.sv:3", _value__COV_CNT, _value__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]      4: %6d\t`Var`\t%s	.cov_exporter_no_sep_always/top.sv:4", _value64__COV_CNT, _value64__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]      7: %6d\t`Var`\t%s	.cov_exporter_no_sep_always/top.sv:7", _counter__COV_CNT, _counter__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]      8: %6d\t`Var`\t%s	.cov_exporter_no_sep_always/top.sv:8", _accumulator__COV_CNT, _accumulator__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]      9: %6d\t`Net`\t%s	.cov_exporter_no_sep_always/top.sv:9", _valid__COV_CNT, _valid__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     10: %6d\t`Net`\t%s	.cov_exporter_no_sep_always/top.sv:10", _result__COV_CNT, _result__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     19: %6d\t`Net`\t%s	.cov_exporter_no_sep_always/top.sv:19", _assign_net__COV_CNT, _assign_net__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     23: %6d\t`Var`\t%s	.cov_exporter_no_sep_always/top.sv:23", _state__COV_CNT, _state__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     24: %6d\t`Var`\t%s	.cov_exporter_no_sep_always/top.sv:24", _enable__COV_CNT, _enable__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     28: %6d\t`CondPath`\t%s	.cov_exporter_no_sep_always/top.sv:28\t(reset)", _0__COV_BIN_EXPR_CNT, _0__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     33: %6d\t`CondPath`\t%s	.cov_exporter_no_sep_always/top.sv:33\t(!(reset))", _6__COV_BIN_EXPR_CNT, _6__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     36: %6d\t`CondPath`\t%s	.cov_exporter_no_sep_always/top.sv:36\t(!(reset)) && (counter[0] & counter[1])", _1__COV_BIN_EXPR_CNT, _1__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     38: %6d\t`CondPath`\t%s	.cov_exporter_no_sep_always/top.sv:38\t(!(reset)) && (!(counter[0] & counter[1])) && (counter[2] | counter[3])", _2__COV_BIN_EXPR_CNT, _2__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     42: %6d\t`CondPath`\t%s	.cov_exporter_no_sep_always/top.sv:42\t(!(reset)) && (enable)", _5__COV_BIN_EXPR_CNT, _5__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     43: %6d\t`CondPath`\t%s	.cov_exporter_no_sep_always/top.sv:43\t(!(reset)) && (enable) && (state == 4'd5)", _3__COV_BIN_EXPR_CNT, _3__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     45: %6d\t`CondPath`\t%s	.cov_exporter_no_sep_always/top.sv:45\t(!(reset)) && (enable) && (!(state == 4'd5))", _4__COV_BIN_EXPR_CNT, _4__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("| Module | Line | Count | SignalType | Status | Source | Guard |");
$display("");
endfunction

export "DPI-C" function showCoverageCount;



// ==========================================================
//  cov_exporter Statistic
// ----------------------------------------------------------
//   net coverage points    : 3
//   var coverage points    : 6
//   cond-path points       : 7
//   duplicate nets removed : 0
//   unsupported cond stmts : 0
// ----------------------------------------------------------
//   literalEqualNet (excluded):
//       literal_net
//   identifierEqualNet (excluded):
//       ident_net
//   unsupportedCondStmts:
//       (none)
// ==========================================================

`endif // NO_COVERAGE

endmodule


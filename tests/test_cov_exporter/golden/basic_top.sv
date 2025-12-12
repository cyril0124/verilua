module top(
    input wire clock,
    input wire reset,
    output reg [7:0] value,
    output reg [63:0] value64
);

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
        counter <= 0;
        accumulator <= 0;
        state <= 0;
        enable <= 0;
    end else begin
        counter <= counter + 1;
        
        if (counter[0] & counter[1]) begin
            accumulator <= accumulator + 1;
        end else if (counter[2] | counter[3]) begin
            accumulator <= accumulator - 1;
        end
        
        if (enable) begin
            if (state == 4'd5) begin
                state <= 0;
            end else begin
                state <= state + 1;
            end
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

bit _COV_EN = 1;

int _assign_net__COV_CNT = 0;
int _result__COV_CNT = 0;
int _valid__COV_CNT = 0;
bit _assign_net__LAST;
bit[7:0] _result__LAST;
bit _valid__LAST;

always @(posedge clock) begin if(_COV_EN) begin if(assign_net ^ _assign_net__LAST) _assign_net__COV_CNT++; _assign_net__LAST <= assign_net; end end
always @(posedge clock) begin if(_COV_EN) begin if(result ^ _result__LAST) _result__COV_CNT++; _result__LAST <= result; end end
always @(posedge clock) begin if(_COV_EN) begin if(valid ^ _valid__LAST) _valid__COV_CNT++; _valid__LAST <= valid; end end


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

always @(posedge clock) begin if(_COV_EN) begin if(enable ^ _enable__LAST) _enable__COV_CNT++; _enable__LAST <= enable; end end
always @(posedge clock) begin if(_COV_EN) begin if(accumulator ^ _accumulator__LAST) _accumulator__COV_CNT++; _accumulator__LAST <= accumulator; end end
always @(posedge clock) begin if(_COV_EN) begin if(counter ^ _counter__LAST) _counter__COV_CNT++; _counter__LAST <= counter; end end
always @(posedge clock) begin if(_COV_EN) begin if(value64 ^ _value64__LAST) _value64__COV_CNT++; _value64__LAST <= value64; end end
always @(posedge clock) begin if(_COV_EN) begin if(state ^ _state__LAST) _state__COV_CNT++; _state__LAST <= state; end end
always @(posedge clock) begin if(_COV_EN) begin if(value ^ _value__LAST) _value__COV_CNT++; _value__LAST <= value; end end


wire _0__COV_BIN_EXPR = state == 4'd5;
int _0__COV_BIN_EXPR_CNT = 0;
wire _1__COV_BIN_EXPR = counter[2] | counter[3];
int _1__COV_BIN_EXPR_CNT = 0;
wire _2__COV_BIN_EXPR = enable;
int _2__COV_BIN_EXPR_CNT = 0;
wire _3__COV_BIN_EXPR = counter[0] & counter[1];
int _3__COV_BIN_EXPR_CNT = 0;
wire _4__COV_BIN_EXPR = reset;
int _4__COV_BIN_EXPR_CNT = 0;
bit _0__COV_BIN_EXPR_LAST;
bit _1__COV_BIN_EXPR_LAST;
bit _2__COV_BIN_EXPR_LAST;
bit _3__COV_BIN_EXPR_LAST;
bit _4__COV_BIN_EXPR_LAST;

always @(posedge clock) begin if(_COV_EN) begin if(_0__COV_BIN_EXPR ^ _0__COV_BIN_EXPR_LAST) _0__COV_BIN_EXPR_CNT++; _0__COV_BIN_EXPR_LAST <= _0__COV_BIN_EXPR; end end
always @(posedge clock) begin if(_COV_EN) begin if(_1__COV_BIN_EXPR ^ _1__COV_BIN_EXPR_LAST) _1__COV_BIN_EXPR_CNT++; _1__COV_BIN_EXPR_LAST <= _1__COV_BIN_EXPR; end end
always @(posedge clock) begin if(_COV_EN) begin if(_2__COV_BIN_EXPR ^ _2__COV_BIN_EXPR_LAST) _2__COV_BIN_EXPR_CNT++; _2__COV_BIN_EXPR_LAST <= _2__COV_BIN_EXPR; end end
always @(posedge clock) begin if(_COV_EN) begin if(_3__COV_BIN_EXPR ^ _3__COV_BIN_EXPR_LAST) _3__COV_BIN_EXPR_CNT++; _3__COV_BIN_EXPR_LAST <= _3__COV_BIN_EXPR; end end
always @(posedge clock) begin if(_COV_EN) begin if(_4__COV_BIN_EXPR ^ _4__COV_BIN_EXPR_LAST) _4__COV_BIN_EXPR_CNT++; _4__COV_BIN_EXPR_LAST <= _4__COV_BIN_EXPR; end end



function void coverageCtrl(input bit enable);
    _COV_EN = enable;
endfunction

export "DPI-C" function coverageCtrl;


function void getCoverageCount(output int totalCount, output int totalBinExprCount);
    totalCount = int'((_assign_net__COV_CNT >= 1 ? 1 : 0) + (_result__COV_CNT >= 1 ? 1 : 0) + (_valid__COV_CNT >= 1 ? 1 : 0) + (_enable__COV_CNT >= 1 ? 1 : 0) + (_accumulator__COV_CNT >= 1 ? 1 : 0) + (_counter__COV_CNT >= 1 ? 1 : 0) + (_value64__COV_CNT >= 1 ? 1 : 0) + (_state__COV_CNT >= 1 ? 1 : 0) + (_value__COV_CNT >= 1 ? 1 : 0) + (_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0));
    totalBinExprCount = int'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0));
endfunction

export "DPI-C" function getCoverageCount;



/*
hierPaths(ScopeNames):
    top
*/
function void getCoverage(output real value);
    value = real'((_assign_net__COV_CNT >= 1 ? 1 : 0) + (_result__COV_CNT >= 1 ? 1 : 0) + (_valid__COV_CNT >= 1 ? 1 : 0) + (_enable__COV_CNT >= 1 ? 1 : 0) + (_accumulator__COV_CNT >= 1 ? 1 : 0) + (_counter__COV_CNT >= 1 ? 1 : 0) + (_value64__COV_CNT >= 1 ? 1 : 0) + (_state__COV_CNT >= 1 ? 1 : 0) + (_value__COV_CNT >= 1 ? 1 : 0) + (_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0)) / 14.0;
endfunction

export "DPI-C" function getCoverage;



/*
hierPaths(ScopeNames):
    top
*/
function void getCondCoverage(output real value);
    value = real'((_0__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_1__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_2__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_3__COV_BIN_EXPR_CNT >= 1 ? 1 : 0) + (_4__COV_BIN_EXPR_CNT >= 1 ? 1 : 0)) / 5.0;
endfunction

export "DPI-C" function getCondCoverage;



function void resetCoverage();
_assign_net__COV_CNT = 0; _result__COV_CNT = 0; _valid__COV_CNT = 0; _enable__COV_CNT = 0; _accumulator__COV_CNT = 0; _counter__COV_CNT = 0; _value64__COV_CNT = 0; _state__COV_CNT = 0; _value__COV_CNT = 0; _0__COV_BIN_EXPR_CNT = 0; _1__COV_BIN_EXPR_CNT = 0; _2__COV_BIN_EXPR_CNT = 0; _3__COV_BIN_EXPR_CNT = 0; _4__COV_BIN_EXPR_CNT = 0;
endfunction

export "DPI-C" function resetCoverage;



function void showCoverageCount();
$display("// ----------------------------------------");
$display("// Show Coverage Count[top]");
$display("// ----------------------------------------");
$display("| Module | Line | Count | SignalType | Status | Source |");
$display("[top]      4: %6d\t`Var`\t%s	.cov_exporter_basic/top.sv:4", _value__COV_CNT, _value__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]      5: %6d\t`Var`\t%s	.cov_exporter_basic/top.sv:5", _value64__COV_CNT, _value64__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]      8: %6d\t`Var`\t%s	.cov_exporter_basic/top.sv:8", _counter__COV_CNT, _counter__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]      9: %6d\t`Var`\t%s	.cov_exporter_basic/top.sv:9", _accumulator__COV_CNT, _accumulator__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     10: %6d\t`Net`\t%s	.cov_exporter_basic/top.sv:10", _valid__COV_CNT, _valid__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     11: %6d\t`Net`\t%s	.cov_exporter_basic/top.sv:11", _result__COV_CNT, _result__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     20: %6d\t`Net`\t%s	.cov_exporter_basic/top.sv:20", _assign_net__COV_CNT, _assign_net__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     24: %6d\t`Var`\t%s	.cov_exporter_basic/top.sv:24", _state__COV_CNT, _state__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     25: %6d\t`Var`\t%s	.cov_exporter_basic/top.sv:25", _enable__COV_CNT, _enable__COV_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     29: %6d\t`BinExpr`\t%s	.cov_exporter_basic/top.sv:29", _4__COV_BIN_EXPR_CNT, _4__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     37: %6d\t`BinExpr`\t%s	.cov_exporter_basic/top.sv:37", _3__COV_BIN_EXPR_CNT, _3__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     39: %6d\t`BinExpr`\t%s	.cov_exporter_basic/top.sv:39", _1__COV_BIN_EXPR_CNT, _1__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     43: %6d\t`BinExpr`\t%s	.cov_exporter_basic/top.sv:43", _2__COV_BIN_EXPR_CNT, _2__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("[top]     44: %6d\t`BinExpr`\t%s	.cov_exporter_basic/top.sv:44", _0__COV_BIN_EXPR_CNT, _0__COV_BIN_EXPR_CNT > 0 ? "\x1b[32mCOVERED\x1b[0m" : "\x1b[31mMISSED\x1b[0m");
$display("| Module | Line | Count | SignalType | Status | Source |");
$display("");
endfunction

export "DPI-C" function showCoverageCount;



// [cov_exporter] Statistic:
//     netCount: 3
//     varCount: 6
//     binExprCount: 5
//     duplicateNetCount: 0
/*
literalEqualNet:
    literal_net
*/
/*
identifierEqualNet:
    ident_net
*/

`endif // NO_COVERAGE

endmodule


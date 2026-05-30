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

// Reset-only path. No explicit `else`, so only one cond-path entry is emitted.
always @(posedge clock or posedge reset) begin
    if (reset) begin
        hit <= 8'h01;
    end
end

// Decision tree for the non-reset cases. Each `if`/`else if`/`else` branch
// becomes its own cond-path coverage point.
always @(posedge clock) begin
    if (a) begin
        hit <= 8'h02;
    end else if (b) begin
        hit <= 8'h03;
        if (c) begin
            hit <= 8'h04;
        end
    end else if (d) begin
        hit <= 8'h05;
    end else begin
        hit <= 8'h06;
    end

    // Independent if (no else) so it contributes a single coverage point.
    if (e) begin
        hit <= 8'h07;
    end

    // For-loop containing a nested if to exercise loop-body recursion.
    for (int i = 0; i < 2; i++) begin
        if (a & e) begin
            hit <= 8'h08;
        end
    end
end

endmodule

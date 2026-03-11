module LeafMod (
    input wire clock,
    input wire reset,
    output reg data
);
    always @(posedge clock) begin
        if (reset) begin
            data <= 1'b0;
        end else begin
            data <= ~data;
        end
    end
endmodule

module MidMod (
    input wire clock,
    input wire reset,
    output reg data
);
    wire leaf_data;

    LeafMod u_leaf (
        .clock(clock),
        .reset(reset),
        .data(leaf_data)
    );

    always @(posedge clock) begin
        if (reset) begin
            data <= 1'b0;
        end else begin
            data <= leaf_data;
        end
    end
endmodule

module top (
    input wire clock,
    input wire reset
);
    wire mid_a_data;
    wire mid_b_data;
    wire mid_out_data;
    wire leaf_top_data;

    MidMod u_mid_a (
        .clock(clock),
        .reset(reset),
        .data(mid_a_data)
    );

    MidMod u_mid_b (
        .clock(clock),
        .reset(reset),
        .data(mid_b_data)
    );

    MidMod u_mid_out (
        .clock(clock),
        .reset(reset),
        .data(mid_out_data)
    );

    LeafMod u_leaf_top (
        .clock(clock),
        .reset(reset),
        .data(leaf_top_data)
    );
endmodule

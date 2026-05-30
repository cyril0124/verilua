// cov_bench_top.sv — auto-generated stress-test RTL for cov_exporter benchmark.
// Characteristics: 280 signals, ~140 cond-path branches.
module cov_bench_top (
    input  logic        clock,
    input  logic        reset,
    input  logic [31:0] data_in,
    input  logic [7:0]  ctrl,
    input  logic        valid,
    output logic [31:0] result,
    output logic        done
);

    logic [7:0] r0;
    logic [7:0] r1;
    logic [7:0] r2;
    logic [7:0] r3;
    logic [7:0] r4;
    logic [7:0] r5;
    logic [7:0] r6;
    logic [7:0] r7;
    logic [7:0] r8;
    logic [7:0] r9;
    logic [7:0] r10;
    logic [7:0] r11;
    logic [7:0] r12;
    logic [7:0] r13;
    logic [7:0] r14;
    logic [7:0] r15;
    logic [7:0] r16;
    logic [7:0] r17;
    logic [7:0] r18;
    logic [7:0] r19;
    logic [7:0] r20;
    logic [7:0] r21;
    logic [7:0] r22;
    logic [7:0] r23;
    logic [7:0] r24;
    logic [7:0] r25;
    logic [7:0] r26;
    logic [7:0] r27;
    logic [7:0] r28;
    logic [7:0] r29;
    logic [7:0] r30;
    logic [7:0] r31;
    logic [7:0] r32;
    logic [7:0] r33;
    logic [7:0] r34;
    logic [7:0] r35;
    logic [7:0] r36;
    logic [7:0] r37;
    logic [7:0] r38;
    logic [7:0] r39;
    logic [7:0] r40;
    logic [7:0] r41;
    logic [7:0] r42;
    logic [7:0] r43;
    logic [7:0] r44;
    logic [7:0] r45;
    logic [7:0] r46;
    logic [7:0] r47;
    logic [7:0] r48;
    logic [7:0] r49;
    logic [7:0] r50;
    logic [7:0] r51;
    logic [7:0] r52;
    logic [7:0] r53;
    logic [7:0] r54;
    logic [7:0] r55;
    logic [7:0] r56;
    logic [7:0] r57;
    logic [7:0] r58;
    logic [7:0] r59;
    logic [7:0] r60;
    logic [7:0] r61;
    logic [7:0] r62;
    logic [7:0] r63;
    logic [7:0] r64;
    logic [7:0] r65;
    logic [7:0] r66;
    logic [7:0] r67;
    logic [7:0] r68;
    logic [7:0] r69;
    logic [7:0] r70;
    logic [7:0] r71;
    logic [7:0] r72;
    logic [7:0] r73;
    logic [7:0] r74;
    logic [7:0] r75;
    logic [7:0] r76;
    logic [7:0] r77;
    logic [7:0] r78;
    logic [7:0] r79;
    logic [7:0] r80;
    logic [7:0] r81;
    logic [7:0] r82;
    logic [7:0] r83;
    logic [7:0] r84;
    logic [7:0] r85;
    logic [7:0] r86;
    logic [7:0] r87;
    logic [7:0] r88;
    logic [7:0] r89;
    logic [7:0] r90;
    logic [7:0] r91;
    logic [7:0] r92;
    logic [7:0] r93;
    logic [7:0] r94;
    logic [7:0] r95;
    logic [7:0] r96;
    logic [7:0] r97;
    logic [7:0] r98;
    logic [7:0] r99;
    logic [7:0] r100;
    logic [7:0] r101;
    logic [7:0] r102;
    logic [7:0] r103;
    logic [7:0] r104;
    logic [7:0] r105;
    logic [7:0] r106;
    logic [7:0] r107;
    logic [7:0] r108;
    logic [7:0] r109;
    logic [7:0] r110;
    logic [7:0] r111;
    logic [7:0] r112;
    logic [7:0] r113;
    logic [7:0] r114;
    logic [7:0] r115;
    logic [7:0] r116;
    logic [7:0] r117;
    logic [7:0] r118;
    logic [7:0] r119;
    logic [7:0] r120;
    logic [7:0] r121;
    logic [7:0] r122;
    logic [7:0] r123;
    logic [7:0] r124;
    logic [7:0] r125;
    logic [7:0] r126;
    logic [7:0] r127;
    logic [7:0] r128;
    logic [7:0] r129;
    logic [7:0] r130;
    logic [7:0] r131;
    logic [7:0] r132;
    logic [7:0] r133;
    logic [7:0] r134;
    logic [7:0] r135;
    logic [7:0] r136;
    logic [7:0] r137;
    logic [7:0] r138;
    logic [7:0] r139;
    logic [7:0] r140;
    logic [7:0] r141;
    logic [7:0] r142;
    logic [7:0] r143;
    logic [7:0] r144;
    logic [7:0] r145;
    logic [7:0] r146;
    logic [7:0] r147;
    logic [7:0] r148;
    logic [7:0] r149;
    logic [7:0] r150;
    logic [7:0] r151;
    logic [7:0] r152;
    logic [7:0] r153;
    logic [7:0] r154;
    logic [7:0] r155;
    logic [7:0] r156;
    logic [7:0] r157;
    logic [7:0] r158;
    logic [7:0] r159;
    logic [7:0] r160;
    logic [7:0] r161;
    logic [7:0] r162;
    logic [7:0] r163;
    logic [7:0] r164;
    logic [7:0] r165;
    logic [7:0] r166;
    logic [7:0] r167;
    logic [7:0] r168;
    logic [7:0] r169;
    logic [7:0] r170;
    logic [7:0] r171;
    logic [7:0] r172;
    logic [7:0] r173;
    logic [7:0] r174;
    logic [7:0] r175;
    logic [7:0] r176;
    logic [7:0] r177;
    logic [7:0] r178;
    logic [7:0] r179;
    logic [7:0] r180;
    logic [7:0] r181;
    logic [7:0] r182;
    logic [7:0] r183;
    logic [7:0] r184;
    logic [7:0] r185;
    logic [7:0] r186;
    logic [7:0] r187;
    logic [7:0] r188;
    logic [7:0] r189;
    logic [7:0] r190;
    logic [7:0] r191;
    logic [7:0] r192;
    logic [7:0] r193;
    logic [7:0] r194;
    logic [7:0] r195;
    logic [7:0] r196;
    logic [7:0] r197;
    logic [7:0] r198;
    logic [7:0] r199;

    wire [7:0] w0 = r163 ^ r28;
    wire [7:0] w1 = r189 ^ r70;
    wire [7:0] w2 = r57 | r35;
    wire [7:0] w3 = r26 | r173;
    wire [7:0] w4 = r139 | r22;
    wire [7:0] w5 = r108 ^ r8;
    wire [7:0] w6 = r23 ^ r55;
    wire [7:0] w7 = r129 ^ r154;
    wire [7:0] w8 = r143 | r50;
    wire [7:0] w9 = r166 | r179;
    wire [7:0] w10 = r107 & r56;
    wire [7:0] w11 = r150 ^ r71;
    wire [7:0] w12 = r194 | r40;
    wire [7:0] w13 = r108 & r87;
    wire [7:0] w14 = r39 & r55;
    wire [7:0] w15 = r26 & r23;
    wire [7:0] w16 = r24 & r91;
    wire [7:0] w17 = r154 ^ r67;
    wire [7:0] w18 = r186 | r117;
    wire [7:0] w19 = r31 ^ r96;
    wire [7:0] w20 = r141 | r75;
    wire [7:0] w21 = r158 | r92;
    wire [7:0] w22 = r49 ^ r180;
    wire [7:0] w23 = r11 ^ r169;
    wire [7:0] w24 = r197 ^ r74;
    wire [7:0] w25 = r59 & r25;
    wire [7:0] w26 = r71 | r116;
    wire [7:0] w27 = r93 & r41;
    wire [7:0] w28 = r90 | r53;
    wire [7:0] w29 = r68 | r179;
    wire [7:0] w30 = r165 | r18;
    wire [7:0] w31 = r162 | r43;
    wire [7:0] w32 = r186 ^ r62;
    wire [7:0] w33 = r118 & r97;
    wire [7:0] w34 = r163 | r176;
    wire [7:0] w35 = r56 & r175;
    wire [7:0] w36 = r196 ^ r198;
    wire [7:0] w37 = r58 & r8;
    wire [7:0] w38 = r102 ^ r68;
    wire [7:0] w39 = r54 | r145;
    wire [7:0] w40 = r80 | r54;
    wire [7:0] w41 = r127 | r101;
    wire [7:0] w42 = r117 & r36;
    wire [7:0] w43 = r35 | r63;
    wire [7:0] w44 = r143 & r137;
    wire [7:0] w45 = r191 & r149;
    wire [7:0] w46 = r149 & r102;
    wire [7:0] w47 = r56 | r35;
    wire [7:0] w48 = r126 ^ r23;
    wire [7:0] w49 = r28 | r39;
    wire [7:0] w50 = r40 & r174;
    wire [7:0] w51 = r152 & r16;
    wire [7:0] w52 = r97 & r152;
    wire [7:0] w53 = r135 | r64;
    wire [7:0] w54 = r2 | r174;
    wire [7:0] w55 = r29 | r174;
    wire [7:0] w56 = r192 | r68;
    wire [7:0] w57 = r87 & r28;
    wire [7:0] w58 = r111 & r40;
    wire [7:0] w59 = r0 | r184;
    wire [7:0] w60 = r67 ^ r128;
    wire [7:0] w61 = r129 | r27;
    wire [7:0] w62 = r76 | r163;
    wire [7:0] w63 = r155 ^ r50;
    wire [7:0] w64 = r95 ^ r195;
    wire [7:0] w65 = r138 | r199;
    wire [7:0] w66 = r0 & r153;
    wire [7:0] w67 = r125 ^ r4;
    wire [7:0] w68 = r92 ^ r78;
    wire [7:0] w69 = r14 | r61;
    wire [7:0] w70 = r20 | r21;
    wire [7:0] w71 = r124 | r17;
    wire [7:0] w72 = r196 ^ r32;
    wire [7:0] w73 = r168 | r121;
    wire [7:0] w74 = r42 | r67;
    wire [7:0] w75 = r155 ^ r108;
    wire [7:0] w76 = r138 | r193;
    wire [7:0] w77 = r176 | r51;
    wire [7:0] w78 = r79 | r102;
    wire [7:0] w79 = r166 & r95;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r0 <= 8'h0;
            r1 <= 8'h0;
            r2 <= 8'h0;
            r3 <= 8'h0;
            r4 <= 8'h0;
            r5 <= 8'h0;
            r6 <= 8'h0;
            r7 <= 8'h0;
            r8 <= 8'h0;
            r9 <= 8'h0;
            r10 <= 8'h0;
            r11 <= 8'h0;
            r12 <= 8'h0;
            r13 <= 8'h0;
            r14 <= 8'h0;
            r15 <= 8'h0;
            r16 <= 8'h0;
            r17 <= 8'h0;
            r18 <= 8'h0;
            r19 <= 8'h0;
        end else begin
            if (ctrl[0]) begin
                r16 <= w57;
                if (valid) r7 <= data_in[7:0];
            end else if (r2[1]) begin
                r10 <= w2;
            end else if (r7[2]) begin
                r18 <= w28;
                if (valid) r1 <= data_in[7:0];
            end else if (r7[3]) begin
                r2 <= w4;
            end else if (r2[4]) begin
                r16 <= w30;
                if (valid) r15 <= data_in[7:0];
            end else if (r6[5]) begin
                r17 <= w16;
            end else if (r18[6]) begin
                r18 <= w60;
                if (valid) r15 <= data_in[7:0];
            end else if (r13[7]) begin
                r6 <= w12;
                if (valid) r13 <= data_in[7:0];
            end else if (r11[0]) begin
                r13 <= w52;
            end else if (r1[1]) begin
                r3 <= w7;
            end else if (r10[2]) begin
                r3 <= w31;
                if (valid) r17 <= data_in[7:0];
            end else if (r14[3]) begin
                r4 <= w54;
                if (valid) r14 <= data_in[7:0];
            end else if (r7[4]) begin
                r2 <= w56;
            end else begin
                r17 <= w12;
                if (valid) r17 <= data_in[7:0];
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r20 <= 8'h0;
            r21 <= 8'h0;
            r22 <= 8'h0;
            r23 <= 8'h0;
            r24 <= 8'h0;
            r25 <= 8'h0;
            r26 <= 8'h0;
            r27 <= 8'h0;
            r28 <= 8'h0;
            r29 <= 8'h0;
            r30 <= 8'h0;
            r31 <= 8'h0;
            r32 <= 8'h0;
            r33 <= 8'h0;
            r34 <= 8'h0;
            r35 <= 8'h0;
            r36 <= 8'h0;
            r37 <= 8'h0;
            r38 <= 8'h0;
            r39 <= 8'h0;
        end else begin
            if (ctrl[1]) begin
                r20 <= w11;
            end else if (r27[1]) begin
                r25 <= w52;
            end else if (r26[2]) begin
                r32 <= w7;
                if (valid) r20 <= data_in[7:0];
            end else if (r32[3]) begin
                r28 <= w58;
                if (valid) r37 <= data_in[7:0];
            end else if (r35[4]) begin
                r24 <= w24;
                if (valid) r21 <= data_in[7:0];
            end else if (r38[5]) begin
                r37 <= w7;
            end else if (r21[6]) begin
                r21 <= w74;
            end else if (r36[7]) begin
                r25 <= w7;
            end else if (r22[0]) begin
                r25 <= w8;
            end else if (r27[1]) begin
                r32 <= w15;
            end else if (r38[2]) begin
                r27 <= w74;
            end else if (r39[3]) begin
                r22 <= w53;
            end else if (r38[4]) begin
                r36 <= w40;
            end else begin
                r26 <= w40;
                if (valid) r32 <= data_in[7:0];
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r40 <= 8'h0;
            r41 <= 8'h0;
            r42 <= 8'h0;
            r43 <= 8'h0;
            r44 <= 8'h0;
            r45 <= 8'h0;
            r46 <= 8'h0;
            r47 <= 8'h0;
            r48 <= 8'h0;
            r49 <= 8'h0;
            r50 <= 8'h0;
            r51 <= 8'h0;
            r52 <= 8'h0;
            r53 <= 8'h0;
            r54 <= 8'h0;
            r55 <= 8'h0;
            r56 <= 8'h0;
            r57 <= 8'h0;
            r58 <= 8'h0;
            r59 <= 8'h0;
        end else begin
            if (ctrl[2]) begin
                r44 <= w38;
            end else if (r42[1]) begin
                r40 <= w58;
            end else if (r58[2]) begin
                r43 <= w9;
            end else if (r56[3]) begin
                r48 <= w16;
            end else if (r42[4]) begin
                r47 <= w47;
                if (valid) r54 <= data_in[7:0];
            end else if (r57[5]) begin
                r49 <= w78;
            end else if (r56[6]) begin
                r40 <= w70;
                if (valid) r43 <= data_in[7:0];
            end else if (r44[7]) begin
                r48 <= w14;
            end else if (r57[0]) begin
                r44 <= w34;
                if (valid) r46 <= data_in[7:0];
            end else if (r50[1]) begin
                r46 <= w33;
            end else if (r48[2]) begin
                r41 <= w11;
            end else if (r48[3]) begin
                r41 <= w0;
            end else if (r44[4]) begin
                r48 <= w20;
            end else begin
                r57 <= w54;
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r60 <= 8'h0;
            r61 <= 8'h0;
            r62 <= 8'h0;
            r63 <= 8'h0;
            r64 <= 8'h0;
            r65 <= 8'h0;
            r66 <= 8'h0;
            r67 <= 8'h0;
            r68 <= 8'h0;
            r69 <= 8'h0;
            r70 <= 8'h0;
            r71 <= 8'h0;
            r72 <= 8'h0;
            r73 <= 8'h0;
            r74 <= 8'h0;
            r75 <= 8'h0;
            r76 <= 8'h0;
            r77 <= 8'h0;
            r78 <= 8'h0;
            r79 <= 8'h0;
        end else begin
            if (ctrl[3]) begin
                r63 <= w9;
            end else if (r64[1]) begin
                r77 <= w4;
            end else if (r78[2]) begin
                r77 <= w18;
            end else if (r61[3]) begin
                r69 <= w46;
            end else if (r61[4]) begin
                r71 <= w26;
            end else if (r63[5]) begin
                r71 <= w71;
            end else if (r73[6]) begin
                r79 <= w19;
            end else if (r67[7]) begin
                r65 <= w22;
            end else if (r60[0]) begin
                r65 <= w42;
            end else if (r73[1]) begin
                r67 <= w34;
                if (valid) r63 <= data_in[7:0];
            end else if (r72[2]) begin
                r61 <= w60;
                if (valid) r74 <= data_in[7:0];
            end else if (r71[3]) begin
                r69 <= w29;
                if (valid) r66 <= data_in[7:0];
            end else if (r72[4]) begin
                r70 <= w35;
            end else begin
                r68 <= w44;
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r80 <= 8'h0;
            r81 <= 8'h0;
            r82 <= 8'h0;
            r83 <= 8'h0;
            r84 <= 8'h0;
            r85 <= 8'h0;
            r86 <= 8'h0;
            r87 <= 8'h0;
            r88 <= 8'h0;
            r89 <= 8'h0;
            r90 <= 8'h0;
            r91 <= 8'h0;
            r92 <= 8'h0;
            r93 <= 8'h0;
            r94 <= 8'h0;
            r95 <= 8'h0;
            r96 <= 8'h0;
            r97 <= 8'h0;
            r98 <= 8'h0;
            r99 <= 8'h0;
        end else begin
            if (ctrl[4]) begin
                r92 <= w68;
            end else if (r80[1]) begin
                r83 <= w33;
                if (valid) r88 <= data_in[7:0];
            end else if (r81[2]) begin
                r83 <= w76;
            end else if (r90[3]) begin
                r93 <= w77;
            end else if (r83[4]) begin
                r92 <= w73;
                if (valid) r81 <= data_in[7:0];
            end else if (r93[5]) begin
                r80 <= w66;
            end else if (r97[6]) begin
                r86 <= w46;
            end else if (r90[7]) begin
                r99 <= w40;
            end else if (r83[0]) begin
                r89 <= w64;
            end else if (r93[1]) begin
                r90 <= w51;
            end else if (r97[2]) begin
                r84 <= w24;
            end else if (r92[3]) begin
                r85 <= w78;
            end else if (r92[4]) begin
                r97 <= w0;
            end else begin
                r86 <= w55;
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r100 <= 8'h0;
            r101 <= 8'h0;
            r102 <= 8'h0;
            r103 <= 8'h0;
            r104 <= 8'h0;
            r105 <= 8'h0;
            r106 <= 8'h0;
            r107 <= 8'h0;
            r108 <= 8'h0;
            r109 <= 8'h0;
            r110 <= 8'h0;
            r111 <= 8'h0;
            r112 <= 8'h0;
            r113 <= 8'h0;
            r114 <= 8'h0;
            r115 <= 8'h0;
            r116 <= 8'h0;
            r117 <= 8'h0;
            r118 <= 8'h0;
            r119 <= 8'h0;
        end else begin
            if (ctrl[5]) begin
                r119 <= w41;
            end else if (r114[1]) begin
                r106 <= w65;
            end else if (r105[2]) begin
                r102 <= w36;
            end else if (r119[3]) begin
                r110 <= w11;
            end else if (r107[4]) begin
                r109 <= w28;
            end else if (r104[5]) begin
                r100 <= w5;
                if (valid) r115 <= data_in[7:0];
            end else if (r119[6]) begin
                r102 <= w58;
            end else if (r118[7]) begin
                r106 <= w49;
            end else if (r107[0]) begin
                r104 <= w0;
            end else if (r103[1]) begin
                r113 <= w28;
                if (valid) r116 <= data_in[7:0];
            end else if (r114[2]) begin
                r101 <= w71;
                if (valid) r103 <= data_in[7:0];
            end else if (r114[3]) begin
                r104 <= w59;
            end else if (r117[4]) begin
                r119 <= w40;
            end else begin
                r114 <= w78;
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r120 <= 8'h0;
            r121 <= 8'h0;
            r122 <= 8'h0;
            r123 <= 8'h0;
            r124 <= 8'h0;
            r125 <= 8'h0;
            r126 <= 8'h0;
            r127 <= 8'h0;
            r128 <= 8'h0;
            r129 <= 8'h0;
            r130 <= 8'h0;
            r131 <= 8'h0;
            r132 <= 8'h0;
            r133 <= 8'h0;
            r134 <= 8'h0;
            r135 <= 8'h0;
            r136 <= 8'h0;
            r137 <= 8'h0;
            r138 <= 8'h0;
            r139 <= 8'h0;
        end else begin
            if (ctrl[6]) begin
                r136 <= w54;
            end else if (r137[1]) begin
                r134 <= w20;
            end else if (r135[2]) begin
                r134 <= w33;
            end else if (r128[3]) begin
                r136 <= w62;
            end else if (r128[4]) begin
                r134 <= w9;
            end else if (r127[5]) begin
                r128 <= w42;
            end else if (r137[6]) begin
                r122 <= w17;
                if (valid) r132 <= data_in[7:0];
            end else if (r124[7]) begin
                r126 <= w8;
            end else if (r130[0]) begin
                r137 <= w59;
            end else if (r126[1]) begin
                r133 <= w49;
            end else if (r138[2]) begin
                r120 <= w73;
            end else if (r120[3]) begin
                r131 <= w38;
            end else if (r133[4]) begin
                r137 <= w69;
            end else begin
                r127 <= w62;
                if (valid) r133 <= data_in[7:0];
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r140 <= 8'h0;
            r141 <= 8'h0;
            r142 <= 8'h0;
            r143 <= 8'h0;
            r144 <= 8'h0;
            r145 <= 8'h0;
            r146 <= 8'h0;
            r147 <= 8'h0;
            r148 <= 8'h0;
            r149 <= 8'h0;
            r150 <= 8'h0;
            r151 <= 8'h0;
            r152 <= 8'h0;
            r153 <= 8'h0;
            r154 <= 8'h0;
            r155 <= 8'h0;
            r156 <= 8'h0;
            r157 <= 8'h0;
            r158 <= 8'h0;
            r159 <= 8'h0;
        end else begin
            if (ctrl[7]) begin
                r155 <= w3;
            end else if (r152[1]) begin
                r145 <= w59;
            end else if (r159[2]) begin
                r157 <= w3;
            end else if (r158[3]) begin
                r158 <= w3;
                if (valid) r153 <= data_in[7:0];
            end else if (r144[4]) begin
                r154 <= w23;
                if (valid) r152 <= data_in[7:0];
            end else if (r150[5]) begin
                r146 <= w58;
            end else if (r152[6]) begin
                r148 <= w53;
                if (valid) r142 <= data_in[7:0];
            end else if (r155[7]) begin
                r140 <= w69;
                if (valid) r151 <= data_in[7:0];
            end else if (r147[0]) begin
                r142 <= w5;
            end else if (r147[1]) begin
                r146 <= w2;
            end else if (r147[2]) begin
                r144 <= w60;
            end else if (r158[3]) begin
                r146 <= w59;
            end else if (r151[4]) begin
                r145 <= w77;
            end else begin
                r143 <= w20;
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r160 <= 8'h0;
            r161 <= 8'h0;
            r162 <= 8'h0;
            r163 <= 8'h0;
            r164 <= 8'h0;
            r165 <= 8'h0;
            r166 <= 8'h0;
            r167 <= 8'h0;
            r168 <= 8'h0;
            r169 <= 8'h0;
            r170 <= 8'h0;
            r171 <= 8'h0;
            r172 <= 8'h0;
            r173 <= 8'h0;
            r174 <= 8'h0;
            r175 <= 8'h0;
            r176 <= 8'h0;
            r177 <= 8'h0;
            r178 <= 8'h0;
            r179 <= 8'h0;
        end else begin
            if (ctrl[0]) begin
                r163 <= w74;
                if (valid) r169 <= data_in[7:0];
            end else if (r178[1]) begin
                r172 <= w50;
            end else if (r166[2]) begin
                r162 <= w75;
            end else if (r167[3]) begin
                r163 <= w38;
            end else if (r179[4]) begin
                r163 <= w72;
            end else if (r171[5]) begin
                r177 <= w54;
            end else if (r162[6]) begin
                r176 <= w43;
                if (valid) r173 <= data_in[7:0];
            end else if (r175[7]) begin
                r163 <= w55;
            end else if (r174[0]) begin
                r164 <= w55;
                if (valid) r176 <= data_in[7:0];
            end else if (r168[1]) begin
                r179 <= w68;
            end else if (r174[2]) begin
                r173 <= w75;
                if (valid) r167 <= data_in[7:0];
            end else if (r162[3]) begin
                r168 <= w57;
                if (valid) r174 <= data_in[7:0];
            end else if (r178[4]) begin
                r179 <= w48;
            end else begin
                r175 <= w41;
                if (valid) r166 <= data_in[7:0];
            end
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r180 <= 8'h0;
            r181 <= 8'h0;
            r182 <= 8'h0;
            r183 <= 8'h0;
            r184 <= 8'h0;
            r185 <= 8'h0;
            r186 <= 8'h0;
            r187 <= 8'h0;
            r188 <= 8'h0;
            r189 <= 8'h0;
            r190 <= 8'h0;
            r191 <= 8'h0;
            r192 <= 8'h0;
            r193 <= 8'h0;
            r194 <= 8'h0;
            r195 <= 8'h0;
            r196 <= 8'h0;
            r197 <= 8'h0;
            r198 <= 8'h0;
            r199 <= 8'h0;
        end else begin
            if (ctrl[1]) begin
                r191 <= w33;
            end else if (r199[1]) begin
                r188 <= w71;
                if (valid) r186 <= data_in[7:0];
            end else if (r182[2]) begin
                r187 <= w52;
            end else if (r187[3]) begin
                r195 <= w62;
            end else if (r180[4]) begin
                r182 <= w37;
                if (valid) r187 <= data_in[7:0];
            end else if (r189[5]) begin
                r198 <= w47;
            end else if (r196[6]) begin
                r191 <= w54;
            end else if (r197[7]) begin
                r190 <= w45;
            end else if (r188[0]) begin
                r189 <= w32;
                if (valid) r186 <= data_in[7:0];
            end else if (r190[1]) begin
                r183 <= w68;
            end else if (r185[2]) begin
                r186 <= w27;
            end else if (r188[3]) begin
                r198 <= w67;
            end else if (r183[4]) begin
                r186 <= w37;
                if (valid) r185 <= data_in[7:0];
            end else begin
                r189 <= w1;
            end
        end
    end

    assign result = {r0, r1, r2, r3};
    assign done   = r4[0];

endmodule
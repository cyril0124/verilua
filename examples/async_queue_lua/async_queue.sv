// Asynchronous Queue (Async FIFO) - Cross Clock Domain Example
// Write clock domain: wr_clk, Read clock domain: rd_clk
// Uses Gray code pointers for safe clock domain crossing

module async_queue #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 3  // Depth = 2^ADDR_WIDTH = 8
)(
    // Write clock domain
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output reg                   full,

    // Read clock domain
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    output reg                   empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // Memory
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Write pointer (binary and Gray code)
    reg [ADDR_WIDTH:0] wr_ptr_bin;
    wire [ADDR_WIDTH:0] wr_ptr_gray;

    // Read pointer (binary and Gray code)
    reg [ADDR_WIDTH:0] rd_ptr_bin;
    wire [ADDR_WIDTH:0] rd_ptr_gray;

    // Synchronized pointers
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // Binary to Gray code conversion
    assign wr_ptr_gray = wr_ptr_bin ^ (wr_ptr_bin >> 1);
    assign rd_ptr_gray = rd_ptr_bin ^ (rd_ptr_bin >> 1);

    // Write pointer logic
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin <= '0;
        end else if (wr_en && !full) begin
            wr_ptr_bin <= wr_ptr_bin + 1'b1;
        end
    end

    // Read pointer logic
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin <= '0;
        end else if (rd_en && !empty) begin
            rd_ptr_bin <= rd_ptr_bin + 1'b1;
        end
    end

    // Synchronize write pointer to read clock domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= '0;
            wr_ptr_gray_sync2 <= '0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // Synchronize read pointer to write clock domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= '0;
            rd_ptr_gray_sync2 <= '0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Full flag generation (in write clock domain)
    // Full when: wr_ptr_gray == {~rd_ptr_gray[MSB:MSB-1], rd_ptr_gray[MSB-2:0]}
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            full <= 1'b0;
        end else begin
            full <= (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
                                      rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
        end
    end

    // Empty flag generation (in read clock domain)
    // Empty when: rd_ptr_gray == wr_ptr_gray
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            empty <= 1'b1;
        end else begin
            empty <= (rd_ptr_gray == wr_ptr_gray_sync2);
        end
    end

    // Memory write
    always @(posedge wr_clk) begin
        if (wr_en && !full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    // Memory read
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_data <= '0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
        end
    end

endmodule

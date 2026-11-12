module AXI4Memory #(
    parameter integer SIZE_BYTES = 4096,
    parameter integer STALL_EVERY = 3
) (
    input  logic        clock,
    input  logic        reset_n,

    input  logic        awvalid,
    output logic        awready,
    input  logic [3:0]  awid,
    input  logic [31:0] awaddr,
    input  logic [7:0]  awlen,
    input  logic [2:0]  awsize,
    input  logic [1:0]  awburst,

    input  logic        wvalid,
    output logic        wready,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wlast,

    output logic        bvalid,
    input  logic        bready,
    output logic [3:0]  bid,
    output logic [1:0]  bresp,

    input  logic        arvalid,
    output logic        arready,
    input  logic [3:0]  arid,
    input  logic [31:0] araddr,
    input  logic [7:0]  arlen,
    input  logic [2:0]  arsize,
    input  logic [1:0]  arburst,

    output logic        rvalid,
    input  logic        rready,
    output logic [3:0]  rid,
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rlast
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [7:0] bytes [0:SIZE_BYTES - 1];

    logic write_active;
    logic [31:0] write_address;
    logic [3:0] write_id;
    integer unsigned write_beats;
    integer unsigned write_index;
    logic response_pending;

    logic read_active;
    logic [31:0] read_address;
    logic [3:0] read_id;
    integer unsigned read_beats;
    integer unsigned read_index;

    longint unsigned cycle;

    initial begin
        if (SIZE_BYTES <= 0 || SIZE_BYTES % 4 != 0) begin
            $fatal(1, "size_bytes must be a positive multiple of four");
        end

        if (STALL_EVERY != 0 && STALL_EVERY < 2) begin
            $fatal(1, "stall_every must be zero or an integer >= 2");
        end

        for (integer address = 0; address < SIZE_BYTES; address = address + 1) begin
            bytes[address] = 8'd0;
        end

        write_active = 1'b0;
        write_address = 32'd0;
        write_id = 4'd0;
        write_beats = 0;
        write_index = 0;
        response_pending = 1'b0;

        read_active = 1'b0;
        read_address = 32'd0;
        read_id = 4'd0;
        read_beats = 0;
        read_index = 0;
        cycle = 0;

        awready = 1'b0;
        wready = 1'b0;
        bvalid = 1'b0;
        bid = 4'd0;
        bresp = 2'd0;
        arready = 1'b0;
        rvalid = 1'b0;
        rid = 4'd0;
        rdata = 32'd0;
        rresp = 2'd0;
        rlast = 1'b0;
    end

    // Blocking state updates follow Lua order; outputs retain prior-cycle handshakes.
    always @(posedge clock) begin : update_memory
        logic [63:0] burst_end_address;
        logic [31:0] beat_address;
        logic [31:0] read_data;
        logic last_write_beat;
        logic publish_read;
        logic ready;

        if (!reset_n) begin
            // Reset aborts transactions without clearing memory or payload registers.
            write_active = 1'b0;
            read_active = 1'b0;
            response_pending = 1'b0;
            cycle = 0;

            awready <= 1'b0;
            wready <= 1'b0;
            bvalid <= 1'b0;
            arready <= 1'b0;
            rvalid <= 1'b0;
            rlast <= 1'b0;
        end else begin
            cycle = cycle + 1;

            if (response_pending && bready) begin
                response_pending = 1'b0;
                bvalid <= 1'b0;
            end

            if (awvalid && awready) begin
                burst_end_address = {32'd0, awaddr} + ({56'd0, awlen} + 64'd1) * 64'd4;

                if (awsize !== 3'd2) begin
                    $fatal(1, "AXI4Memory supports 4-byte beats only");
                end

                if (awburst !== 2'd1) begin
                    $fatal(1, "AXI4Memory supports INCR bursts only");
                end

                if (awaddr[1:0] !== 2'b00) begin
                    $fatal(1, "AXI4Memory requires word-aligned addresses");
                end

                if (burst_end_address > SIZE_BYTES) begin
                    $fatal(1, "AXI4Memory address out of range");
                end

                if ({32'd0, awaddr} / 64'd4096 != (burst_end_address - 64'd1) / 64'd4096) begin
                    $fatal(1, "AXI4 burst crosses a 4 KiB boundary");
                end

                write_active = 1'b1;
                write_address = awaddr;
                write_id = awid;
                write_beats = {24'd0, awlen} + 32'd1;
                write_index = 0;
            end

            if (wvalid && wready) begin
                if (!write_active) begin
                    $fatal(1, "AXI4 W beat has no active write burst");
                end

                last_write_beat = write_index == write_beats - 1;

                if (wlast !== last_write_beat) begin
                    $fatal(1, "AXI4 WLAST does not match AWLEN");
                end

                beat_address = write_address + write_index * 4;

                for (integer lane = 0; lane < 4; lane = lane + 1) begin
                    if (wstrb[lane]) begin
                        bytes[beat_address + lane] = wdata[lane * 8 +: 8];
                    end
                end

                write_index = write_index + 1;

                if (last_write_beat) begin
                    bid <= write_id;
                    bresp <= 2'd0;
                    bvalid <= 1'b1;
                    response_pending = 1'b1;
                    write_active = 1'b0;
                end
            end

            publish_read = 1'b0;

            if (read_active && rvalid && rready) begin
                read_index = read_index + 1;

                if (read_index == read_beats) begin
                    read_active = 1'b0;
                    rvalid <= 1'b0;
                    rlast <= 1'b0;
                end else begin
                    publish_read = 1'b1;
                end
            end

            if (arvalid && arready) begin
                burst_end_address = {32'd0, araddr} + ({56'd0, arlen} + 64'd1) * 64'd4;

                if (arsize !== 3'd2) begin
                    $fatal(1, "AXI4Memory supports 4-byte beats only");
                end

                if (arburst !== 2'd1) begin
                    $fatal(1, "AXI4Memory supports INCR bursts only");
                end

                if (araddr[1:0] !== 2'b00) begin
                    $fatal(1, "AXI4Memory requires word-aligned addresses");
                end

                if (burst_end_address > SIZE_BYTES) begin
                    $fatal(1, "AXI4Memory address out of range");
                end

                if ({32'd0, araddr} / 64'd4096 != (burst_end_address - 64'd1) / 64'd4096) begin
                    $fatal(1, "AXI4 burst crosses a 4 KiB boundary");
                end

                read_active = 1'b1;
                read_address = araddr;
                read_id = arid;
                read_beats = {24'd0, arlen} + 32'd1;
                read_index = 0;
                publish_read = 1'b1;
            end

            // Only published beats observe memory, including writes from this edge.
            if (publish_read) begin
                beat_address = read_address + read_index * 4;
                read_data = 32'd0;

                for (integer lane = 0; lane < 4; lane = lane + 1) begin
                    read_data[lane * 8 +: 8] = bytes[beat_address + lane];
                end

                rid <= read_id;
                rdata <= read_data;
                rresp <= 2'd0;
                rlast <= read_index == read_beats - 1;
                rvalid <= 1'b1;
            end

            if (STALL_EVERY == 0) begin
                ready = 1'b1;
            end else begin
                ready = cycle % STALL_EVERY != 0;
            end

            awready <= ready && !write_active && !response_pending;
            wready <= ready && write_active;
            arready <= ready && !read_active;
        end
    end
endmodule

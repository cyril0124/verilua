-- Async Queue Example using NativeClock
-- Demonstrates cross-clock domain FIFO (Async FIFO) with NativeClock
-- Write clock and read clock are driven independently using NativeClock
--
-- Note: Verilator uses 'clock'/'reset' for wr_clk/wr_rst_n

local NativeClock = require "verilua.utils.NativeClock"

local function test_async_queue()
    print("=== Async Queue Test (NativeClock) ===")
    print(string.format("  Simulator: %s", cfg.simulator))

    -- Get the correct signal handles based on simulator
    -- Verilator: 'clock' is wired to 'wr_clk', 'reset' is wired to 'wr_rst_n'
    local wr_clk_signal, wr_rst_signal
    if cfg.simulator == "verilator" then
        wr_clk_signal = dut.clock
        wr_rst_signal = dut.reset
    else
        wr_clk_signal = dut.wr_clk
        wr_rst_signal = dut.wr_rst_n
    end

    -- Create NativeClocks for both clock domains
    local wr_clk_native = NativeClock(wr_clk_signal:chdl())
    local rd_clk_native = NativeClock(dut.rd_clk:chdl())

    print("  Created NativeClocks for write and read clock domains")

    -- Start clocks with different periods
    -- Write clock: 10ns period (100MHz)
    -- Read clock: 16ns period (62.5MHz) - different frequency to test CDC
    wr_clk_native:start(10, "ns", { start_high = false })
    rd_clk_native:start(16, "ns", { start_high = false })

    print("  Started clocks: wr_clk=10ns (100MHz), rd_clk=16ns (62.5MHz)")

    -- Assert reset (active low)
    wr_rst_signal:set(0)
    dut.rd_rst_n:set(0)
    dut.wr_en:set(0)
    dut.wr_data:set(0)
    dut.rd_en:set(0)

    -- Wait for reset
    for _ = 1, 10 do
        wr_clk_signal:posedge()
    end

    -- Release reset
    wr_rst_signal:set(1)
    dut.rd_rst_n:set(1)

    -- Wait for reset to propagate through synchronizers
    for _ = 1, 10 do
        wr_clk_signal:posedge()
    end

    print("  Reset released")

    -- Verify initial state
    local empty_val = dut.empty:get()
    local full_val = dut.full:get()
    print(string.format("  Initial state: empty=%d, full=%d", empty_val, full_val))
    assert(empty_val == 1, "Queue should be empty after reset")
    assert(full_val == 0, "Queue should not be full after reset")

    -- Write test data to the queue
    print("  Writing data to queue...")
    local test_data = { 0x11, 0x22, 0x33, 0x44, 0x55 }

    for i, data in ipairs(test_data) do
        dut.wr_en:set(1)
        dut.wr_data:set(data)
        wr_clk_signal:posedge()
        print(string.format("    Wrote[%d]: 0x%02X", i, data))
    end
    dut.wr_en:set(0)

    -- Wait for empty flag to update (CDC latency)
    for _ = 1, 5 do
        dut.rd_clk:posedge()
    end

    -- Verify queue is not empty
    empty_val = dut.empty:get()
    print(string.format("  After write: empty=%d", empty_val))
    assert(empty_val == 0, "Queue should not be empty after writes")

    -- Read data from the queue
    print("  Reading data from queue...")
    local read_data = {}

    for i = 1, #test_data do
        -- Wait for data to be available
        while dut.empty:get() == 1 do
            dut.rd_clk:posedge()
        end

        dut.rd_en:set(1)
        dut.rd_clk:posedge()
        dut.rd_en:set(0)
        dut.rd_clk:posedge() -- One more cycle to latch data

        local data = dut.rd_data:get()
        read_data[i] = data
        print(string.format("    Read[%d]: 0x%02X", i, data))
    end

    -- Verify read data matches written data
    print("  Verifying data integrity...")
    for i, expected in ipairs(test_data) do
        local actual = read_data[i]
        assert(actual == expected, string.format(
            "Data mismatch at index %d: expected 0x%02X, got 0x%02X",
            i, expected, actual))
    end

    -- Wait for empty flag to update
    for _ = 1, 5 do
        dut.rd_clk:posedge()
    end

    -- Verify queue is empty again
    empty_val = dut.empty:get()
    print(string.format("  Final state: empty=%d", empty_val))
    assert(empty_val == 1, "Queue should be empty after reading all data")

    print("  PASS: Async queue test (NativeClock) completed successfully")
end

-- Main test execution
fork {
    function()
        test_async_queue()

        print("")
        print("=== All tests passed! ===")

        sim.finish()
    end
}

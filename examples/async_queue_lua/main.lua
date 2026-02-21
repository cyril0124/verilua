-- Async Queue Example using Lua Clock Driver
-- Demonstrates cross-clock domain FIFO (Async FIFO) with Lua clock drivers
-- Write clock and read clock are driven independently using Lua coroutines
--
-- Note: Verilator uses 'clock'/'reset' for wr_clk/wr_rst_n

local function test_async_queue()
    print("=== Async Queue Test (Lua Clock) ===")
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

    local wr_clk = wr_clk_signal:chdl()
    local rd_clk = dut.rd_clk:chdl()

    -- Flag to stop clock drivers
    local stop_clocks = false

    -- Write clock driver: 10ns period (5ns high, 5ns low)
    fork {
        function()
            while not stop_clocks do
                wr_clk:set(1)
                await_time(5, "ns")
                wr_clk:set(0)
                await_time(5, "ns")
            end
        end
    }

    -- Read clock driver: 16ns period (8ns high, 8ns low)
    fork {
        function()
            while not stop_clocks do
                rd_clk:set(1)
                await_time(8, "ns")
                rd_clk:set(0)
                await_time(8, "ns")
            end
        end
    }

    print("  Started Lua clock drivers: wr_clk=10ns (100MHz), rd_clk=16ns (62.5MHz)")

    -- Assert reset (active low)
    wr_rst_signal:set(0)
    dut.rd_rst_n:set(0)
    dut.wr_en:set(0)
    dut.wr_data:set(0)
    dut.rd_en:set(0)

    -- Wait for reset
    await_time(100, "ns")

    -- Release reset
    wr_rst_signal:set(1)
    dut.rd_rst_n:set(1)

    -- Wait for reset to propagate through synchronizers
    await_time(100, "ns")

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
        await_time(10, "ns") -- One write clock cycle
        print(string.format("    Wrote[%d]: 0x%02X", i, data))
    end
    dut.wr_en:set(0)

    -- Wait for empty flag to update (CDC latency)
    await_time(80, "ns")

    -- Verify queue is not empty
    empty_val = dut.empty:get()
    print(string.format("  After write: empty=%d", empty_val))
    assert(empty_val == 0, "Queue should not be empty after writes")

    -- Read data from the queue
    print("  Reading data from queue...")
    local read_data = {}

    for i = 1, #test_data do
        -- Wait for data to be available
        local timeout_count = 0
        while dut.empty:get() == 1 do
            await_time(16, "ns")
            timeout_count = timeout_count + 1
            if timeout_count > 100 then
                error("Timeout waiting for data")
            end
        end

        dut.rd_en:set(1)
        await_time(16, "ns") -- One read clock cycle
        dut.rd_en:set(0)
        await_time(16, "ns") -- One more cycle to latch data

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
    await_time(80, "ns")

    -- Verify queue is empty again
    empty_val = dut.empty:get()
    print(string.format("  Final state: empty=%d", empty_val))
    assert(empty_val == 1, "Queue should be empty after reading all data")

    -- Stop clock drivers
    stop_clocks = true
    await_time(50, "ns")

    print("  PASS: Async queue test (Lua Clock) completed successfully")
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

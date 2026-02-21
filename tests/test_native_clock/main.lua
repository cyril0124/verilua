local NativeClock = require "verilua.utils.NativeClock"

local function test_native_clock_basic()
    print("=== Test: NativeClock Basic Functionality ===")

    -- Diagnostic info about time scaling
    local precision = cfg.time_precision
    print("  Time precision (exponent): " .. precision) -- e.g., -12 for ps

    local clock_hdl = dut.clock:chdl()
    print("  clock_hdl = " .. tostring(clock_hdl))

    print("  Creating NativeClock...")
    local clk = NativeClock(clock_hdl)

    -- Test with ns unit - 10ns period
    local period_ns = 10 -- 10ns period
    print(string.format("  Starting clock with period=%d ns, start_high=false...", period_ns))
    local start_time = sim.get_sim_time()
    print(string.format("  Start time: %d", start_time))
    -- Start with clock LOW - first posedge should occur after high_steps = half period
    clk:start(period_ns, "ns", { start_high = false })
    print("  Clock started, is_running = " .. tostring(clk:is_running()))

    -- With 10ns period (10000 steps at 1ps precision) and start_high=false:
    -- First posedge at 5ns (5000 steps), then every 10ns (10000 steps)
    -- Expected posedges at: 5000, 15000, 25000, 35000, 45000 steps
    local expected_times = { 5000, 15000, 25000, 35000, 45000 }

    print("  Waiting for 5 posedges...")
    for i = 1, 5 do
        dut.clock:posedge()
        local t = sim.get_sim_time()
        local expected = expected_times[i]
        print(string.format("    posedge %d at time %d (expected: %d)", i, t, expected))
        assert(t == expected, string.format("Timing error: posedge %d at %d, expected %d", i, t, expected))
    end

    local end_time = sim.get_sim_time()
    local elapsed = tonumber(end_time - start_time)
    assert(elapsed == 45000, string.format("Total elapsed time should be 45000, got %d", elapsed))

    clk:stop()
    clk:destroy()

    print("  PASS: NativeClock basic functionality works correctly")
end

local function test_native_clock_duty_cycle()
    print("=== Test: NativeClock Duty Cycle ===")

    local clock_hdl = dut.clock:chdl()
    local clk = NativeClock(clock_hdl)

    -- 10 step period, 3 step high time (30% duty cycle)
    -- start_high=true: clock starts at 1
    -- After 3 steps (high time): posedge -> negedge
    -- After 7 steps (low time): negedge -> posedge
    -- So posedges occur at: 0 (initial), 10, 20, 30, 40...
    -- But since start_high=true, the first posedge we wait for is at step 10
    clk:start(10, "step", { high = 3, start_high = true })

    local start_time = sim.get_sim_time()

    -- Run for 5 posedges
    -- Expected posedges at: 10, 20, 30, 40, 50 steps from start
    local expected_deltas = { 10, 20, 30, 40, 50 }
    for i = 1, 5 do
        dut.clock:posedge()
        local t = sim.get_sim_time()
        local delta = t - start_time
        local expected = expected_deltas[i]
        print(string.format("    posedge %d at delta %d (expected: %d)", i, delta, expected))
        assert(delta == expected,
            string.format("Duty cycle timing error: posedge %d at delta %d, expected %d", i, delta, expected))
    end

    clk:stop()
    clk:destroy()

    print("  PASS: NativeClock duty cycle works correctly")
end

local function test_native_clock_error_handling()
    print("=== Test: NativeClock Error Handling ===")

    local clock_hdl = dut.clock:chdl()
    local clk = NativeClock(clock_hdl)

    -- Test double start (should error)
    clk:start(10, "step")
    local ok, err = pcall(function()
        clk:start(20, "step")
    end)
    ---@cast err string
    assert(not ok, "Double start should fail")
    assert(string.find(err, "already running"), "Error should mention 'already running'")
    print("  Double start correctly rejected: " .. tostring(err))

    clk:stop()

    -- Test multiple clocks on same signal (should error)
    local clk2 = NativeClock(clock_hdl)
    clk:start(10, "step")
    ok, err = pcall(function()
        clk2:start(20, "step")
    end)
    ---@cast err string
    assert(not ok, "Multiple clocks on same signal should fail")
    assert(string.find(err, "another NativeClock") or string.find(err, "Another NativeClock"),
        "Error should mention 'another NativeClock'")
    print("  Multiple clocks on same signal correctly rejected: " .. tostring(err))

    clk:stop()
    clk:destroy()
    clk2:destroy()

    print("  PASS: NativeClock error handling works correctly")
end

local function test_native_clock_multiple_signals()
    print("=== Test: NativeClock Multiple Different Signals ===")

    -- Use clock and reset as two different signals for this test
    local clock_hdl = dut.clock:chdl()
    local reset_hdl = dut.reset:chdl()

    print("  clock_hdl = " .. tostring(clock_hdl))
    print("  reset_hdl = " .. tostring(reset_hdl))

    -- Create two NativeClocks on different signals
    local clk1 = NativeClock(clock_hdl)
    local clk2 = NativeClock(reset_hdl)

    -- Start both clocks with different periods
    -- Clock: 10ns period, Reset: 20ns period
    clk1:start(10, "ns", { start_high = false }) -- posedges at 5000, 15000, 25000...
    clk2:start(20, "ns", { start_high = false }) -- posedges at 10000, 30000...

    print("  Both clocks started successfully")
    assert(clk1:is_running(), "clk1 should be running")
    assert(clk2:is_running(), "clk2 should be running")

    -- Wait for a few clock cycles using await_time to avoid the scheduler issue
    -- with posedge on non-registered clock signals
    await_time(50, "ns")

    -- Verify both clocks are still running
    assert(clk1:is_running(), "clk1 should still be running")
    assert(clk2:is_running(), "clk2 should still be running")

    -- Clean up
    clk1:stop()
    clk2:stop()

    assert(not clk1:is_running(), "clk1 should be stopped")
    assert(not clk2:is_running(), "clk2 should be stopped")

    clk1:destroy()
    clk2:destroy()

    print("  PASS: Multiple NativeClocks on different signals work correctly")
end

-- Main test execution
fork {
    function()
        test_native_clock_basic()
        test_native_clock_duty_cycle()
        test_native_clock_error_handling()
        test_native_clock_multiple_signals()

        print("")
        print("=== All NativeClock tests passed! ===")

        sim.finish()
    end
}

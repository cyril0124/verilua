-- cov_overhead.lua — cov_exporter runtime-overhead driver.
--
-- The SAME script drives two builds of cov_bench_top:
--   * baseline      : no cov_exporter instrumentation
--   * instrumented  : cov_exporter applied
-- Only the simulation loop is timed (os.clock is the verilua high-resolution
-- CLOCK_MONOTONIC), excluding Verilua startup, so the printed elapsed reflects
-- the real per-cycle cost difference. The test harness parses the
-- `[cov_overhead] elapsed_ms:` line from each run and asserts the overhead.

if os.getenv("JIT_V") == "off" then jit.off() end

local CYCLES  = tonumber(os.getenv("COV_BENCH_CYCLES")) or 1000000

local clock   = dut.clock:chdl()
local data_in = dut.data_in:chdl()
local ctrl    = dut.ctrl:chdl()
local valid   = dut.valid:chdl()

fork {
    function()
        dut.reset = 1
        clock:posedge(5)
        dut.reset = 0

        -- Time only the steady-state stimulus loop.
        local t0 = os.clock()
        for _ = 1, CYCLES do
            clock:negedge()
            data_in:set(math.random(0, 0xFFFFFFFF))
            ctrl:set(math.random(0, 0xFF))
            valid:set(math.random(0, 1))
        end
        local elapsed_ms = (os.clock() - t0) * 1000.0

        print(string.format("[cov_overhead] elapsed_ms: %.3f", elapsed_ms))
        sim.finish()
    end
}

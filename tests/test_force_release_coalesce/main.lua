-- Same-timeslot set_release() + set_force() must not let the signal rise.
--
-- Pattern under test (continuous backpressure):
--   ready:set_force(0)
--   for each cycle:
--     clock:posedge()
--     ready:set_release()
--     ready:set_force(0)
--
-- Expected (when both ops are deferred and coalesce via the pending-put queue):
--   - ready never rises while bp_armed (ready_glitch == 0)
--   - DUT accepts no beats (count == 0)
--
-- If set_release/set_force take effect immediately without coalescing,
-- ready glitches 0->1->0 inside the timeslot and both checks fail.
--
-- Simulator notes:
--   - verilator: force/release unsupported
--   - iverilog/xcelium: set_release has long been immediate (historically wired
--     to vpiml_release_imm_value), so release+force never coalesced there;
--     this check is only meaningful where both ops share the deferred queue

local clock = dut.clock:chdl()
local valid = dut.valid:chdl()
local ready = dut.ready:chdl()
local count = dut.count:chdl()
local bp_armed = dut.bp_armed:chdl()
local ready_glitch = dut.ready_glitch:chdl()

local CYCLES = 20

fork {
    function()
        if cfg.simulator == "verilator" then
            print("[test_force_release_coalesce] skip: force/release not supported on verilator")
            sim.finish()
            return
        end

        if cfg.simulator == "iverilog" or cfg.simulator == "xcelium" then
            print(string.format(
                "[test_force_release_coalesce] skip: set_release is immediate on %s "
                .. "(no deferred coalesce with set_force)",
                cfg.simulator
            ))
            sim.finish()
            return
        end

        valid:set(0)
        bp_armed:set(0)

        dut.reset:set(1)
        clock:posedge(5)
        dut.reset:set(0)
        clock:posedge()

        bp_armed:set(1)
        ready:set_force(0)

        for _ = 1, CYCLES do
            valid:set(1)
            clock:posedge()
            ready:set_release()
            ready:set_force(0)
        end

        valid:set(0)
        ready:set_release()
        bp_armed:set(0)
        clock:posedge(2)

        local glitch = ready_glitch:get()
        local dut_count = count:get()
        print(string.format(
            "[test_force_release_coalesce] ready_glitch=%d dut_count=%d",
            glitch,
            dut_count
        ))

        assert(
            glitch == 0,
            string.format(
                "ready rose under continuous force (ready_glitch=%d); "
                .. "same-timeslot set_release()+set_force() must coalesce",
                glitch
            )
        )

        assert(
            dut_count == 0,
            string.format(
                "DUT accepted %d beats while ready was continuously forced low",
                dut_count
            )
        )

        sim.finish()
    end,
}

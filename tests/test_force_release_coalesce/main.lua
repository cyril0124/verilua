-- Same-timeslot release() + force() must not let the signal rise.
--
-- Pattern under test (continuous backpressure):
--   ready:force(0)
--   for each cycle:
--     clock:posedge()
--     ready:release()
--     ready:force(0)
--
-- Expected (when both ops are deferred and coalesce via the pending-put queue):
--   - ready never rises while bp_armed (ready_glitch == 0)
--   - DUT accepts no beats (count == 0)
--
-- If release/force take effect immediately without coalescing,
-- ready glitches 0->1->0 inside the timeslot and both checks fail.
--
-- Simulator notes:
--   - verilator: needs forceable on forced signals (via verilua.verilator_config)
--   - iverilog/xcelium: release has long been immediate (historically wired
--     to vpiml_release_imm_value), so release+force never coalesced there;
--     this check is only meaningful where both ops share the deferred queue

local clock = dut.clock:chdl()
local valid = dut.valid:chdl()
-- Force the DUT-side continuous-assign net. On Verilator, tb_top.ready and
-- u_top.ready are separate forceable nets; only forcing u_top.ready overrides
-- `assign ready = 1'b1` and blocks the handshake.
local ready = dut.u_top.ready:chdl()
local count = dut.count:chdl()
local bp_armed = dut.bp_armed:chdl()
local ready_glitch = dut.ready_glitch:chdl()

local CYCLES = 20

fork {
    function()
        if cfg.simulator == "iverilog" or cfg.simulator == "xcelium"
            or os.getenv("VL_XMK_USE_INERTIAL_PUT") == "1"
        then
            print(string.format(
                "[test_force_release_coalesce] skip: release/force are immediate on %s%s "
                .. "(no deferred coalesce)",
                cfg.simulator,
                os.getenv("VL_XMK_USE_INERTIAL_PUT") == "1" and "+inertial_put" or ""
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
        ready:force(0)

        for _ = 1, CYCLES do
            valid:set(1)
            clock:posedge()
            ready:release()
            ready:force(0)
        end

        valid:set(0)
        ready:release()
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
                .. "same-timeslot release()+force() must coalesce",
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

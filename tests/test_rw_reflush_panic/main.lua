-- Reproduction: cbReadWriteSynch re-flush cross-queue dedup panic (VCS/iverilog).
--
-- A value-change callback fired during the pending-put flush wakes a coroutine
-- that set()s a signal still queued for flush. The dedup search in
-- try_put_value (complex_handle.rs) used to scan only one queue and panic.
-- Expected: last-write-wins, no crash.

local trig   = dut.trig:chdl()
local shared = dut.shared:chdl()

fork {
    -- Woken by trig's value-change during the flush; writes `shared`, which is
    -- still queued for flush.
    observer = function()
        trig:posedge()
        shared:set(0x55)
    end,

    driver = function()
        dut.reset:set(1)
        trig:set(0)
        shared:set(0)
        dut.clock:posedge()
        dut.reset:set(0)
        dut.clock:posedge()

        -- queue = [trig, shared]; flushing trig (0->1) wakes `observer`, which
        -- set()s shared while shared is still pending.
        trig:set(1)
        shared:set(0xAA)

        await_rw()

        -- No panic means the re-entry was handled. Last-write-wins uniformly:
        -- the observer's re-flushed 0x55 is committed and settled before the
        -- deferred await_rw() wakeup resumes this coroutine, on every
        -- simulator (and inertial_put builds behave the same).
        local v = shared:get()
        assert(v == 0x55, string.format("shared should be 0x55, got 0x%X", v))

        print("[PASS] re-flush cross-queue dedup handled, no panic")
        sim.finish()
    end,
}

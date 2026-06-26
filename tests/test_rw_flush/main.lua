-- Repro: set() must be flushed before await_rw() resumes the coroutine.
-- On VCS the user await_rw() callback runs before the pending-put flush,
-- so the read returns the stale value.

local d = dut.d:chdl()

fork {
    function()
        dut.reset:set(1)
        d:set(0)
        dut.clock:posedge()
        dut.reset:set(0)
        dut.clock:posedge()

        local t = sim.get_sim_time()
        d:set(0xDEAD)
        assert(d:is(0), "before flush d should still read old value")

        await_rw()

        assert(t == sim.get_sim_time(), "await_rw() must not advance time")
        assert(d:is(0xDEAD), string.format("d must be flushed to 0xDEAD, got 0x%X", d:get()))

        d:set(0x1234)
        await_rw()
        assert(d:is(0x1234), string.format("d must be flushed to 0x1234, got 0x%X", d:get()))

        print("[PASS] set() + await_rw() flush ordering correct")
        sim.finish()
    end
}

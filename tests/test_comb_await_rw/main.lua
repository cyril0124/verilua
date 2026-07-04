-- Test: set() + single await_rw() observes combinational propagation
-- Contract: after one await_rw(), pending set() values are committed AND
-- combinational fanout has settled, at unchanged sim time.
--
-- DUT: ready = valid && (counter < 4)

local clock   = dut.clock:chdl()
local reset   = dut.reset:chdl()
local valid   = dut.valid:chdl()
local ready   = dut.ready:chdl()
local counter = dut.counter:chdl()

fork {
    function()
        ---------------------------------------------------------------
        -- Test 1: set() + await_rw() reads propagated comb output
        ---------------------------------------------------------------
        reset:set(1)
        clock:posedge()
        reset:set(0)

        valid:set(0)
        clock:posedge()

        assert(counter:is(0), "counter should be 0 after reset")

        local t = sim.get_sim_time()
        valid:set(1)
        assert(valid:is(0)) -- set() is posted, not yet visible

        await_rw()
        assert(t == sim.get_sim_time(), "await_rw() must not advance time")

        assert(valid:is(1), "valid should be 1 after await_rw()")
        assert(ready:is(1), "ready should be 1 after single await_rw() (comb propagated)")
        print(string.format("[Test 1] %d valid=%d ready=%d", t, valid:get(), ready:get()))

        ---------------------------------------------------------------
        -- Test 2: handshake loop, counter saturates at 4, ready goes 0
        ---------------------------------------------------------------
        reset:set(1)
        clock:posedge()
        reset:set(0)

        valid:set(0)
        clock:posedge()

        assert(counter:is(0), "counter should be 0 after second reset")

        -- VCS caveat: all cbReadWriteSynch occurrences within one time slot
        -- execute before nonblocking assignment updates mature (legal per
        -- IEEE 1800-2023 38.36.2, the region placement is undefined), so
        -- same-slot reads of FF outputs (counter, and ready which depends on
        -- it) observe the pre-edge value: the loop needs one extra clock edge
        -- compared with verilator/iverilog.
        local is_vcs = cfg.simulator == "vcs"
        local max_iters = is_vcs and 6 or 5
        local expected_completed = is_vcs and 5 or 4

        local completed = 0
        for i = 1, max_iters do
            local t1 = sim.get_sim_time()
            valid:set(1)

            await_rw()
            assert(t1 == sim.get_sim_time())

            assert(valid:is(1), "valid must be flushed")
            print(string.format("[Test 2] %d iter %d: ready=%d counter=%d", t1, i, ready:get(), counter:get()))

            if i <= expected_completed then
                assert(ready:is(1), string.format("iter %d: ready should be 1 (counter < 4)", i))
            else
                assert(ready:is(0), string.format("iter %d: ready should be 0 (counter >= 4)", i))
            end

            if ready:is(0) then
                valid:set(0)
                clock:posedge()
                break
            end

            completed = completed + 1
            clock:posedge()
        end

        assert(
            completed == expected_completed,
            string.format("expected %d handshakes, got %d", expected_completed, completed)
        )
        assert(counter:is(4), string.format("expected counter=4, got %d", counter:get()))

        -- Verify: with counter=4, ready stays 0 even with valid=1
        local t2 = sim.get_sim_time()
        valid:set(1)
        assert(valid:is(0)) -- not yet flushed

        await_rw()
        assert(t2 == sim.get_sim_time())

        assert(valid:is(1))
        assert(ready:is(0), "ready should be 0 when counter>=4")
        print(string.format("[Test 2] counter=4, valid=1, ready=%d (expected 0)", ready:get()))

        sim.finish()
    end
}

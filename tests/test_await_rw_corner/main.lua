-- Test: await_rw() corner cases
--
-- DUT: sum = a + b, product = a * b, chain = 4-level comb chain of a/b
-- Covers corners not exercised by test_comb_await_rw:
--   1. bare await_rw() (fast path: no deferral, no time advance)
--   2. set_imm() + await_rw() (bypasses the posted-write queue)
--   3. last-write-wins within one flush batch
--   4. concurrent waiters in the same ReadWrite pass
--   5. multi-level combinational chain settles after a single await_rw()
--   6. same-value set() (flush commits a no-change put)
--   7. chained set() + await_rw() rounds within one timestep

local clock   = dut.clock:chdl()
local reset   = dut.reset:chdl()
local a       = dut.a:chdl()
local b       = dut.b:chdl()
local sum     = dut.sum:chdl()
local product = dut.product:chdl()
local chain   = dut.chain:chdl()
local valid   = dut.valid:chdl()
local counter = dut.counter:chdl()

fork {
    function()
        -- Init
        reset:set(1)
        a:set(0)
        b:set(0)
        valid:set(0)
        clock:posedge(2)
        reset:set(0)
        clock:posedge()
        assert(counter:is(0))

        ---------------------------------------------------------------
        -- Test 1: bare await_rw() without pending writes.
        -- Fast path: no flush happened since registration, so the wakeup
        -- must not be deferred and time must not advance. An implementation
        -- that defers unconditionally would slip to the next timestep here.
        ---------------------------------------------------------------
        a:set(3)
        b:set(5)
        clock:posedge() -- flush via posedge

        local t1 = sim.get_sim_time()
        await_rw() -- no pending writes
        assert(t1 == sim.get_sim_time(), "await_rw() without pending writes should not advance time")
        assert(sum:is(8), string.format("sum should be 8, got %d", sum:get()))
        print("[Test 1] PASS: bare await_rw() without pending writes")

        ---------------------------------------------------------------
        -- Test 2: set_imm() + await_rw().
        -- set_imm() bypasses the posted-write queue (no flush, no deferral),
        -- yet the values and their comb fanout must be visible after a
        -- single await_rw() at unchanged time.
        ---------------------------------------------------------------
        clock:posedge() -- boundary

        local t2 = sim.get_sim_time()
        a:set_imm(7)
        b:set_imm(3)
        assert(a:is(7))
        assert(b:is(3))
        await_rw()
        assert(t2 == sim.get_sim_time(), "set_imm + await_rw() should not advance time")
        assert(a:is(7))
        assert(b:is(3))
        assert(sum:is(10), string.format("sum should be 10, got %d", sum:get()))
        assert(product:is(21), string.format("product should be 21, got %d", product:get()))
        print("[Test 2] PASS: set_imm() + await_rw()")

        ---------------------------------------------------------------
        -- Test 3: last write wins within one flush batch.
        -- The same signal is posted multiple times before the flush; only
        -- the final value may be committed and observed by the comb fanout.
        ---------------------------------------------------------------
        clock:posedge() -- boundary

        a:set(100)
        a:set(200)
        a:set(50) -- last one wins
        b:set(1)
        await_rw()
        assert(a:is(50), string.format("a should be 50, got %d", a:get()))
        assert(b:is(1))
        assert(sum:is(51), string.format("sum should be 51, got %d", sum:get()))
        print("[Test 3] PASS: last write wins within one flush batch")

        ---------------------------------------------------------------
        -- Test 4: concurrent forks both set() + await_rw().
        -- Both waiters sit in the same ReadWrite pass: both must be deferred
        -- past the flush, both must observe the merged writes, and neither
        -- wakeup may slip past its own timestep.
        ---------------------------------------------------------------
        a:set(0)
        b:set(0)
        clock:posedge() -- clear

        local results = {}
        local t = sim.get_sim_time() -- reference: both forks must wake in this same timestep

        fork {
            function()
                a:set(11)
                await_rw()
                assert(sim.get_sim_time() == t, "fork1: await_rw() must not advance time")
                results.fork1_a = a:get()
                results.fork1_sum = sum:get()
            end
        }

        fork {
            function()
                b:set(22)
                await_rw()
                assert(sim.get_sim_time() == t, "fork2: await_rw() must not advance time")
                results.fork2_b = b:get()
                results.fork2_sum = sum:get()
            end
        }

        clock:posedge()

        assert(results.fork1_a == 11, string.format("fork1 a=%s", tostring(results.fork1_a)))
        assert(results.fork2_b == 22, string.format("fork2 b=%s", tostring(results.fork2_b)))
        assert(results.fork1_sum == 33, string.format("fork1 sum=%s (expected 33)", tostring(results.fork1_sum)))
        assert(results.fork2_sum == 33, string.format("fork2 sum=%s (expected 33)", tostring(results.fork2_sum)))
        print("[Test 4] PASS: concurrent forks set() + await_rw()")

        ---------------------------------------------------------------
        -- Test 5: multi-level comb chain settles after single await_rw().
        -- Guards against "single-level comb happens to be readable" luck:
        -- propagation through several levels must also have converged.
        ---------------------------------------------------------------
        clock:posedge() -- boundary

        local t5 = sim.get_sim_time()
        a:set(0x12)
        b:set(0x34)
        await_rw()
        assert(t5 == sim.get_sim_time(), "await_rw() must not advance time")
        -- chain = (((a ^ b) + 1) & 0x7F) ^ 0x55 = (((0x12 ^ 0x34) + 1) & 0x7F) ^ 0x55 = 0x72
        assert(chain:is(0x72), string.format("chain should be 0x72, got 0x%X", chain:get()))
        print("[Test 5] PASS: multi-level comb chain after single await_rw()")

        ---------------------------------------------------------------
        -- Test 6: same-value set() + await_rw().
        -- The flush commits a no-change put: no value-change events follow,
        -- yet the deferred wakeup must still fire in the same timestep.
        ---------------------------------------------------------------
        a:set(5)
        b:set(5)
        clock:posedge() -- establish a=5, b=5

        local t6 = sim.get_sim_time()
        a:set(5) -- same value as current
        await_rw()
        assert(t6 == sim.get_sim_time(), "same-value set() + await_rw() must not advance time")
        assert(a:is(5))
        assert(sum:is(10), string.format("sum should be 10, got %d", sum:get()))
        print("[Test 6] PASS: same-value set() + await_rw()")

        ---------------------------------------------------------------
        -- Test 7: chained set() + await_rw() rounds within one timestep.
        -- A task woken by await_rw() posts again and awaits again: writes
        -- made inside the ReadWrite window must be flushed and settled
        -- without the timestep advancing (verilator: relies on the
        -- verilator_has_pending_put_values() loop condition).
        ---------------------------------------------------------------
        clock:posedge() -- boundary

        local t7 = sim.get_sim_time()
        a:set(1)
        b:set(2)
        await_rw()
        assert(t7 == sim.get_sim_time(), "round 1: time must not advance")
        assert(sum:is(3), string.format("round 1: sum should be 3, got %d", sum:get()))

        a:set(10) -- second round within the same timestep
        await_rw()
        assert(t7 == sim.get_sim_time(), "round 2: chained set+await_rw must stay in the same timestep")
        assert(sum:is(12), string.format("round 2: sum should be 12, got %d", sum:get()))

        a:set(20) -- third round
        await_rw()
        assert(t7 == sim.get_sim_time(), "round 3: chained set+await_rw must stay in the same timestep")
        assert(sum:is(22), string.format("round 3: sum should be 22, got %d", sum:get()))
        print("[Test 7] PASS: chained set() + await_rw() within one timestep")

        sim.finish()
    end
}

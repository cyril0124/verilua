local clock   = dut.clock:chdl()
local reset   = dut.reset:chdl()
local valid   = dut.valid:chdl()
local ready   = dut.ready:chdl()
local counter = dut.counter:chdl()

fork {
    function()
        print("[Section 1] set() + await_rw()")
        reset:set(1)
        valid:set(0)
        clock:posedge(2)
        reset:set(0)
        clock:posedge()
        counter:expect(0)

        valid:set(1)
        assert(valid:is(0))

        await_rw()
        assert(valid:is(1))
        assert(ready:is(1))
        print(string.format("  valid=%d ready=%d", valid:get(), ready:get()))

        print("[Section 2] poll with a single await_rd()")
        for i = 1, 2 do
            valid:set(1)
            while true do
                await_rd()
                if ready:get() == 1 then break end
                clock:posedge()
            end
            clock:posedge()
            print(string.format("  transfer %d requested", i))
        end

        print("[Section 3] drive to saturation, retract with await_rw()")
        while true do
            valid:set(1)
            await_rw()
            if ready:get() == 0 then
                valid:set(0) -- writing requires await_rw(), not await_rd()
                break
            end
            clock:posedge()
        end
        clock:posedge()
        counter:expect(4)

        print("TEST PASS!")
        sim.finish()
    end
}

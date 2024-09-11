
verilua "appendTasks" {
    function ()
        sim.dump_wave() -- dump wave file
        
        dut.clock:negedge()
            dut.reset = 1 -- or `dut.reset:set(1)`
        dut.clock:negedge()
            dut.reset = 0
        dut.clock:negedge()

        dut.clock:negedge(10, function ()
            print("current cycle:", dut.cycles:get())
        end)

        -- we recommend using the `chdl()` method to get the `CallableHDL` of the signal which provides higher performance
        local clock = dut.clock:chdl()

        dut.value:dump() -- dump the value of the signal to the console
        dut.value:expect(0)

        clock:negedge()
            dut.inc:set(1)
        clock:negedge()
            dut.inc:set(0)
        
        dut.value:expect(1)
        dut.value:dump()

        clock:negedge()
            dut.inc:set(1)
        clock:negedge()
            dut.inc:set(0)
        
        if dut.value:is(2) then
            print("dump_str() => ", dut.value:dump_str())
            print("get() => ", dut.value:get())
        end

        clock:negedge()
            dut.inc:set(1)
        
        clock:posedge(10)
            dut.inc:set(0)

        dut.value:expect(11)

        sim.finish() -- finish the simulation
    end
}

-- start task will be called when the simulation starts
verilua "startTask" {
    function ()
        print("Simulation started!")
    end
}

-- finish task will be called when the simulation finishes
verilua "finishTask" {
    function ()
        print("Simulation finished!")
    end
}
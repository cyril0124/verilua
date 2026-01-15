local clock = dut.clock:chdl()

fork {
    function()
        if cfg.simulator == "verilator" then
            sim.dump_wave("test.fst")
        else
            sim.dump_wave()
        end

        clock:posedge(10)

        dut.reset:set(1)
        clock:posedge()
        dut.reset:set(0)
        clock:posedge()

        clock:posedge(100)

        print("cycles:", dut.cycles:get())
        sim.finish()
    end
}

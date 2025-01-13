fork {
    function ()
        if cfg.simulator == "iverilog" then
            sim.dump_wave()
            dut.reset = 1
            dut.clock:posedge(5)
            dut.reset = 0
        end

        if cfg.simulator == "wave_vpi" then
            dut.clock:posedge()
            dut.value:expect_hex_str("10000000")
        else
            dut.clock:posedge(10, function ()
                dut.value:dump()
            end)
        end
        
        sim.finish()
    end   
}
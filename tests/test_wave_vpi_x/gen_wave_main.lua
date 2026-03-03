fork {
    function()
        sim.dump_wave()

        -- First few cycles: data_a/data_b/data_wide are X (uninitialized)
        dut.clock:posedge(3)

        -- Apply reset to assign known values
        dut.reset:set(1)
        dut.clock:posedge()
        dut.reset:set(0)
        dut.clock:posedge()

        -- Run a few more cycles with known values
        dut.clock:posedge(5)

        sim.finish()
    end
}

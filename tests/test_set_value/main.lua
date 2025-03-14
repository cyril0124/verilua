
fork {
    function ()
        local clock = dut.clock:chdl()

        dut.inc:set(1)

        dut.reset:set(1)
        clock:posedge(10)
        dut.reset:set(0)
        clock:posedge()

        dut.count:expect(0)
        dut.inc:set(2) -- set value, available at the next clock cycle
        
        clock:posedge()
        dut.count:expect(1)

        clock:posedge()
        dut.count:expect(3)
        dut.inc:set_imm(1) -- set immediate value, available at the current clock cycle

        clock:posedge()
        dut.count:expect(4)

        sim.finish()
    end
}
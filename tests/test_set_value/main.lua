
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
        dut.inc:expect(1)

        clock:posedge()
        dut.count:expect(1)

        clock:posedge()
        dut.count:expect(3)
        dut.inc:set_imm(1) -- set immediate value, available at the current clock cycle

        clock:posedge()
        dut.count:expect(4)

        dut.inc:set(3)

        clock:negedge()
        dut.count:expect(5)

        clock:negedge()
        dut.count:expect(8)

        clock:posedge(10)
        clock:negedge()
        dut.inc:set_imm(12)
        dut.inc:expect(12)

        clock:negedge()
        dut.inc:expect(12)

        sim.finish()
    end
}
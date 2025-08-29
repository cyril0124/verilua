fork {
    function()
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

        do
            clock:posedge()
            dut.inc:set(22)
            await_rd()
            dut.inc:expect(22)

            clock:posedge()
            dut.inc:set(23)
            await_rd()
            dut.inc:expect(23)

            local at_end_of_eval = false
            clock:posedge()
            await_rw()
            dut.inc:set(12)
            await_rd()
            -- If we are in the end of the ReadWrite evaluation loop, the value will be updated.
            at_end_of_eval = dut.inc:is(12)
            if not at_end_of_eval then
                print("NOT at end of eval", cfg.simulator)
                clock:posedge()
                dut.inc:expect(12)
                await_rw()
                dut.inc:set_imm(13)
                await_rd()
                dut.inc:expect(13)
            else
                print("at end of eval", cfg.simulator)
                clock:posedge()
                dut.inc:set(13)
                await_rd()
                dut.inc:expect(13)
            end

            clock:posedge()
            dut.inc:set(14)
            await_rw()
            at_end_of_eval = dut.inc:is(14)
            if not at_end_of_eval then
                print("NOT at end of eval", cfg.simulator)
                await_rd()
                dut.inc:expect(14)
            end
        end

        do
            clock:posedge()
            dut.inc:set(15)
            clock:posedge()
            dut.inc:set(16)
            await_nsim()
            dut.inc:expect(16)
            await_nsim()
            dut.inc:expect(16)

            await_nsim()
            dut.inc:set(17)
            await_nsim()
            dut.inc:expect(17)
        end

        -- TODO: multiple set
        -- TODO: multiple set_imm
        -- TODO: multiple set_force
        -- TODO: set_force overlap set/set_imm

        sim.finish()
    end
}

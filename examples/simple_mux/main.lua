fork {
    main_task = function()
        sim.bypass_initial()

        dut.a:set(0)
        dut.b:set(1)

        dut.sel:set(1)
        await_time(1)
        dut.out:expect(1)

        dut.sel:set(0)
        await_time(1)
        dut.out:expect(0)

        print("TEST PASS!")

        sim.finish()
    end
}

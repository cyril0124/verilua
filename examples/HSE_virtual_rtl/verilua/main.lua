

fork {
    drv_empty_module = function ()
        local u_empty = dut.u_empty
        local clock = u_empty.clock:chdl()
        local valid = u_empty.valid:chdl()
        local value = u_empty.value:chdl()
        local accumulator = u_empty.accumulator:chdl()

        fork {
            function ()
                while true do
                    print("accumulator: " .. accumulator:get())
                    clock:posedge()
                end
            end
        }

        clock:posedge()
            valid:set(1)
            value:set(0xF)

        clock:posedge(4)
            valid:set(0)

        clock:posedge(2)
            valid:set(1)
            value:set(0x2)
    end,

    check_task = function ()
        local expect_values = { 0, 15, 30, 45, 60, 60, 60, 62, 64, 66, 68, 70, 72, 74, 76, 78, 80 }
        while dut.cycles:is(0) do dut.clock:posedge() end
        while true do
            local cycles = dut.cycles:get()
            dut.accumulator:expect(expect_values[cycles])

            if cycles >= #expect_values then
                break
            end
            dut.clock:posedge()
        end
    end,

    main_task = function ()
        dut.clock:posedge(20, function ()
            print("[main_task] cycles: " .. dut.cycles:get()  .. " accumulator: " .. dut.accumulator:get())
        end)

        sim.finish();
    end
}
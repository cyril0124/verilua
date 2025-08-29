

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
        local expect_values = { 
            0,  -- 1
            15, -- 2
            30, -- 3
            45, -- 4
            60, -- 5
            60, -- 6
            60, -- 7
            62, -- 8
            64, -- 9
            66, -- 10
            68, -- 11
            70, -- 12
            72, -- 13
            74, -- 14
            76, -- 15
            78, -- 16
            80, -- 17
            82, -- 18
         }
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

fork {
    drv_empty2_module = function ()
        local u_empty2 = dut.u_empty2
        local clock = dut.clock:chdl()
        local value64 = u_empty2.value64:chdl()
        local value128 = u_empty2.value128:chdl()

        clock:posedge(2)
            value64:set_hex_str("effffffff3ffffff")
            value128:set_hex_str("effffffff4ffffffeffffffff3ffffff")
        clock:posedge()
            value64:expect_hex_str("effffffff3ffffff")
            value128:expect_hex_str("effffffff4ffffffeffffffff3ffffff")
        clock:posedge()
            value64:set(0x11fffffff3f2ffffULL, true)
        clock:posedge()
            value64:expect_hex_str("11fffffff3f2ffff")
        clock:posedge()
            value64:set({0x123, 0x456})
            value128:set({0x123, 0x456, 0x789, 0xABC})
        clock:posedge()
            value64:expect_hex_str("0000045600000123")
            value128:expect_hex_str("00000abc000007890000045600000123")
    end
}
local clock = dut.clock:chdl()
local cycles = dut.cycles:chdl()

fork {
    function()
        -- sim.dump_wave()

        clock:posedge(10, function()
            cycles:dump()
        end)

        sim.finish()
    end,

    function()
        local en3 = dut.u_top.en3:chdl()

        local expect_values = { 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0 } --[[@as table<integer, integer>]]
        for i = 1, #expect_values do
            en3:dump()
            en3:expect(expect_values[i])

            clock:posedge()
        end
    end,

    function()
        clock:negedge()
        local valid = dut.valid:chdl()
        while true do
            valid.value = 1
            clock:posedge()
            valid.value = 0
            clock:posedge()
        end
    end
}

fork {
    function()
        local inc = dut.inc:chdl()
        inc:set(1)
        await_rd()
        inc:set(2)
        sim.finish()
    end,
}

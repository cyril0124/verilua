fork {
    function()
        dut.clk:posedge(1000)
        assert(dut.oo1:get_width() == 1, dut.oo1:get_width())
        assert(dut.oo2:get_width() == 1, dut.oo2:get_width())
        assert(dut.oo3:get_width() == 8, dut.oo3:get_width())
        assert(dut.oo4:get_width() == 8, dut.oo4:get_width())
        assert(dut.oo5:get_width() == 1, dut.oo5:get_width())
        assert(dut.ii1:get_width() == 1, dut.ii1:get_width())
        assert(dut.ii2:get_width() == 1, dut.ii2:get_width())
        assert(dut.ii3:get_width() == 1, dut.ii3:get_width())
        assert(dut.ii4:get_width() == 8, dut.ii4:get_width())
        assert(dut.ii5:get_width() == 8, dut.ii5:get_width())
        assert(dut.ii6:get_width() == 8, dut.ii6:get_width())
        assert(dut.ii7:get_width() == 1, dut.ii7:get_width())
        sim.finish()
    end
}

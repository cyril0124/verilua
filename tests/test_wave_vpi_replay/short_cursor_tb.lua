local wctrl = require "verilua.utils.WaveVpiCtrl"
local clock = dut.clock:chdl()

fork {
    function()
        clock:posedge()
    end,
    function()
        wctrl:to_percent(100)
        assert(wctrl:get_cursor_index() == 0)
        wctrl:set_cursor_time(0)
        assert(wctrl:get_cursor_index() == 0)
        print("SHORT_CURSOR_PASS")
        sim.finish()
    end,
}

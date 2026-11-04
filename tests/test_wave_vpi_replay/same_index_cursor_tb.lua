io.stdout:setvbuf("no")

local wctrl = require "verilua.utils.WaveVpiCtrl"
local clock = dut.clock:chdl()
local other = dut.other:chdl()
local saw_clock = false
local saw_setter = false

fork {
    function()
        clock:posedge()
        saw_clock = true
    end,
    function()
        -- Register later so the cursor update precedes the clock callback.
        await_time(5)
        other:posedge()
        local index = wctrl:get_cursor_index()
        assert(index == 2 and wctrl:get_max_cursor_index() == 4, "waveform fixture changed")
        assert(not saw_clock, "setter must precede the clock callback")
        wctrl:to_percent(50)
        assert(wctrl:get_cursor_index() == index, "cursor moved unexpectedly")
        saw_setter = true
    end,
    function()
        await_time(15)
        assert(saw_setter, "setter did not run")
        assert(saw_clock, "same-index cursor update skipped concurrent clock edge")
        print("SAME_INDEX_CURSOR_PASS")
        sim.finish()
    end,
}

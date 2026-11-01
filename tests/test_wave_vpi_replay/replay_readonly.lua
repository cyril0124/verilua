-- Replay without --ignore-writes must reject the write instead of applying it.
local reset = dut.reset --[[@as verilua.handles.ProxyTableHandle]]

fork {
    function()
        reset:set(0)
    end,
}

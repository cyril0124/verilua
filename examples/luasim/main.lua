local luasim = require "verilua.luasim.Sim"

---@type verilua.handles.CallableHDL
local clock
---@type verilua.handles.CallableHDL
local valid
---@type verilua.handles.CallableHDL
local ready
---@type verilua.handles.CallableHDL
local data
---@type verilua.handles.CallableHDL
local response_valid
---@type verilua.handles.CallableHDL
local response_data
luasim.declare(function()
    clock = luasim.signal("tb_top.clock", { width = 1 })
    valid = luasim.signal("tb_top.req.valid", { width = 1 })
    ready = luasim.signal("tb_top.req.ready", { width = 1 })
    data = luasim.signal("tb_top.req.data", { width = 128 })
    response_valid = luasim.signal("tb_top.rsp.valid", { width = 1 })
    response_data = luasim.signal("tb_top.rsp.data", { width = 128 })
end)
local payload = "123456789abcdef0123456789abcdef0"

sim.dump_wave("luasim.vcd")

fork {
    clock_driver = function()
        while true do
            await_time_ns(5)
            clock:set(1)
            await_time_ns(5)
            clock:set(0)
        end
    end,
}

fork {
    responder = function()
        clock:negedge(3)
        ready:set(1)
        repeat
            clock:posedge()
        until valid:is(1) and ready:is(1)
        local captured = data:get_hex_str()
        clock:negedge()
        ready:set(0)
        clock:negedge(2)
        response_data:set_hex_str(captured)
        response_valid:set(1)
    end,
}

fork {
    test = function()
        clock:negedge()
        valid:set(1)
        data:set_hex_str(payload)
        repeat
            clock:posedge()
        until ready:is(1)
        clock:negedge()
        valid:set(0)
        repeat
            clock:posedge()
        until response_valid:is(1)
        response_data:expect_hex_str(payload)
        print("PASS: 128-bit request survives backpressure and delayed response")
        sim.finish()
    end,
}

fork {
    watchdog = function()
        await_time_ns(200)
        error("request did not complete within 200 ns")
    end,
}

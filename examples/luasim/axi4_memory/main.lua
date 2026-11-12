---@type table<string, verilua.handles.CallableHDL>
local axi = {}

local widths = {
    awvalid = 1,
    awready = 1,
    awid = 4,
    awaddr = 32,
    awlen = 8,
    awsize = 3,
    awburst = 2,

    wvalid = 1,
    wready = 1,
    wdata = 32,
    wstrb = 4,
    wlast = 1,

    bvalid = 1,
    bready = 1,
    bid = 4,
    bresp = 2,

    arvalid = 1,
    arready = 1,
    arid = 4,
    araddr = 32,
    arlen = 8,
    arsize = 3,
    arburst = 2,

    rvalid = 1,
    rready = 1,
    rid = 4,
    rdata = 32,
    rresp = 2,
    rlast = 1,
}

---@type verilua.handles.CallableHDL
local clock
---@type verilua.handles.CallableHDL
local reset_n

if cfg.simulator == "luasim" then
    local luasim = require "verilua.luasim.Sim"
    local AXI4Memory = require "AXI4Memory"

    luasim.declare(function()
        clock = luasim.signal("tb_top.clock", { width = 1 })
        reset_n = luasim.signal("tb_top.reset_n", { width = 1 })

        for name, width in pairs(widths) do
            axi[name] = luasim.signal("tb_top.axi." .. name, { width = width })
        end
    end)

    AXI4Memory.start(clock, reset_n, axi, {
        size_bytes = 4096,
        stall_every = 3,
    })
else
    clock = dut.clock:chdl()
    reset_n = (cfg.top .. ".reset"):chdl()

    for name in pairs(widths) do
        axi[name] = dut[name]:chdl()
    end
end

if cfg.simulator == "luasim" then
    sim.dump_wave("axi4_memory.vcd")
end

local run = require "AXI4Driver"
run(clock, reset_n, axi)

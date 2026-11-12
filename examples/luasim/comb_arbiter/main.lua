---@type CombArbiterPort
local input0
---@type CombArbiterPort
local input1
---@type CombArbiterPort
local output

if cfg.simulator == "luasim" then
    local luasim = require "verilua.luasim.Sim"
    local CombArbiter = require "CombArbiter"

    luasim.declare(function()
        input0 = {
            valid = luasim.signal("tb_top.input0.valid", { width = 1 }),
            ready = luasim.signal("tb_top.input0.ready", { width = 1 }),
            data = luasim.signal("tb_top.input0.data", { width = 32 }),
        }

        input1 = {
            valid = luasim.signal("tb_top.input1.valid", { width = 1 }),
            ready = luasim.signal("tb_top.input1.ready", { width = 1 }),
            data = luasim.signal("tb_top.input1.data", { width = 32 }),
        }

        output = {
            valid = luasim.signal("tb_top.output.valid", { width = 1 }),
            ready = luasim.signal("tb_top.output.ready", { width = 1 }),
            data = luasim.signal("tb_top.output.data", { width = 32 }),
        }
    end)

    CombArbiter.start(input0, input1, output)
else
    local top = dut
    input0 = {
        valid = top.input0_valid:chdl(),
        ready = top.input0_ready:chdl(),
        data = top.input0_data:chdl(),
    }

    input1 = {
        valid = top.input1_valid:chdl(),
        ready = top.input1_ready:chdl(),
        data = top.input1_data:chdl(),
    }

    output = {
        valid = top.output_valid:chdl(),
        ready = top.output_ready:chdl(),
        data = top.output_data:chdl(),
    }
end

if cfg.simulator == "luasim" then
    sim.dump_wave("comb_arbiter.vcd")
end

local run = require "ArbiterDriver"
run(input0, input1, output)

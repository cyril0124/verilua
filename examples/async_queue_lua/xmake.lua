---@diagnostic disable: undefined-global, undefined-field

-- Async Queue Example using Lua Clock Driver
-- Demonstrates cross-clock domain FIFO with Lua coroutines for both clock domains
-- Requires no_internal_clock since clocks are driven by Lua

target("test", function()
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "iverilog" then
            target:set("toolchains", "@iverilog")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    add_files("./async_queue.sv")
    set_values("cfg.top", "async_queue")
    set_values("cfg.lua_main", "./main.lua")

    -- Disable internal clock - we drive clocks using Lua
    set_values("cfg.no_internal_clock", "1")

    -- Specify primary clock for testbench generation
    add_values("cfg.tb_gen_flags", "--clock-signal", "wr_clk")
    add_values("cfg.tb_gen_flags", "--reset-signal", "wr_rst_n")

    -- Verilator requires TIMING_MODE for await_time with Lua clock drivers
    set_values("verilator.flags", "--timing")
end)

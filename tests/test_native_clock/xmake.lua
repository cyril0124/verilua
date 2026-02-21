---@diagnostic disable

local rtl_dir = path.join(os.scriptdir(), "..", "rtl")

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

    add_files(path.join(rtl_dir, "top.sv"))
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "main.lua")

    -- No internal clock - we want to test NativeClock
    set_values("cfg.no_internal_clock", "1")

    -- Use timing mode for Verilator to enable proper cbAfterDelay timing.
    -- In NORMAL_MODE, time advances by fixed increments (10000) per step
    -- regardless of cbAfterDelay callbacks. NativeClock requires TIMING_MODE
    -- for proper sub-step timing.
    set_values("verilator.flags", "--timing")
end)

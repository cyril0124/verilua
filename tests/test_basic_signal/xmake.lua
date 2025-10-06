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
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    add_files(path.join(rtl_dir, "top.sv"))
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "main.lua")

    if os.getenv("NO_INTERNAL_CLOCK") then
        set_values("cfg.no_internal_clock", "1")
    end
end)

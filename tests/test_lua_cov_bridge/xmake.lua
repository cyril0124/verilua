---@diagnostic disable

local sim = os.getenv("SIM") or "verilator"

-- Simulators with DPI export support, mapped to their xmake toolchain. Every other
-- simulator gets a target that does nothing.
local DPI_EXPORT_TOOLCHAINS = {
    verilator = "@verilator",
    vcs = "@vcs",
    xcelium = "@xcelium",
}

target("test", function()
    local sim_toolchain = DPI_EXPORT_TOOLCHAINS[sim]
    if sim_toolchain == nil then
        set_kind("phony")
        set_default(true)
        on_build(function() end)
        on_run(function() end)
        return
    end

    add_rules("verilua")

    on_config(function(target)
        target:set("toolchains", sim_toolchain)
    end)

    -- Verilator drops DPI exports that nothing references at link time.
    if sim == "verilator" then
        add_ldflags("-u verilua_cov_sample")
        add_ldflags("-u verilua_cov_hit_count")
    end

    add_files("top.sv")
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "./main.lua")

    -- cov_bridge.sv holds the covergroup and the DPI exports that Lua calls.
    add_values("verilua.tb_gen_flags", "--inject-inner-file", path.join(os.scriptdir(), "cov_bridge.sv"))
end)

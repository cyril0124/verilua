---@diagnostic disable: undefined-global, undefined-field

local simulator = os.getenv("SIM") or "luasim"

target("test", function()
    add_rules("verilua")
    local toolchain = ("@" .. simulator) --[[@as verilua.xmake.toolchains]]
    add_toolchains(toolchain)
    set_values("verilua.lua_main", "main.lua")

    if simulator == "luasim" then
        add_files("main.lua", "ArbiterDriver.lua", "CombArbiter.lua")
        set_values("verilua.top", "tb_top")
    else
        add_files("CombArbiter.sv")
        set_values("verilua.top", "CombArbiter")
        set_values("verilua.no_internal_clock", "1")
        add_values("verilator.flags", "--timing", "--trace")
        add_values("vcs.flags", "+define+VCS_DUMP_VCD")
    end
end)

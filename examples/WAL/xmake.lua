---@diagnostic disable: undefined-global, undefined-field

local sim = os.getenv("SIM") or "verilator"

target("gen_wave", function()
    add_rules("verilua")

    if sim == "iverilog" then
        add_toolchains("@iverilog")
    elseif sim == "vcs" then
        add_toolchains("@vcs")
    else
        add_toolchains("@verilator")
    end

    add_files("./Counter.v")
    add_files("./Monitor.lua")

    set_values("cfg.lua_main", "./main.lua")
    set_values("cfg.top", "Counter")

    set_values("verilator.flags", "--trace", "--no-trace-top")
end)

target("sim_wave", function()
    add_rules("verilua")
    add_toolchains("@wave_vpi")

    if sim == "iverilog" then
        add_files("./build/iverilog/Counter/wave/test.vcd")
    elseif sim == "vcs" then
        add_files("./build/vcs/Counter/wave/test.vcd.fsdb")
    else
        add_files("./build/verilator/Counter/wave/test.vcd")
    end

    add_files("./Monitor.lua")

    set_values("cfg.lua_main", "./main_for_wal.lua")
    set_values("cfg.top", "Counter")
end)

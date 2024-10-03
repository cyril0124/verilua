local PWD = os.getenv("PWD")
local sim = os.getenv("SIM") or "verilator"

target("gen_wave")
    add_rules("verilua")

    if sim == "iverilog" then
        add_toolchains("@iverilog") -- use iverilog
    else
        add_toolchains("@verilator") -- use verilator
    end

    add_files("./Counter.v")
    add_files("./Monitor.lua")
    
    set_values("cfg.lua_main", "./LuaMain.lua")
    set_values("cfg.top", "Counter")

    set_values("verilator.flags", "--trace", "--no-trace-top")

target("sim_wave")
    add_rules("verilua")
    add_toolchains("@wave_vpi")

    if sim == "iverilog" then
        add_files("./build/iverilog/Counter/wave/test.vcd") -- this wave file is generated by <generate_wave> target
    else
        add_files("./build/verilator/Counter/wave/test.vcd") -- this wave file is generated by <generate_wave> target
    end
    
    set_values("cfg.lua_main", "./LuaMainForWave.lua")
    set_values("cfg.top", "Counter")


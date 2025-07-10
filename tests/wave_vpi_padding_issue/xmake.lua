---@diagnostic disable

target("test")
    add_rules("verilua")
    add_toolchains("@iverilog")
    add_files("./Design.v")
    set_values("cfg.top", "Design")
    set_values("cfg.lua_main", "main.lua")

target("test_wave")
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files("./build/iverilog/Design/test.vcd")
    set_values("cfg.top", "Design")
    set_values("cfg.lua_main", "main.lua")
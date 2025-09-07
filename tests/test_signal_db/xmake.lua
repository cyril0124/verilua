---@diagnostic disable


target("test", function()
    add_rules("verilua")
    add_toolchains("@verilator")
    add_files("./top.sv")
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "./main.lua")
end)

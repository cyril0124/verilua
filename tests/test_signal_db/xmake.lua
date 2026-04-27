---@diagnostic disable


target("test", function()
    add_rules("verilua")
    add_toolchains("@verilator")
    add_files("./top.sv")
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "./main.lua")
end)

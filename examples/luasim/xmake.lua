---@diagnostic disable: undefined-global, undefined-field

target("test", function()
    add_rules("verilua")
    add_toolchains("@luasim")
    add_files("main.lua")
    set_values("verilua.top", "tb_top")
    set_values("verilua.lua_main", "main.lua")
end)

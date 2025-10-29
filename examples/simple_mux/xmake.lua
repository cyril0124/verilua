---@diagnostic disable: undefined-global, undefined-field

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

    add_files("./mux.sv")
    set_values("cfg.top", "mux")
    set_values("cfg.lua_main", "./main.lua")
end)

-- Minimal example
-- target("test", function()
--     add_rules("verilua")
--     add_toolchains("@iverilog")
--     add_files("./mux.sv")
--     set_values("cfg.top", "mux")
--     set_values("cfg.lua_main", "./main.lua")
-- end)

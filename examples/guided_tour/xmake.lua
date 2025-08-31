---@diagnostic disable

target("test-top", function()
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

    add_files("./top.sv")
    set_values("cfg.user_cfg", "./cfg.lua")
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "./main.lua")
end)
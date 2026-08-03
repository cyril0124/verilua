---@diagnostic disable: undefined-field, undefined-global

target("test", function()
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "vcs"
        if sim == "iverilog" then
            target:set("toolchains", "@iverilog")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    add_files("./top.sv")
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "main.lua")

    -- Verilator VPI force/release requires forceable signals (since 5.050).
    -- https://verilator.org/guide/latest/control.html#verilator-control-files
    set_values("verilua.verilator_config", [[
forceable -module "top" -var "ready"
]])
end)

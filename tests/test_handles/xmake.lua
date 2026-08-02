---@diagnostic disable: undefined-global, undefined-field

target("test", function()
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "iverilog" then
            target:set("toolchains", "@iverilog")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
            -- forceable needs Verilator >= 5.046; keep non-force coverage on older versions
            local ver = os.iorun("verilator --version") or ""
            local major, minor = ver:match("Verilator%s+(%d+)%.(%d+)")
            major, minor = tonumber(major), tonumber(minor)
            if major and (major > 5 or (major == 5 and minor >= 46)) then
                target:set("values", "verilua.verilator_config", [[
forceable -module "top" -var "opt_valid"
forceable -module "top" -var "opt_data"
]])
            end
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    add_files("top.sv")
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "main.lua")
end)

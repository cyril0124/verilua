---@diagnostic disable

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
                -- inc is driven from tb_top; counter is an internal reg in top.
                target:set("values", "verilua.verilator_config", [[
forceable -module "tb_top" -var "inc"
forceable -module "top" -var "inc"
forceable -module "top" -var "counter"
]])
            end
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    add_files("top.v")

    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "./main.lua")

    set_values("verilator.flags", "--trace", "--no-trace-top")
end)

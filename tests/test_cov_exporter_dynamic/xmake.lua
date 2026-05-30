---@diagnostic disable

target("test", function()
    add_rules("verilua")
    set_default(true)

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "verilator" then
            target:set("toolchains", "@verilator")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    add_files("cond_path_top.sv")
    set_values("verilua.top", "cond_path_top")
    set_values("verilua.lua_main", "main.lua")
    set_values("verilator.flags", "--Wno-MULTIDRIVEN")

    set_values("verilua.instrument", function()
        return {
            {
                type = "cov_exporter",
                config = {
                    { module = "cond_path_top" }
                },
            },
        }
    end)
end)

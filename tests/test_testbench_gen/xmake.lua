---@diagnostic disable

target("test_run_ansi", function()
    add_rules("verilua")
    set_default(false)

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

    add_files("./top_ansi.sv")
    set_values("cfg.top", "TopAnsi")
    set_values("cfg.lua_main", "./main.lua")
end)

target("test_run_non_ansi", function()
    add_rules("verilua")
    set_default(false)

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

    add_files("./top_non_ansi.sv")
    set_values("cfg.top", "TopNonAnsi")
    set_values("cfg.lua_main", "./main.lua")
end)

target("test", function()
    set_kind("phony")
    set_default(true)
    on_run(function(target)
        local build_dir = path.join(os.scriptdir(), "build")
        local rtl = path.join(os.scriptdir(), "top_ansi.sv")
        os.exec("testbench_gen %s --out-dir %s --regen --verbose --check-output", rtl, build_dir)

        -- TODO:
        -- rtl = path.join(os.scriptdir(), "top_non_ansi.sv")
        -- os.exec("testbench_gen %s --out-dir %s --regen --verbose --check-output", rtl, build_dir)
    end)
end)

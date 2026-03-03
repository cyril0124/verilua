---@diagnostic disable: undefined-global, undefined-field, unnecessary-if

local prj_dir = os.projectdir()
local wtype = os.getenv("WTYPE") or "vcd"

target("gen_wave", function()
    set_default(false)
    add_rules("verilua")

    -- Disable VCS initreg to preserve X-state in simulation
    set_values("cfg.vcs_no_initreg", "1")
    -- Enable VCS X-propagation to preserve X-state in FSDB
    set_values("vcs.flags", "-xprop=tmerge")

    on_config(function(target)
        local sim = os.getenv("SIM") or "iverilog"
        if sim == "iverilog" then
            target:set("toolchains", "@iverilog")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    after_run(function()
        local sim = os.getenv("SIM") or "iverilog"
        if sim == "iverilog" then
            assert(os.isfile("test.vcd"), "test.vcd not found")
            os.cp("test.vcd", prj_dir)
        elseif sim == "vcs" then
            assert(os.isfile("test.vcd.fsdb"), "test.vcd.fsdb not found")
            os.cp("test.vcd.fsdb", prj_dir)
        end
    end)

    add_files("./Design.v")
    set_values("cfg.top", "Design")
    set_values("cfg.lua_main", "gen_wave_main.lua")
end)

target("sim_wave", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")

    -- Disable WaveVPI JIT optimization to preserve X/Z state in string formats.
    -- JIT pre-computes values as uint32_t (2-state only), losing X/Z information.
    add_runenvs("WAVE_VPI_ENABLE_JIT", "0")

    if wtype == "fsdb" then
        add_files("./test.vcd.fsdb")
    else
        add_files("./test.vcd")
    end

    set_values("cfg.top", "tb_top")
    set_values("cfg.lua_main", "sim_wave_main.lua")
end)

target("run_test", function()
    set_default(true)
    set_kind("phony")

    on_build(function()
    end)

    on_run(function()
        -- Generate VCD wave using iverilog
        os.setenv("SIM", "iverilog")
        os.exec("xmake b -P . gen_wave")
        os.exec("xmake r -P . gen_wave")

        -- Test with VCD
        os.setenv("WTYPE", "vcd")
        os.exec("xmake b -P . sim_wave")
        os.exec("xmake r -P . sim_wave")

        -- Generate FSDB wave using VCS (if available)
        import("lib.detect.find_file")
        if find_file("vcs", { "$(env PATH)" }) then
            os.setenv("SIM", "vcs")
            os.exec("xmake b -P . gen_wave")
            os.exec("xmake r -P . gen_wave")

            -- Test with FSDB
            if find_file("verdi", { "$(env PATH)" }) and os.getenv("VERDI_HOME") then
                os.setenv("WTYPE", "fsdb")
                os.exec("xmake b -P . sim_wave")
                os.exec("xmake r -P . sim_wave")
            end
        end
    end)
end)

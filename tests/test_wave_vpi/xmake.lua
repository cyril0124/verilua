---@diagnostic disable: undefined-global, undefined-field, unnecessary-if

local prj_dir = os.projectdir()
local wtype = os.getenv("WTYPE") or "fsdb"

target("gen_wave", function()
    set_default(false)
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    after_run(function()
        local sim = os.getenv("SIM") or "verilator"
        if sim == "verilator" then
            assert(os.isfile("test.fst"), "test.fst not found")
            os.cp("test.fst", prj_dir)
        elseif sim == "vcs" then
            assert(os.isfile("test.vcd.fsdb"), "test.vcd.fsdb not found")
            os.cp("test.vcd.fsdb", prj_dir)
        end
    end)

    add_files("./top.sv")
    add_values("verilator.flags", "--trace", "--trace-fst")
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "gen_wave_main.lua")
end)

target("sim_wave", function()
    set_default(false)
    add_rules("verilua")

    add_toolchains("@wave_vpi")

    if wtype == "fsdb" then
        add_files("./test.vcd.fsdb")
    else
        add_files("./test.fst")
    end

    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "sim_wave_main.lua")
end)

target("gen_wave_all", function()
    set_default(false)
    set_kind("phony")
    on_run(function()
        os.setenv("SIM", "verilator")
        os.exec("xmake b -P . gen_wave")
        os.exec("xmake r -P . gen_wave")

        os.setenv("SIM", "vcs")
        os.exec("xmake b -P . gen_wave")
        os.exec("xmake r -P . gen_wave")
    end)
end)

target("run_test", function()
    set_default(true)
    set_kind("phony")

    on_build(function()
    end)

    on_run(function()
        local test_cases = {
            "basic",
            "to_end",
            "to_end_1",
            "to_end_2"
        }

        local wtypes = {
            "fst"
        }

        import("lib.detect.find_file")
        if find_file("verdi", { "$(env PATH)" }) and os.getenv("VERDI_HOME") then
            wtypes[#wtypes + 1] = "fsdb"
        end

        for _, _wtype in ipairs(wtypes) do
            os.setenv("WTYPE", _wtype)
            os.exec("xmake b -P . sim_wave")

            for _, tc in ipairs(test_cases) do
                os.setenv("TC_NAME", tc)
                os.exec("xmake r -P . sim_wave")
            end
        end
    end)
end)

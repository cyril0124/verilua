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
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "gen_wave_main.lua")
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

    set_values("verilua.top", "tb_top")
    set_values("verilua.lua_main", "sim_wave_main.lua")
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
            "to_end_2",
            "set_cursor_time",
            "get_max_cursor_time_unit",
            "set_cursor_time_unit",
            "padding",
            "sampling_phase"
        }

        local wtypes = {
            "fst"
        }

        import("lib.detect.find_file")
        if find_file("wave_vpi_main_fsdb", { "$(env PATH)" }) then
            wtypes[#wtypes + 1] = "fsdb"
        end

        for _, _wtype in ipairs(wtypes) do
            os.setenv("WTYPE", _wtype)
            os.exec("xmake b -P . sim_wave")

            for _, tc in ipairs(test_cases) do
                os.setenv("TC_NAME", tc)
                os.exec("xmake r -P . sim_wave")
            end

            local log_dir = path.join(prj_dir, "build", "sampling_logs")
            os.mkdir(log_dir)
            for _, jit in ipairs({ "0", "1" }) do
                local label = _wtype .. "-jit" .. jit
                local stdout_file = path.join(log_dir, label .. ".log")
                local stderr_file = path.join(log_dir, label .. ".err")
                local code = os.execv("xmake", { "run", "-P", prj_dir, "sim_wave" }, {
                    envs = { TC_NAME = "sampling_boundary", WAVE_VPI_ENABLE_JIT = jit },
                    stdout = stdout_file,
                    stderr = stderr_file,
                    try = true,
                })
                local output = (io.readfile(stdout_file) or "") .. (io.readfile(stderr_file) or "")
                assert(code == 0, label .. ": " .. output)
                assert(output:find("SAMPLING_BOUNDARY_PASS jit=" .. jit, 1, true), label .. ": " .. output)
                if jit == "1" then
                    local warmup = output:find("Continue optimization... tb_top.reset", 1, true)
                    local begin = output:find("SAMPLING_BOUNDARY_BEGIN", 1, true)
                    assert(warmup and begin and warmup < begin,
                        label .. ": reset JIT cache was not exercised: " .. output)
                end
                print("SAMPLING_MATRIX_PASS " .. label)
            end
        end
    end)
end)

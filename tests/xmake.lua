---@diagnostic disable: undefined-global, undefined-field

local scriptdir = os.scriptdir()
local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
end

local case_event_prefix = "@@VL_TEST_CASE@@"

local function join_case_parts(...)
    local parts = {}
    for _, part in ipairs({ ... }) do
        if part and part ~= "" then
            table.insert(parts, tostring(part))
        end
    end
    return table.concat(parts, "/")
end

target("test-all-lua", function()
    set_kind("phony")
    set_default(false)
    add_files(path.join(scriptdir, "test_*.lua"))
    on_run(function(target)
        local function emit_case_event(status, case_name, duration)
            local event_log = os.getenv("VL_TEST_EVENT_LOG")
            if not event_log or event_log == "" then
                return
            end

            local line = string.format("%s\t%s\t%s\t%s", case_event_prefix, status, case_name,
                duration ~= nil and tostring(duration) or "")
            os.execv(os.shell(), { "-c", "printf '%s\\n' " .. shell_quote(line) .. " >> " .. shell_quote(event_log) })
        end

        local function run_case(case_name, case_runner)
            emit_case_event("start", case_name)
            local start_time = os.time()
            local success = true
            local err = nil
            try {
                function()
                    case_runner()
                end,
                catch {
                    function(e)
                        success = false
                        err = e
                    end
                }
            }

            local duration = os.time() - start_time
            if success then
                emit_case_event("pass", case_name, duration)
            else
                emit_case_event("fail", case_name, duration)
                raise(err)
            end
        end

        local function run_lua_test_files(files)
            for index, file in ipairs(files) do
                run_case(path.filename(file), function()
                    print(string.format("=== [%d/%d] start test %s ==================================", index, #files, file))
                    os.exec("luajit %s --stop-on-fail --no-quiet", file)
                    print("")
                end)
            end
        end

        run_lua_test_files(target:sourcefiles())
    end)
end)

local core_basic_cases = {
    { dir = "test_edge", name = "test_edge" },
    { dir = "test_set_value", name = "test_set_value" },
    { dir = "test_basic_signal", name = "test_basic_signal", no_internal_clock = true },
    { dir = "test_scheduler", name = "test_scheduler" },
    { dir = "test_comb", name = "test_comb", no_internal_clock = true },
    { dir = "test_comb_1", name = "test_comb_1", no_internal_clock = true },
}

local core_extended_cases = {
    { dir = "test_bitvec_signal", name = "test_bitvec_signal" },
    { dir = "test_no_internal_clock", name = "test_no_internal_clock" },
    { dir = "test_handles", name = "test_handles" },
    { dir = "test_native_clock", name = "test_native_clock" },
    { dir = "test_queue_waitable", name = "test_queue_waitable" },
    { dir = "test_dpic", name = "test_dpic" },
}

local function add_group_target(name, runner)
    target(name, function()
        set_kind("phony")
        set_default(false)
        on_run(function()
            import("lib.detect.find_file")

            local function emit_case_event(status, case_name, duration)
                local event_log = os.getenv("VL_TEST_EVENT_LOG")
                if not event_log or event_log == "" then
                    return
                end

                local line = string.format("%s\t%s\t%s\t%s", case_event_prefix, status, case_name,
                    duration ~= nil and tostring(duration) or "")
                os.execv(os.shell(),
                    { "-c", "printf '%s\\n' " .. shell_quote(line) .. " >> " .. shell_quote(event_log) })
            end

            local function run_cmd(cwd, cmd, envs, opt)
                local env_prefix = ""
                if envs then
                    for key, value in pairs(envs) do
                        env_prefix = env_prefix .. key .. "=" .. shell_quote(value) .. " "
                    end
                end
                local full_cmd = "cd " .. shell_quote(cwd) .. " && " .. env_prefix .. cmd
                local ok = true
                try {
                    function()
                        os.execv(os.shell(), { "-c", full_cmd })
                    end,
                    catch {
                        function(e)
                            ok = false
                            if not (opt and opt.allow_fail) then
                                raise(e)
                            end
                        end
                    }
                }
                return ok
            end

            local function clean(...)
                for _, path_to_remove in ipairs({ ... }) do
                    os.tryrm(path_to_remove)
                end
            end

            local function run_case(case_name, case_runner)
                emit_case_event("start", case_name)
                local start_time = os.time()
                local success = true
                local err = nil
                try {
                    function()
                        case_runner()
                    end,
                    catch {
                        function(e)
                            success = false
                            err = e
                        end
                    }
                }

                local duration = os.time() - start_time
                if success then
                    emit_case_event("pass", case_name, duration)
                else
                    emit_case_event("fail", case_name, duration)
                    raise(err)
                end
            end

            local function run_xmake_pair(cwd, envs, build_cmd, run_cmdline, opt)
                if not (opt and opt.skip_clean) then
                    clean(path.join(cwd, "build"))
                end
                run_cmd(cwd, build_cmd, envs)
                return run_cmd(cwd, run_cmdline, envs, { allow_fail = opt and opt.allow_fail_run or false })
            end

            local function run_xmake_case(cwd, case_name, envs, build_cmd, run_cmdline, opt)
                run_case(case_name, function()
                    run_xmake_pair(cwd, envs, build_cmd, run_cmdline, opt)
                end)
            end

            local simulators = {}
            local has_verilator = false
            if find_file("iverilog", { "$(env PATH)" }) then
                table.insert(simulators, "iverilog")
            end
            if find_file("verilator", { "$(env PATH)" }) then
                has_verilator = true
                table.insert(simulators, "verilator")
            end
            if find_file("vcs", { "$(env PATH)" }) then
                table.insert(simulators, "vcs")
            end
            -- if find_file("xrun", { "$(env PATH)" }) then
            --     table.insert(simulators, "xcelium")
            -- end
            assert(#simulators > 0, "No simulators found!")

            local verilator_version
            if has_verilator then
                local version_output = os.iorun("verilator --version")
                local version = version_output:match("Verilator%s+([%d.]+)")
                verilator_version = tonumber(version)
                assert(verilator_version ~= nil, "Failed to parse Verilator version from `verilator --version`")
            end

            local ctx = {
                tests_dir = scriptdir,
                simulators = simulators,
                has_verilator = has_verilator,
                verilator_version = verilator_version,
                find_file = find_file,
                clean = clean,
                run_case = run_case,
                run_cmd = run_cmd,
                run_xmake_pair = run_xmake_pair,
                run_xmake_case = run_xmake_case,
            }
            runner(ctx)
        end)
    end)
end

add_group_target("test-core-basic", function(ctx)
    for _, case in ipairs(core_basic_cases) do
        local cwd = path.join(ctx.tests_dir, case.dir)
        for _, sim in ipairs(ctx.simulators) do
            if not (case.name == "test_comb_1" and sim == "verilator" and ctx.verilator_version and ctx.verilator_version < 5.036) then
                ctx.run_xmake_case(cwd, join_case_parts(case.name, sim), { SIM = sim }, "xmake build -v -P .",
                    "xmake run -v -P .")
            end
        end

        if ctx.has_verilator and not (case.name == "test_comb_1" and ctx.verilator_version and ctx.verilator_version < 5.036) then
            ctx.run_xmake_case(cwd, join_case_parts(case.name, "verilator", "cfg_use_inertial_put"), {
                SIM = "verilator",
                CFG_USE_INERTIAL_PUT = "1",
            }, "xmake build -v -P .", "xmake run -v -P .")
        end

        if case.no_internal_clock then
            for _, sim in ipairs(ctx.simulators) do
                if not (case.name == "test_comb_1" and sim == "verilator" and ctx.verilator_version and ctx.verilator_version < 5.036) then
                    ctx.run_xmake_case(cwd, join_case_parts(case.name, sim, "no_internal_clock"), {
                        SIM = sim,
                        NO_INTERNAL_CLOCK = "1",
                    }, "xmake build -v -P .", "xmake run -v -P .")
                end
            end
        end
    end
end)

add_group_target("test-core-extended", function(ctx)
    for _, case in ipairs(core_extended_cases) do
        local cwd = path.join(ctx.tests_dir, case.dir)
        for _, sim in ipairs(ctx.simulators) do
            ctx.run_xmake_case(cwd, join_case_parts(case.name, sim), { SIM = sim }, "xmake build -v -P .",
                "xmake run -v -P .")
        end

        if ctx.has_verilator then
            ctx.run_xmake_case(cwd, join_case_parts(case.name, "verilator", "cfg_use_inertial_put"), {
                SIM = "verilator",
                CFG_USE_INERTIAL_PUT = "1",
            }, "xmake build -v -P .", "xmake run -v -P .")
        end
    end
end)

add_group_target("test-wave-vpi", function(ctx)
    for _, dir in ipairs({
        "test_wave_vpi",
        "test_wave_vpi_x",
        "test_wave_vpi_print_hier",
        "test_wave_vpi_module_name",
    }) do
        ctx.run_case(dir, function()
            ctx.run_cmd(path.join(ctx.tests_dir, dir), "xmake run -P .")
        end)
    end
end)

add_group_target("test-wave-padding", function(ctx)
    local cwd = path.join(ctx.tests_dir, "wave_vpi_padding_issue")
    ctx.clean(path.join(cwd, "build"))
    ctx.run_case("wave_vpi_padding_issue/test", function()
        ctx.run_cmd(cwd, "xmake build -v -P . test")
        ctx.run_cmd(cwd, "xmake run -v -P . test")
    end)
    ctx.run_case("wave_vpi_padding_issue/test_wave", function()
        ctx.run_cmd(cwd, "xmake build -v -P . test_wave")
        ctx.run_cmd(cwd, "xmake run -v -P . test_wave")
    end)
end)

add_group_target("test-benchmarks", function(ctx)
    local cwd = path.join(ctx.tests_dir, "benchmarks")
    for _, case_name in ipairs({
        "signal_operation",
        "multitasking",
        "matrix_multiplier",
        "matrix_multiplier_no_internal_clock",
    }) do
        for _, sim in ipairs(ctx.simulators) do
            ctx.run_xmake_case(cwd, join_case_parts(case_name, sim), { SIM = sim }, string.format("xmake build -P . %s", case_name),
                string.format("xmake run -P . %s", case_name), { skip_clean = true })
        end

        if ctx.has_verilator then
            ctx.run_xmake_case(cwd, join_case_parts(case_name, "verilator", "cfg_use_inertial_put"), {
                SIM = "verilator",
                CFG_USE_INERTIAL_PUT = "1",
            }, string.format("xmake build -P . %s", case_name), string.format("xmake run -P . %s", case_name),
                { skip_clean = true })
        end
    end
end)

add_group_target("test-benchmarks-wave-vpi", function(ctx)
    local cwd = path.join(ctx.tests_dir, "benchmarks")

    -- FST and VCD benchmarks (require wave_vpi_main + verilator)
    local has_wave_vpi = ctx.find_file("wave_vpi_main", { "$(env PATH)" })
    if has_wave_vpi and ctx.has_verilator then
        -- FST benchmark
        ctx.run_case("wave_vpi_bench/gen", function()
            ctx.clean(path.join(cwd, "build", "verilator", "wave_vpi_gen"))
            ctx.clean(path.join(cwd, "build", "wave_vpi", "wave_vpi_bench"))
            ctx.run_cmd(cwd, "xmake build -P . wave_vpi_gen", { SIM = "verilator" })
            ctx.run_cmd(cwd, "xmake run -P . wave_vpi_gen", { SIM = "verilator" })
            ctx.run_cmd(cwd, "xmake build -P . wave_vpi_bench")
        end)

        for _, jit in ipairs({ "1", "0" }) do
            local jit_label = jit == "1" and "jit_on" or "jit_off"
            ctx.run_case("wave_vpi_bench/" .. jit_label, function()
                ctx.run_cmd(cwd, "xmake run -P . wave_vpi_bench", {
                    WAVE_VPI_ENABLE_JIT = jit,
                })
            end)
        end

        -- VCD benchmark
        ctx.run_case("wave_vpi_bench_vcd/gen", function()
            ctx.run_cmd(cwd, "xmake build -P . wave_vpi_gen_vcd")
            ctx.run_cmd(cwd, "xmake run -P . wave_vpi_gen_vcd", { WAVE_DUMP_FILE = "bench.vcd" })
            ctx.run_cmd(cwd, "xmake build -P . wave_vpi_bench_vcd")
        end)

        for _, jit in ipairs({ "1", "0" }) do
            local jit_label = jit == "1" and "jit_on" or "jit_off"
            ctx.run_case("wave_vpi_bench_vcd/" .. jit_label, function()
                ctx.run_cmd(cwd, "xmake run -P . wave_vpi_bench_vcd", {
                    WAVE_VPI_ENABLE_JIT = jit,
                })
            end)
        end
    end

    -- FSDB benchmark (conditional: requires vcs + verdi + wave_vpi_main_fsdb)
    local has_fsdb = ctx.find_file("wave_vpi_main_fsdb", { "$(env PATH)" })
        and ctx.find_file("vcs", { "$(env PATH)" })
        and os.getenv("VERDI_HOME")
    if has_fsdb then
        ctx.run_case("wave_vpi_bench_fsdb/gen", function()
            ctx.run_cmd(cwd, "xmake build -P . wave_vpi_gen_fsdb")
            ctx.run_cmd(cwd, "xmake run -P . wave_vpi_gen_fsdb", { WAVE_DUMP_FILE = "bench.vcd" })
            ctx.run_cmd(cwd, "xmake build -P . wave_vpi_bench_fsdb")
        end)

        for _, jit in ipairs({ "1", "0" }) do
            local jit_label = jit == "1" and "jit_on" or "jit_off"
            ctx.run_case("wave_vpi_bench_fsdb/" .. jit_label, function()
                ctx.run_cmd(cwd, "xmake run -P . wave_vpi_bench_fsdb", {
                    WAVE_VPI_ENABLE_JIT = jit,
                })
            end)
        end
    end
end)

add_group_target("test-testbench-gen", function(ctx)
    local cwd = path.join(ctx.tests_dir, "test_testbench_gen")
    ctx.run_case("test_testbench_gen/default", function()
        ctx.run_cmd(cwd, "xmake run -P .")
    end)
    for _, sim in ipairs(ctx.simulators) do
        if sim ~= "iverilog" then
            ctx.run_xmake_case(cwd, join_case_parts("test_testbench_gen", "test_run_ansi", sim), { SIM = sim },
                "xmake b -P . test_run_ansi", "xmake r -P . test_run_ansi")
        end
    end
end)

add_group_target("test-tools", function(ctx)
    ctx.run_case("test_dpi_exporter", function()
        ctx.run_cmd(path.join(ctx.tests_dir, "test_dpi_exporter"), "xmake run -P .")
    end)
    ctx.run_case("test_cov_exporter", function()
        ctx.run_cmd(path.join(ctx.tests_dir, "test_cov_exporter"), "xmake run -P .")
    end)
    ctx.run_xmake_case(path.join(ctx.tests_dir, "test_signal_db"), "test_signal_db", nil, "xmake build -P .",
        "xmake run -P .", {
            skip_clean = true,
        })
end)

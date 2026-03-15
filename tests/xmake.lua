---@diagnostic disable: undefined-global, undefined-field

local scriptdir = os.scriptdir()
--- Wrap a value in single quotes for safe shell interpolation.
local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
end

local case_event_prefix = "@@VL_TEST_CASE@@"

--- Join case name segments with "/" separator, skipping empty parts.
---@param ... string Case name segments to join with "/"
---@return string
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
        --- Append a test case event line to VL_TEST_EVENT_LOG (if set).
        ---@param status string Event status ("start", "pass", "fail")
        ---@param case_name string Test case name
        ---@param duration? number Duration in seconds
        local function emit_case_event(status, case_name, duration)
            local event_log = os.getenv("VL_TEST_EVENT_LOG")
            if not event_log or event_log == "" then
                return
            end

            local line = string.format("%s\t%s\t%s\t%s", case_event_prefix, status, case_name,
                duration ~= nil and tostring(duration) or "")
            os.execv(os.shell(), { "-c", "printf '%s\\n' " .. shell_quote(line) .. " >> " .. shell_quote(event_log) })
        end

        --- Run a named test case, emitting start/pass/fail events.
        ---@param case_name string Test case name
        ---@param case_runner fun() Function that runs the test
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

        --- Run all Lua test files sequentially with case event logging.
        ---@param files string[] List of Lua test file paths
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

---@class TestGroupContext
---@field tests_dir string Path to the tests/ directory
---@field simulators string[] Available simulator names (e.g. {"iverilog", "verilator", "vcs"})
---@field has_verilator boolean Whether verilator is available
---@field verilator_version number|nil Parsed verilator version (e.g. 5.036)
---@field find_file fun(name: string, dirs: string[]): string|nil
---@field clean fun(...: string) Remove paths
---@field run_case fun(case_name: string, case_runner: fun()) Run a named test case with event logging
---@field run_cmd fun(cwd: string, cmd: string, envs?: table<string,string>, opt?: {allow_fail?: boolean}): boolean

--- Create a phony xmake target that detects available simulators and runs a test group.
---@param name string Target name (becomes an xmake phony target)
---@param runner fun(ctx: TestGroupContext)
local function add_group_target(name, runner)
    target(name, function()
        set_kind("phony")
        set_default(false)
        on_run(function()
            import("lib.detect.find_file")

            --- Append a test case event line to VL_TEST_EVENT_LOG (if set).
            ---@param status string Event status ("start", "pass", "fail")
            ---@param case_name string Test case name
            ---@param duration? number Duration in seconds
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

            --- Execute a shell command in a given directory with optional env vars.
            ---@param cwd string Working directory
            ---@param cmd string Shell command to execute
            ---@param envs? table<string,string> Environment variables
            ---@param opt? {allow_fail?: boolean}
            ---@return boolean ok
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

            --- Remove filesystem paths (ignoring errors).
            ---@param ... string Paths to remove
            local function clean(...)
                for _, path_to_remove in ipairs({ ... }) do
                    os.tryrm(path_to_remove)
                end
            end

            --- Run a named test case, emitting start/pass/fail events.
            ---@param case_name string Test case name
            ---@param case_runner fun() Function that runs the test
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
            }
            runner(ctx)
        end)
    end)
end

---@class SimTestCase
---@field dir string Test directory name under tests/ (e.g. "test_edge")
---@field name string Test case display name (e.g. "test_edge")
---@field no_internal_clock? boolean Also run with NO_INTERNAL_CLOCK=1
---@field min_verilator_version? number Skip verilator if version < this (e.g. 5.036)

-- All sim-based test cases — each directory gets its own parallel target
---@type SimTestCase[]
local sim_test_cases = {
    { dir = "test_edge", name = "test_edge" },
    { dir = "test_set_value", name = "test_set_value" },
    { dir = "test_basic_signal", name = "test_basic_signal", no_internal_clock = true },
    { dir = "test_scheduler", name = "test_scheduler" },
    { dir = "test_comb", name = "test_comb", no_internal_clock = true },
    { dir = "test_comb_1", name = "test_comb_1", no_internal_clock = true, min_verilator_version = 5.036 },
    { dir = "test_bitvec_signal", name = "test_bitvec_signal" },
    { dir = "test_no_internal_clock", name = "test_no_internal_clock" },
    { dir = "test_handles", name = "test_handles" },
    { dir = "test_native_clock", name = "test_native_clock" },
    { dir = "test_queue_waitable", name = "test_queue_waitable" },
    { dir = "test_dpic", name = "test_dpic" },
}

-- Create a per-directory sim test target for each case (build + run for all sims).
for _, case in ipairs(sim_test_cases) do
    add_group_target(case.dir:gsub("_", "-"), function(ctx)
        local cwd = path.join(ctx.tests_dir, case.dir)
        local skip_verilator = case.min_verilator_version and ctx.verilator_version
            and ctx.verilator_version < case.min_verilator_version

        for _, sim in ipairs(ctx.simulators) do
            if not (skip_verilator and sim == "verilator") then
                ctx.run_case(join_case_parts(case.name, sim), function()
                    ctx.clean(path.join(cwd, "build"))
                    ctx.run_cmd(cwd, "xmake build -v -P .", { SIM = sim })
                    ctx.run_cmd(cwd, "xmake run -v -P .", { SIM = sim })
                end)
            end
        end

        if ctx.has_verilator and not skip_verilator then
            ctx.run_case(join_case_parts(case.name, "verilator", "cfg_use_inertial_put"), function()
                ctx.clean(path.join(cwd, "build"))
                ctx.run_cmd(cwd, "xmake build -v -P .", { SIM = "verilator", CFG_USE_INERTIAL_PUT = "1" })
                ctx.run_cmd(cwd, "xmake run -v -P .", { SIM = "verilator", CFG_USE_INERTIAL_PUT = "1" })
            end)
        end

        if case.no_internal_clock then
            for _, sim in ipairs(ctx.simulators) do
                if not (skip_verilator and sim == "verilator") then
                    ctx.run_case(join_case_parts(case.name, sim, "no_internal_clock"), function()
                        ctx.clean(path.join(cwd, "build"))
                        ctx.run_cmd(cwd, "xmake build -v -P .", { SIM = sim, NO_INTERNAL_CLOCK = "1" })
                        ctx.run_cmd(cwd, "xmake run -v -P .", { SIM = sim, NO_INTERNAL_CLOCK = "1" })
                    end)
                end
            end
        end
    end)
end

-- Wave VPI tests — each directory gets its own parallel target
for _, dir in ipairs({
    "test_wave_vpi",
    "test_wave_vpi_x",
    "test_wave_vpi_print_hier",
    "test_wave_vpi_module_name",
}) do
    add_group_target(dir:gsub("_", "-"), function(ctx)
        ctx.run_case(dir, function()
            ctx.run_cmd(path.join(ctx.tests_dir, dir), "xmake run -P .")
        end)
    end)
end

add_group_target("test-benchmarks", function(ctx)
    local cwd = path.join(ctx.tests_dir, "benchmarks")
    for _, case_name in ipairs({
        "signal_operation",
        "multitasking",
        "matrix_multiplier",
        "matrix_multiplier_no_internal_clock",
    }) do
        local build_cmd = string.format("xmake build -P . %s", case_name)
        local run_cmd = string.format("xmake run -P . %s", case_name)

        for _, sim in ipairs(ctx.simulators) do
            ctx.run_case(join_case_parts(case_name, sim), function()
                ctx.run_cmd(cwd, build_cmd, { SIM = sim })
                ctx.run_cmd(cwd, run_cmd, { SIM = sim })
            end)
        end

        if ctx.has_verilator then
            ctx.run_case(join_case_parts(case_name, "verilator", "cfg_use_inertial_put"), function()
                ctx.run_cmd(cwd, build_cmd, { SIM = "verilator", CFG_USE_INERTIAL_PUT = "1" })
                ctx.run_cmd(cwd, run_cmd, { SIM = "verilator", CFG_USE_INERTIAL_PUT = "1" })
            end)
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
            ctx.run_case(join_case_parts("test_testbench_gen", "test_run_ansi", sim), function()
                ctx.clean(path.join(cwd, "build"))
                ctx.run_cmd(cwd, "xmake b -P . test_run_ansi", { SIM = sim })
                ctx.run_cmd(cwd, "xmake r -P . test_run_ansi", { SIM = sim })
            end)
        end
    end
end)

-- Tool tests — each directory gets its own parallel target
add_group_target("test-dpi-exporter", function(ctx)
    ctx.run_case("test_dpi_exporter", function()
        ctx.run_cmd(path.join(ctx.tests_dir, "test_dpi_exporter"), "xmake run -P .")
    end)
end)

add_group_target("test-cov-exporter", function(ctx)
    ctx.run_case("test_cov_exporter", function()
        ctx.run_cmd(path.join(ctx.tests_dir, "test_cov_exporter"), "xmake run -P .")
    end)
end)

add_group_target("test-signal-db", function(ctx)
    ctx.run_case("test_signal_db", function()
        local cwd = path.join(ctx.tests_dir, "test_signal_db")
        ctx.run_cmd(cwd, "xmake build -P .")
        ctx.run_cmd(cwd, "xmake run -P .")
    end)
end)

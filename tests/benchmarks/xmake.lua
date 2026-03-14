---@diagnostic disable: undefined-global, undefined-field

local curr_dir = os.scriptdir()
local rtl_dir = path.join(os.scriptdir(), "..", "rtl")
local wave_vpi_rtl_dir = path.join(os.scriptdir(), "rtl")

local function target_common()
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
        else
            raise("unknown simulator: %s", sim)
        end
    end)
end

target("signal_operation", function()
    target_common()
    set_default(false)
    add_files(path.join(rtl_dir, "top.sv"))
    set_values("cfg.top", "top")
    set_values("cfg.build_dir_name", "signal_operation")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "signal_operation.lua"))
end)

target("multitasking", function()
    target_common()
    set_default(false)
    add_files(path.join(rtl_dir, "top.sv"))
    set_values("cfg.top", "top")
    set_values("cfg.build_dir_name", "multitasking")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "multitasking.lua"))
end)

target("matrix_multiplier", function()
    target_common()
    set_default(false)
    add_files(path.join(rtl_dir, "matrix_multiplier.sv"))
    set_values("cfg.top", "matrix_multiplier")
    set_values("cfg.build_dir_name", "matrix_multiplier")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "matrix_multiplier.lua"))
end)

target("matrix_multiplier_no_internal_clock", function()
    target_common()
    set_default(false)
    add_files(path.join(rtl_dir, "matrix_multiplier.sv"))
    set_values("cfg.top", "matrix_multiplier")
    set_values("cfg.no_internal_clock", "1")
    set_values("cfg.build_dir_name", "matrix_multiplier_no_internal_clock")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "matrix_multiplier_no_internal_clock.lua"))
end)

target("wave_vpi_gen", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@verilator")
    add_files(path.join(wave_vpi_rtl_dir, "wave_vpi_bench.sv"))
    add_values("verilator.flags", "--trace", "--trace-fst")
    set_values("cfg.top", "wave_vpi_bench")
    set_values("cfg.build_dir_name", "wave_vpi_gen")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "wave_vpi_gen.lua"))

    after_run(function()
        assert(os.isfile("bench.fst"), "bench.fst not found after wave_vpi_gen run")
        local waves_dir = path.join(curr_dir, "waves")
        os.mkdir(waves_dir)
        os.cp("bench.fst", waves_dir)
    end)
end)

target("wave_vpi_bench", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files(path.join(curr_dir, "waves", "bench.fst"))
    set_values("cfg.top", "tb_top")
    set_values("cfg.build_dir_name", "wave_vpi_bench")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "wave_vpi_bench.lua"))
end)

target("wave_vpi_gen_vcd", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@verilator")
    add_files(path.join(wave_vpi_rtl_dir, "wave_vpi_bench.sv"))
    add_values("verilator.flags", "--trace")
    set_values("cfg.top", "wave_vpi_bench")
    set_values("cfg.build_dir_name", "wave_vpi_gen_vcd")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "wave_vpi_gen.lua"))

    after_run(function()
        assert(os.isfile("bench.vcd"), "bench.vcd not found after wave_vpi_gen_vcd run")
        local waves_dir = path.join(curr_dir, "waves")
        os.mkdir(waves_dir)
        os.cp("bench.vcd", waves_dir)
    end)
end)

target("wave_vpi_bench_vcd", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files(path.join(curr_dir, "waves", "bench.vcd"))
    set_values("cfg.top", "tb_top")
    set_values("cfg.build_dir_name", "wave_vpi_bench_vcd")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "wave_vpi_bench.lua"))
end)

target("wave_vpi_gen_fsdb", function()
    set_default(false)
    add_rules("verilua")

    on_config(function(target)
        import("lib.detect.find_file")
        local has_fsdb = find_file("wave_vpi_main_fsdb", { "$(env PATH)" })
            and find_file("vcs", { "$(env PATH)" })
            and os.getenv("VERDI_HOME")
        if has_fsdb then
            target:set("toolchains", "@vcs")
        else
            target:set("toolchains", "@iverilog")
        end
    end)

    add_files(path.join(wave_vpi_rtl_dir, "wave_vpi_bench.sv"))
    set_values("cfg.top", "wave_vpi_bench")
    set_values("cfg.build_dir_name", "wave_vpi_gen_fsdb")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "wave_vpi_gen.lua"))

    after_run(function()
        local waves_dir = path.join(curr_dir, "waves")
        os.mkdir(waves_dir)
        assert(os.isfile("bench.vcd.fsdb"), "bench.vcd.fsdb not found after wave_vpi_gen_fsdb run")
        os.cp("bench.vcd.fsdb", waves_dir)
    end)
end)

target("wave_vpi_bench_fsdb", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files(path.join(curr_dir, "waves", "bench.vcd.fsdb"))
    set_values("cfg.top", "tb_top")
    set_values("cfg.build_dir_name", "wave_vpi_bench_fsdb")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "wave_vpi_bench.lua"))
end)

target("benchmarks", function()
    set_kind("phony")
    set_default(true)
    on_run(function(target)
        import("core.base.json")
        import("lib.detect.find_file")
        if not find_file("hyperfine", { "$(env PATH)" }) then
            raise("[benchmarks] hyperfine not found!")
        end

        local warmup = 10
        local runs = 10
        local simulators = {
            "iverilog",
            "verilator",
        }
        local simulator_versions = {}
        local cases = {
            "signal_operation",
            "multitasking",
            "matrix_multiplier"
        }
        local results = {}
        local merged_resutls = {}

        for _, simulator in ipairs(simulators) do
            if not find_file(simulator, { "$(env PATH)" }) then
                raise("[benchmarks] simulator: `%s` not found!", simulator)
            end
        end

        if find_file("vcs", { "$(env PATH)" }) then
            table.insert(simulators, "vcs")
        end

        for _, sim in ipairs(simulators) do
            if sim == "iverilog" then
                simulator_versions[sim] = os.iorun("iverilog -V"):split('\n', { plain = true })[1]
            elseif sim == "verilator" then
                simulator_versions[sim] = os.iorun("verilator --version"):split('\n', { plain = true })[1]
            elseif sim == "vcs" then
                local got_vcs_version = false
                for _, line in ipairs(os.iorun("vcs -help"):split('\n', { plain = true })) do
                    if line:startswith("vcs script version") then
                        simulator_versions[sim] = line
                        got_vcs_version = true
                    end
                end
                assert(got_vcs_version, "[benchmarks] failed to get vcs version")
            else
                raise("[benchmarks] simulator: `%s` not supported!", sim)
            end
        end

        for _, sim in ipairs(simulators) do
            for _, jit_v in ipairs({ "on", "off" }) do
                local sum_value = 0
                local extra_info = format("sim version: %s", simulator_versions[sim])
                for _, case in ipairs(cases) do
                    local command_name = case .. "__sim_" .. sim .. "__jit_" .. jit_v

                    os.tryrm(path.join(curr_dir, "build"))
                    os.execv("xmake", {
                        "build",
                        "-P", curr_dir,
                        case
                    }, {
                        envs = {
                            SIM = sim,
                        }
                    })

                    os.execv("hyperfine", {
                        "-w", warmup,
                        "-r", runs,
                        "--command-name", command_name,
                        "--export-json", command_name .. ".json",
                        format("xmake run -P %s %s", curr_dir, case)
                    }, {
                        envs = {
                            JIT_V = jit_v,
                            SIM = sim,
                        }
                    })

                    local v = json.loadfile(path.join(curr_dir, command_name .. ".json")).results[1].mean * 1000
                    results[#results + 1] = {
                        name = format("[benchmarks] %s - sim `%s` - jit `%s`", case, sim, jit_v),
                        unit = "ms",
                        value = v,
                        extra = extra_info,
                    }
                    sum_value = sum_value + v
                end

                merged_resutls[#merged_resutls + 1] = {
                    name = format("[benchmarks] merged resutls - sim `%s` - jit `%s`", sim, jit_v),
                    unit = "ms",
                    value = sum_value,
                    extra = extra_info,
                }
            end
        end

        print("results:", results)
        print("merged_resutls:", merged_resutls)

        -- wave_vpi benchmarks: Hot-Prefetch JIT on/off × hot signal count × waveform format
        local wave_vpi_hot_counts = { 5, 10, 100, 1000 }
        local run_wave_vpi = find_file("wave_vpi_main", { "$(env PATH)" })

        if run_wave_vpi then
            local wave_formats = {
                { name = "fst", gen_target = "wave_vpi_gen",     bench_target = "wave_vpi_bench",     gen_envs = { SIM = "verilator" },            run_envs = {} },
                { name = "vcd", gen_target = "wave_vpi_gen_vcd", bench_target = "wave_vpi_bench_vcd", gen_envs = { WAVE_DUMP_FILE = "bench.vcd" }, run_envs = {} },
            }

            local has_fsdb = find_file("wave_vpi_main_fsdb", { "$(env PATH)" })
                and find_file("vcs", { "$(env PATH)" })
                and os.getenv("VERDI_HOME")
            if has_fsdb then
                table.insert(wave_formats, {
                    name = "fsdb",
                    gen_target = "wave_vpi_gen_fsdb",
                    bench_target = "wave_vpi_bench_fsdb",
                    gen_envs = { WAVE_DUMP_FILE = "bench.vcd" },
                    run_envs = {},
                })
            else
                cprint(
                    "${yellow}[WARN] skip wave_vpi FSDB benchmarks: wave_vpi_main_fsdb/vcs/VERDI_HOME not found${clear}")
            end

            for _, fmt in ipairs(wave_formats) do
                -- Generate waveform
                os.tryrm(path.join(curr_dir, "build"))
                os.execv("xmake", { "build", "-P", curr_dir, fmt.gen_target }, {
                    envs = fmt.gen_envs,
                })
                os.execv("xmake", { "run", "-P", curr_dir, fmt.gen_target }, {
                    envs = fmt.gen_envs,
                })

                -- Benchmark with hot signal counts × JIT on/off
                local wave_sum = {}
                for _, jit_v in ipairs({ "on", "off" }) do
                    wave_sum[jit_v] = 0
                    for _, hot_count in ipairs(wave_vpi_hot_counts) do
                        local command_name = format("wave_vpi_%s_hot%d__jit_%s", fmt.name, hot_count, jit_v)

                        os.tryrm(path.join(curr_dir, "build", "wave_vpi"))
                        os.execv("xmake", { "build", "-P", curr_dir, fmt.bench_target })
                        os.execv("hyperfine", {
                            "-w", warmup,
                            "-r", runs,
                            "--command-name", command_name,
                            "--export-json", command_name .. ".json",
                            format("xmake run -P %s %s", curr_dir, fmt.bench_target),
                        }, {
                            envs = {
                                WAVE_VPI_ENABLE_JIT = jit_v == "on" and "1" or "0",
                                HOT_SIGNAL_COUNT = tostring(hot_count),
                            },
                        })

                        local v = json.loadfile(path.join(curr_dir, command_name .. ".json")).results[1].mean * 1000
                        results[#results + 1] = {
                            name = format("[benchmarks] wave_vpi_%s_hot%d - wave_vpi jit `%s`", fmt.name, hot_count,
                                jit_v),
                            unit = "ms",
                            value = v,
                            extra = format("wave_vpi %s Hot-Prefetch JIT %s", fmt.name:upper(), jit_v),
                        }
                        wave_sum[jit_v] = wave_sum[jit_v] + v
                    end

                    merged_resutls[#merged_resutls + 1] = {
                        name = format("[benchmarks] merged resutls - wave_vpi_%s jit `%s`", fmt.name, jit_v),
                        unit = "ms",
                        value = wave_sum[jit_v],
                        extra = format("wave_vpi %s Hot-Prefetch JIT %s", fmt.name:upper(), jit_v),
                    }
                end
            end
        else
            cprint("${yellow}[WARN] skip wave_vpi benchmarks: wave_vpi_main not found${clear}")
        end

        print("wave_vpi results added")

        local final_results = {}
        table.join2(final_results, merged_resutls)
        table.join2(final_results, results)
        json.savefile(path.join(curr_dir, "output.json"), final_results)
    end)
end)

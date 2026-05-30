---@diagnostic disable

target("test", function()
    set_kind("phony")
    set_default(true)
    on_run(function(target)
        -- Helper function to compare output with golden file using diff
        local function compare_file(output_file, golden_file, test_name)
            if not os.isfile(output_file) then
                print(string.format("[%s] FAILED: Output file not found: %s", test_name, output_file))
                return false
            end
            if not os.isfile(golden_file) then
                print(string.format("[%s] SKIPPED: Golden file not found: %s", test_name, golden_file))
                return true -- Skip comparison if golden file doesn't exist
            end

            -- Use diff command to compare files (diff returns 0 if files are identical)
            local diff_result = os.execv("diff", { "-q", golden_file, output_file }, { try = true })
            if diff_result == 0 then
                print(string.format("[%s] PASSED (golden match)", test_name))
                return true
            else
                print(string.format("[%s] FAILED: File contents differ", test_name))
                print(string.format("  Output: %s", output_file))
                print(string.format("  Golden: %s", golden_file))
                print("")
                print("=" .. string.rep("=", 60))
                print("DIFF DETAILS (unified format):")
                print("  '-' lines: content in golden file (expected)")
                print("  '+' lines: content in output file (actual)")
                print("=" .. string.rep("=", 60))
                -- Show diff details (diff -u will print to stdout directly)
                os.execv("diff", { "-u", golden_file, output_file }, { try = true })
                print("=" .. string.rep("=", 60))
                return false
            end
        end

        local test_dir = os.scriptdir()
        local golden_dir = path.join(test_dir, "golden")
        local rtl = path.join(test_dir, "top.sv")
        local all_passed = true
        local test_count = 0
        local pass_count = 0

        print("=" .. string.rep("=", 60))
        print("Running cov_exporter tests...")
        print("=" .. string.rep("=", 60))

        -- Test 1: Basic module coverage
        test_count = test_count + 1
        local test_name = "basic"
        local output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)

        print(string.format("\n[%s] Running cov_exporter...", test_name))
        local cmd = format("cov_exporter %s -m top --od %s --wd %s -q --relative-file-path", rtl, output_dir, output_dir)
        local ok = try { function()
            os.exec(cmd)
            return true
        end }

        if not ok then
            print(string.format("[%s] FAILED: cov_exporter execution failed", test_name))
            all_passed = false
        else
            -- Compare generated files with golden files
            local top_sv_output = path.join(output_dir, "top.sv")
            local top_sv_golden = path.join(golden_dir, test_name .. "_top.sv")

            local meta_output = path.join(output_dir, "cov_exporter.meta.json")

            local passed = true

            -- Compare top.sv
            if not compare_file(top_sv_output, top_sv_golden, test_name .. "_top_sv") then
                passed = false
            end

            -- Note: Skip meta.json comparison as it may contain paths that differ between runs
            -- Just check it exists
            if not os.isfile(meta_output) then
                print(string.format("[%s] FAILED: Meta file not generated", test_name))
                passed = false
            else
                print(string.format("[%s_meta] PASSED (file exists)", test_name))
            end

            if passed then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        end

        -- Test 2: With disable signal pattern
        test_count = test_count + 1
        test_name = "disable_signal"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)

        print(string.format("\n[%s] Running cov_exporter...", test_name))
        cmd = format("cov_exporter %s -m top --ds top:counter --od %s --wd %s -q --relative-file-path", rtl, output_dir,
            output_dir)
        ok = try { function()
            os.exec(cmd)
            return true
        end }

        if not ok then
            print(string.format("[%s] FAILED: cov_exporter execution failed", test_name))
            all_passed = false
        else
            local top_sv_output = path.join(output_dir, "top.sv")
            local top_sv_golden = path.join(golden_dir, test_name .. "_top.sv")

            local passed = true

            if not compare_file(top_sv_output, top_sv_golden, test_name .. "_top_sv") then
                passed = false
            end

            if passed then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        end

        -- Test 3: No separate always block mode
        test_count = test_count + 1
        test_name = "no_sep_always"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)

        print(string.format("\n[%s] Running cov_exporter...", test_name))
        cmd = format("cov_exporter %s -m top --ns --od %s --wd %s -q --relative-file-path", rtl, output_dir, output_dir)
        ok = try { function()
            os.exec(cmd)
            return true
        end }

        if not ok then
            print(string.format("[%s] FAILED: cov_exporter execution failed", test_name))
            all_passed = false
        else
            local top_sv_output = path.join(output_dir, "top.sv")
            local top_sv_golden = path.join(golden_dir, test_name .. "_top.sv")

            local passed = true

            if not compare_file(top_sv_output, top_sv_golden, test_name .. "_top_sv") then
                passed = false
            end

            if passed then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        end

        -- ----------------------------------------------------------------------
        -- Test 4: cond-path coverage – full golden comparison
        -- ----------------------------------------------------------------------
        test_count = test_count + 1
        test_name = "cond_path"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        local cond_rtl = path.join(test_dir, "cond_path_top.sv")

        print(string.format("\n[%s] Running cov_exporter...", test_name))
        cmd = format("cov_exporter %s -m cond_path_top --od %s --wd %s -q --relative-file-path",
            cond_rtl, output_dir, output_dir)
        ok = try { function()
            os.exec(cmd); return true
        end }

        if not ok then
            print(string.format("[%s] FAILED: cov_exporter execution failed", test_name))
            all_passed = false
        else
            local top_sv_output = path.join(output_dir, "cond_path_top.sv")
            local top_sv_golden = path.join(golden_dir, test_name .. "_top.sv")

            if compare_file(top_sv_output, top_sv_golden, test_name .. "_top_sv") then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        end

        -- ----------------------------------------------------------------------
        -- Test 5: unsupported cond-statement warnings – full golden comparison
        -- ----------------------------------------------------------------------
        test_count = test_count + 1
        test_name = "unsupported"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        local unsupported_rtl = path.join(test_dir, "cond_path_unsupported_top.sv")

        print(string.format("\n[%s] Running cov_exporter...", test_name))
        cmd = format("cov_exporter %s -m cond_path_unsupported_top --od %s --wd %s -q --relative-file-path",
            unsupported_rtl, output_dir, output_dir)
        ok = try { function()
            os.exec(cmd); return true
        end }
        if not ok then
            print(string.format("[%s] FAILED: cov_exporter execution failed", test_name))
            all_passed = false
        else
            local top_sv_output = path.join(output_dir, "cond_path_unsupported_top.sv")
            local top_sv_golden = path.join(golden_dir, test_name .. "_top.sv")

            if compare_file(top_sv_output, top_sv_golden, test_name .. "_top_sv") then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        end

        -- ----------------------------------------------------------------------
        -- Test 6: lint check — verilator --lint-only on every generated output,
        -- both with and without +define+NO_COVERAGE. A golden text-compare only
        -- proves the output is stable, not that it compiles; this catches
        -- malformed instrumentation (unbalanced `ifndef/`endif, missing decls,
        -- broken begin/end) that a diff would happily accept.
        -- ----------------------------------------------------------------------
        test_count          = test_count + 1
        test_name           = "lint"

        -- verilator must be available for lint; skip gracefully otherwise.
        local has_verilator = try { function()
            os.runv("verilator", { "--version" }); return true
        end }
        if not has_verilator then
            print("\n[lint] SKIPPED (verilator not found in PATH)")
            pass_count = pass_count + 1 -- skip counts as pass
        else
            -- (output dir name, generated file name) for each prior test that
            -- produced instrumented RTL.
            local lint_cases = {
                { ".cov_exporter_basic",          "top.sv" },
                { ".cov_exporter_disable_signal", "top.sv" },
                { ".cov_exporter_no_sep_always",  "top.sv" },
                { ".cov_exporter_cond_path",      "cond_path_top.sv" },
                { ".cov_exporter_unsupported",    "cond_path_unsupported_top.sv" },
            }

            print("\n[lint] Running verilator --lint-only on every generated output...")
            local lint_passed = true
            for _, c in ipairs(lint_cases) do
                local sv = path.join(test_dir, c[1], c[2])
                if not os.isfile(sv) then
                    print(string.format("[lint] FAILED: generated SV not found: %s", sv))
                    lint_passed = false
                else
                    -- Lint twice: instrumented (default) and stripped (NO_COVERAGE).
                    for _, defs in ipairs({ {}, { "+define+NO_COVERAGE" } }) do
                        local args = { "--lint-only", "-Wno-MULTIDRIVEN", "-Wno-WIDTHTRUNC" }
                        for _, d in ipairs(defs) do table.insert(args, d) end
                        table.insert(args, sv)
                        local lint_ok = try { function()
                            os.execv("verilator", args)
                            return true
                        end }
                        if not lint_ok then
                            print(string.format("[lint] FAILED: verilator lint errors for %s (%s)",
                                sv, #defs > 0 and "NO_COVERAGE" or "default"))
                            lint_passed = false
                        end
                    end
                end
            end
            if lint_passed then
                print("[lint] PASSED")
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        end -- has_verilator

        -- ----------------------------------------------------------------------
        -- Test 7: cov_exporter runtime overhead — instrumented vs baseline
        -- ----------------------------------------------------------------------
        -- iverilog does not support VPI the way these targets need, so it is
        -- excluded. Other simulators (verilator / vcs / xcelium) are timed.
        test_count = test_count + 1
        test_name = "overhead"
        local sim = os.getenv("SIM") or "verilator"
        local overhead_passed = true
        if sim == "iverilog" then
            print(string.format("\n[%s] SKIPPED (iverilog unsupported)", test_name))
            pass_count = pass_count + 1 -- skip counts as pass
        else
            local OVERHEAD_LIMIT_PCT = 30.0
            local RUNS = 3 -- take the minimum elapsed to reduce system noise

            -- Build + run a target, returning the minimum elapsed_ms over RUNS.
            local function measure(target_name)
                local bok = try { function()
                    os.execv("xmake", { "build", "-P", test_dir, target_name }, { envs = { SIM = sim } })
                    return true
                end }
                if not bok then
                    print(string.format("[%s] FAILED: build of %s failed", test_name, target_name))
                    return nil
                end
                local best = nil
                for _ = 1, RUNS do
                    local out = nil
                    local rok = try { function()
                        out = os.iorun(format("xmake run -P %s %s", test_dir, target_name))
                        return true
                    end }
                    if not rok or not out then
                        print(string.format("[%s] FAILED: run of %s failed", test_name, target_name))
                        return nil
                    end
                    local ms = out:match("%[cov_overhead%] elapsed_ms:%s*([%d%.]+)")
                    if not ms then
                        print(string.format("[%s] FAILED: no elapsed_ms in %s output", test_name, target_name))
                        return nil
                    end
                    local v = tonumber(ms)
                    if not best or v < best then best = v end
                end
                return best
            end

            print(string.format("\n[%s] Measuring cov_exporter overhead (sim=%s, limit<=%.0f%%)...",
                test_name, sim, OVERHEAD_LIMIT_PCT))
            local base_ms = measure("cov_overhead_baseline")
            local inst_ms = base_ms and measure("cov_overhead_instrumented") or nil

            if not base_ms or not inst_ms then
                overhead_passed = false
            else
                local overhead_pct = (inst_ms - base_ms) / base_ms * 100.0
                print(string.format("[%s] baseline=%.1f ms  instrumented=%.1f ms  overhead=%.1f%%",
                    test_name, base_ms, inst_ms, overhead_pct))
                if overhead_pct > OVERHEAD_LIMIT_PCT then
                    print(string.format("[%s] FAILED: overhead %.1f%% exceeds %.0f%% limit",
                        test_name, overhead_pct, OVERHEAD_LIMIT_PCT))
                    overhead_passed = false
                else
                    print(string.format("[%s] PASSED", test_name))
                end
            end
            if overhead_passed then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        end

        -- Print summary
        print("\n" .. string.rep("=", 60))
        print(string.format("Test Summary: %d/%d passed", pass_count, test_count))
        print(string.rep("=", 60))

        if not all_passed then
            raise("Some tests failed!")
        end
    end)
end)

target("regen_golden", function()
    set_kind("phony")
    set_default(false)
    on_run(function(target)
        local test_dir = os.scriptdir()
        local golden_dir = path.join(test_dir, "golden")
        local rtl = path.join(test_dir, "top.sv")

        -- Create golden directory if not exists
        os.mkdir(golden_dir)

        print("Regenerating golden files...")

        -- Test 1: Basic module coverage
        local test_name = "basic"
        local output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        print(string.format("[%s] Generating golden file...", test_name))
        local cmd = format("cov_exporter %s -m top --od %s --wd %s -q --relative-file-path", rtl, output_dir, output_dir)
        os.exec(cmd)
        os.cp(path.join(output_dir, "top.sv"), path.join(golden_dir, test_name .. "_top.sv"))

        -- Test 2: With disable signal pattern
        test_name = "disable_signal"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        print(string.format("[%s] Generating golden file...", test_name))
        cmd = format("cov_exporter %s -m top --ds top:counter --od %s --wd %s -q --relative-file-path", rtl, output_dir,
            output_dir)
        os.exec(cmd)
        os.cp(path.join(output_dir, "top.sv"), path.join(golden_dir, test_name .. "_top.sv"))

        -- Test 3: No separate always block mode
        test_name = "no_sep_always"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        print(string.format("[%s] Generating golden file...", test_name))
        cmd = format("cov_exporter %s -m top --ns --od %s --wd %s -q --relative-file-path", rtl, output_dir, output_dir)
        os.exec(cmd)
        os.cp(path.join(output_dir, "top.sv"), path.join(golden_dir, test_name .. "_top.sv"))

        -- Test 4: cond-path coverage
        test_name = "cond_path"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        print(string.format("[%s] Generating golden file...", test_name))
        cmd = format("cov_exporter %s -m cond_path_top --od %s --wd %s -q --relative-file-path",
            path.join(test_dir, "cond_path_top.sv"), output_dir, output_dir)
        os.exec(cmd)
        os.cp(path.join(output_dir, "cond_path_top.sv"), path.join(golden_dir, test_name .. "_top.sv"))

        -- Test 5: unsupported cond-statement warnings
        test_name = "unsupported"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        print(string.format("[%s] Generating golden file...", test_name))
        cmd = format("cov_exporter %s -m cond_path_unsupported_top --od %s --wd %s -q --relative-file-path",
            path.join(test_dir, "cond_path_unsupported_top.sv"), output_dir, output_dir)
        os.exec(cmd)
        os.cp(path.join(output_dir, "cond_path_unsupported_top.sv"), path.join(golden_dir, test_name .. "_top.sv"))

        print("\nGolden files regenerated successfully!")
        print("Golden files location: " .. golden_dir)
    end)
end)

-- ----------------------------------------------------------------------
-- cov_exporter runtime-overhead targets (driven by the `overhead` test
-- case in the `test` target above). Two builds of the same DUT/stimulus:
--   cov_overhead_baseline      : no instrumentation
--   cov_overhead_instrumented  : cov_exporter applied
-- ----------------------------------------------------------------------
local cov_bench_rtl = path.join(os.scriptdir(), "cov_bench_top.sv")
local cov_overhead_lua = path.join(os.scriptdir(), "cov_overhead.lua")

target("cov_overhead_baseline", function()
    add_rules("verilua")
    set_default(false)
    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        else
            target:set("toolchains", "@verilator")
        end
    end)
    add_files(cov_bench_rtl)
    set_values("verilua.top", "cov_bench_top")
    set_values("verilua.build_dir_name", "cov_overhead_baseline")
    set_values("verilua.lua_main", cov_overhead_lua)
    add_values("verilator.flags", "--Wno-MULTIDRIVEN")
end)

target("cov_overhead_instrumented", function()
    add_rules("verilua")
    set_default(false)
    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        else
            target:set("toolchains", "@verilator")
        end
    end)
    add_files(cov_bench_rtl)
    set_values("verilua.top", "cov_bench_top")
    set_values("verilua.build_dir_name", "cov_overhead_instrumented")
    set_values("verilua.lua_main", cov_overhead_lua)
    add_values("verilator.flags", "--Wno-MULTIDRIVEN")
    set_values("verilua.instrument", function()
        return {
            {
                type = "cov_exporter",
                config = { { module = "cov_bench_top" } },
            },
        }
    end)
end)

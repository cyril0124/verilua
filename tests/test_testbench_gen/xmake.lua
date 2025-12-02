---@diagnostic disable: undefined-global, undefined-field

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
        -- Helper function to compare testbench output with golden file using diff
        local function compare_testbench(output_file, golden_file, test_name)
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
        local build_dir = path.join(test_dir, "build")
        local all_passed = true
        local test_count = 0
        local pass_count = 0

        print("=" .. string.rep("=", 60))
        print("Running testbench_gen tests...")
        print("=" .. string.rep("=", 60))

        -- Test top_ansi.sv
        test_count = test_count + 1
        local ansi_rtl = path.join(test_dir, "top_ansi.sv")
        local ansi_output = path.join(build_dir, "tb_top.sv")
        local ansi_golden = path.join(golden_dir, "top_ansi_tb_top.sv")

        print("\n[ansi] Running testbench_gen for top_ansi.sv...")
        local ok = try { function()
            os.exec("testbench_gen %s --out-dir %s --regen --verbose --check-output", ansi_rtl, build_dir)
            return true
        end }
        if ok then
            print("[ansi] testbench_gen PASSED")
            -- Compare with golden file if exists
            if compare_testbench(ansi_output, ansi_golden, "ansi_golden") then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        else
            print("[ansi] FAILED: testbench_gen execution failed")
            all_passed = false
        end

        -- Test top_non_ansi.sv
        test_count = test_count + 1
        local non_ansi_rtl = path.join(test_dir, "top_non_ansi.sv")
        local non_ansi_output = path.join(build_dir, "tb_top.sv")
        local non_ansi_golden = path.join(golden_dir, "top_non_ansi_tb_top.sv")

        print("\n[non_ansi] Running testbench_gen for top_non_ansi.sv...")
        local ok2 = try { function()
            os.exec("testbench_gen %s --out-dir %s --regen --verbose --check-output", non_ansi_rtl, build_dir)
            return true
        end }
        if ok2 then
            print("[non_ansi] testbench_gen PASSED")
            -- Compare with golden file if exists
            if compare_testbench(non_ansi_output, non_ansi_golden, "non_ansi_golden") then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        else
            print("[non_ansi] FAILED: testbench_gen execution failed")
            all_passed = false
        end

        -- Test top_clock_variants.sv (clock/reset smart detection)
        test_count = test_count + 1
        local clock_variants_rtl = path.join(test_dir, "top_clock_variants.sv")
        local clock_variants_output = path.join(build_dir, "tb_top.sv")
        local clock_variants_golden = path.join(golden_dir, "top_clock_variants_tb_top.sv")

        print("\n[clock_variants] Running testbench_gen for top_clock_variants.sv...")
        local ok3 = try { function()
            os.exec("testbench_gen %s --out-dir %s --regen --verbose --check-output", clock_variants_rtl, build_dir)
            return true
        end }
        if ok3 then
            print("[clock_variants] testbench_gen PASSED")
            -- Compare with golden file if exists
            if compare_testbench(clock_variants_output, clock_variants_golden, "clock_variants_golden") then
                pass_count = pass_count + 1
            else
                all_passed = false
            end
        else
            print("[clock_variants] FAILED: testbench_gen execution failed")
            all_passed = false
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
        local build_dir = path.join(test_dir, "build")

        -- Create golden directory if not exists
        os.mkdir(golden_dir)

        print("Regenerating golden files...")

        -- Generate golden for top_ansi.sv
        local ansi_rtl = path.join(test_dir, "top_ansi.sv")
        print("[ansi] Generating golden file...")
        os.exec("testbench_gen %s --out-dir %s --regen --check-output", ansi_rtl, build_dir)
        os.cp(path.join(build_dir, "tb_top.sv"), path.join(golden_dir, "top_ansi_tb_top.sv"))

        -- Generate golden for top_non_ansi.sv
        local non_ansi_rtl = path.join(test_dir, "top_non_ansi.sv")
        print("[non_ansi] Generating golden file...")
        os.exec("testbench_gen %s --out-dir %s --regen --check-output", non_ansi_rtl, build_dir)
        os.cp(path.join(build_dir, "tb_top.sv"), path.join(golden_dir, "top_non_ansi_tb_top.sv"))

        -- Generate golden for top_clock_variants.sv
        local clock_variants_rtl = path.join(test_dir, "top_clock_variants.sv")
        print("[clock_variants] Generating golden file...")
        os.exec("testbench_gen %s --out-dir %s --regen --check-output", clock_variants_rtl, build_dir)
        os.cp(path.join(build_dir, "tb_top.sv"), path.join(golden_dir, "top_clock_variants_tb_top.sv"))

        print("\nGolden files regenerated successfully!")
        print("  - " .. path.join(golden_dir, "top_ansi_tb_top.sv"))
        print("  - " .. path.join(golden_dir, "top_non_ansi_tb_top.sv"))
        print("  - " .. path.join(golden_dir, "top_clock_variants_tb_top.sv"))
    end)
end)

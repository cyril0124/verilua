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
        local cmd = format("cov_exporter %s -m top --od %s --wd %s -q", rtl, output_dir, output_dir)
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
            local meta_golden = path.join(golden_dir, test_name .. "_meta.json")

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
        cmd = format("cov_exporter %s -m top --ds top:counter --od %s --wd %s -q", rtl, output_dir, output_dir)
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
        cmd = format("cov_exporter %s -m top --ns --od %s --wd %s -q", rtl, output_dir, output_dir)
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
        local cmd = format("cov_exporter %s -m top --od %s --wd %s -q", rtl, output_dir, output_dir)
        os.exec(cmd)
        os.cp(path.join(output_dir, "top.sv"), path.join(golden_dir, test_name .. "_top.sv"))

        -- Test 2: With disable signal pattern
        test_name = "disable_signal"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        print(string.format("[%s] Generating golden file...", test_name))
        cmd = format("cov_exporter %s -m top --ds top:counter --od %s --wd %s -q", rtl, output_dir, output_dir)
        os.exec(cmd)
        os.cp(path.join(output_dir, "top.sv"), path.join(golden_dir, test_name .. "_top.sv"))

        -- Test 3: No separate always block mode
        test_name = "no_sep_always"
        output_dir = path.join(test_dir, ".cov_exporter_" .. test_name)
        print(string.format("[%s] Generating golden file...", test_name))
        cmd = format("cov_exporter %s -m top --ns --od %s --wd %s -q", rtl, output_dir, output_dir)
        os.exec(cmd)
        os.cp(path.join(output_dir, "top.sv"), path.join(golden_dir, test_name .. "_top.sv"))

        print("\nGolden files regenerated successfully!")
        print("Golden files location: " .. golden_dir)
    end)
end)

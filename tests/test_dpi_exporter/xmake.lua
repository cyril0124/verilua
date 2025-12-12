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
        print("Running dpi_exporter tests...")
        print("=" .. string.rep("=", 60))

        -- Test each config file
        local cfgs = os.files(path.join(test_dir, "dpi_cfgs", "*.lua"))
        for _, cfg in ipairs(cfgs) do
            local cfg_name = path.basename(cfg):gsub("%.lua$", "")
            local output_dir = path.join(test_dir, ".dpi_exporter_" .. cfg_name)

            test_count = test_count + 1

            -- Run dpi_exporter
            print(string.format("\n[%s] Running dpi_exporter...", cfg_name))
            local cmd = format("dpi_exporter %s -c %s --no-cache -q --od %s --wd %s", rtl, cfg, output_dir, output_dir)
            local ok = try { function()
                os.exec(cmd)
                return true
            end }

            if not ok then
                print(string.format("[%s] FAILED: dpi_exporter execution failed", cfg_name))
                all_passed = false
            else
                -- Compare generated files with golden files
                local dpi_func_output = path.join(output_dir, "dpi_func.cpp")
                local dpi_func_golden = path.join(golden_dir, cfg_name .. "_dpi_func.cpp")

                local top_sv_output = path.join(output_dir, "top.sv")
                local top_sv_golden = path.join(golden_dir, cfg_name .. "_top.sv")

                local passed = true

                -- Compare dpi_func.cpp
                if not compare_file(dpi_func_output, dpi_func_golden, cfg_name .. "_dpi_func") then
                    passed = false
                end

                -- Compare top.sv
                if not compare_file(top_sv_output, top_sv_golden, cfg_name .. "_top_sv") then
                    passed = false
                end

                if passed then
                    pass_count = pass_count + 1
                else
                    all_passed = false
                end
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

        local cfgs = os.files(path.join(test_dir, "dpi_cfgs", "*.lua"))
        for _, cfg in ipairs(cfgs) do
            local cfg_name = path.basename(cfg):gsub("%.lua$", "")
            local output_dir = path.join(test_dir, ".dpi_exporter_" .. cfg_name)

            print(string.format("[%s] Generating golden file...", cfg_name))
            local cmd = format("dpi_exporter %s -c %s --no-cache -q --od %s --wd %s", rtl, cfg, output_dir, output_dir)
            os.exec(cmd)

            -- Copy generated files to golden directory
            os.cp(path.join(output_dir, "dpi_func.cpp"), path.join(golden_dir, cfg_name .. "_dpi_func.cpp"))
            os.cp(path.join(output_dir, "top.sv"), path.join(golden_dir, cfg_name .. "_top.sv"))
        end

        print("\nGolden files regenerated successfully!")
        print("Golden files location: " .. golden_dir)
    end)
end)

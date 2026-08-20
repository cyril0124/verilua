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
            local cmd = format("dpi_exporter %s -c %s --no-cache -q --od %s --wd %s --relative-meta-path", rtl, cfg,
                output_dir, output_dir)
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

                -- public.vlt: golden-compared when expected; unexpected generation fails
                local vlt_output = path.join(output_dir, "dpi_exporter.public.vlt")
                local vlt_golden = path.join(golden_dir, cfg_name .. "_public.vlt")
                if os.isfile(vlt_golden) then
                    if not compare_file(vlt_output, vlt_golden, cfg_name .. "_public_vlt") then
                        passed = false
                    end
                elseif os.isfile(vlt_output) then
                    print(string.format("[%s] FAILED: unexpected %s (no golden)", cfg_name, vlt_output))
                    passed = false
                end

                -- Meta must carry static signal infos (no exportedSignals list)
                local meta_output = path.join(output_dir, "dpi_exporter.meta.json")
                if not os.isfile(meta_output) then
                    print(string.format("[%s] FAILED: meta not found: %s", cfg_name, meta_output))
                    passed = false
                else
                    local meta_content = io.readfile(meta_output)
                    if not meta_content:find('"exportedSignalInfos"', 1, true) then
                        print(string.format("[%s] FAILED: meta missing exportedSignalInfos", cfg_name))
                        passed = false
                    elseif meta_content:find('"exportedSignals"', 1, true) then
                        print(string.format("[%s] FAILED: meta still has exportedSignals (removed)", cfg_name))
                        passed = false
                    elseif not meta_content:find('"hierPath"', 1, true)
                        or not meta_content:find('"bitWidth"', 1, true)
                        or not meta_content:find('"vpiTypeStr"', 1, true)
                        or not meta_content:find('"handleId"', 1, true)
                        or not meta_content:find('"metaOnly"', 1, true) then
                        print(string.format("[%s] FAILED: meta infos missing required fields", cfg_name))
                        passed = false
                    else
                        print(string.format("[%s] PASSED (meta exportedSignalInfos)", cfg_name))
                    end
                end

                if passed then
                    pass_count = pass_count + 1
                else
                    all_passed = false
                end
            end
        end

        -- Inline --config-str must match the only_default golden (file vs str equivalence).
        -- Reuse only_default outdir so --relative-meta-path embeds the same path as golden.
        do
            local cfg_name = "only_default_config_str"
            local cfg_path = path.join(test_dir, "dpi_cfgs", "only_default.lua")
            local output_dir = path.join(test_dir, ".dpi_exporter_only_default")
            local cfg_content = io.readfile(cfg_path)
            test_count = test_count + 1

            print(string.format("\n[%s] Running dpi_exporter with --config-str...", cfg_name))
            local ok = try { function()
                os.execv("dpi_exporter", {
                    rtl,
                    "--config-str", cfg_content,
                    "--no-cache", "-q",
                    "--od", output_dir,
                    "--wd", output_dir,
                    "--relative-meta-path",
                })
                return true
            end }

            if not ok then
                print(string.format("[%s] FAILED: dpi_exporter execution failed", cfg_name))
                all_passed = false
            else
                local passed = true
                if not compare_file(path.join(output_dir, "dpi_func.cpp"),
                        path.join(golden_dir, "only_default_dpi_func.cpp"),
                        cfg_name .. "_dpi_func") then
                    passed = false
                end
                if not compare_file(path.join(output_dir, "top.sv"),
                        path.join(golden_dir, "only_default_top.sv"),
                        cfg_name .. "_top_sv") then
                    passed = false
                end
                if passed then
                    pass_count = pass_count + 1
                else
                    all_passed = false
                end
            end
        end

        -- Same-group conflict: meta_only + sensitive_signals must be rejected
        -- by the config layer with a clear message.
        do
            local cfg_name = "meta_only_sensitive_conflict"
            local output_dir = path.join(test_dir, ".dpi_exporter_" .. cfg_name)
            test_count = test_count + 1

            print(string.format("\n[%s] Running dpi_exporter (expected to fail)...", cfg_name))
            local conflict_cfg =
            'add_pattern { module = "B", signals = "(i_.*)|(.*valid)", sensitive_signals = ".*valid", meta_only = true }'
            local out_file = os.tmpfile()
            local err_file = os.tmpfile()
            local code = os.execv("dpi_exporter", {
                rtl,
                "--config-str", conflict_cfg,
                "--no-cache", "-q",
                "--od", output_dir,
                "--wd", output_dir,
            }, { try = true, stdout = out_file, stderr = err_file })
            local output = (io.readfile(out_file) or "") .. (io.readfile(err_file) or "")
            os.tryrm(out_file)
            os.tryrm(err_file)

            if code == 0 then
                print(string.format("[%s] FAILED: conflicting cfg unexpectedly succeeded", cfg_name))
                all_passed = false
            elseif not output:find("meta_only cannot be used with sensitive_signals", 1, true) then
                print(string.format("[%s] FAILED: unexpected error message:", cfg_name))
                print(output)
                all_passed = false
            else
                print(string.format("[%s] PASSED (rejected with clear message)", cfg_name))
                pass_count = pass_count + 1
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
            local cmd = format("dpi_exporter %s -c %s --no-cache -q --od %s --wd %s --relative-meta-path", rtl, cfg,
                output_dir, output_dir)
            os.exec(cmd)

            -- Copy generated files to golden directory
            os.cp(path.join(output_dir, "dpi_func.cpp"), path.join(golden_dir, cfg_name .. "_dpi_func.cpp"))
            os.cp(path.join(output_dir, "top.sv"), path.join(golden_dir, cfg_name .. "_top.sv"))

            -- meta_only cfgs also produce a public vlt
            local vlt_output = path.join(output_dir, "dpi_exporter.public.vlt")
            if os.isfile(vlt_output) then
                os.cp(vlt_output, path.join(golden_dir, cfg_name .. "_public.vlt"))
            end
        end

        print("\nGolden files regenerated successfully!")
        print("Golden files location: " .. golden_dir)
    end)
end)

---@diagnostic disable: undefined-global, undefined-field

local prj_dir = os.projectdir()
local wtype = os.getenv("WTYPE") or "fst"

target("gen_wave", function()
    set_default(false)
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "verilator" then
            target:set("toolchains", "@verilator")
            target:add("values", "verilator.flags", "--trace", "--trace-fst")
        elseif sim == "iverilog" then
            target:set("toolchains", "@iverilog")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    after_run(function()
        local sim = os.getenv("SIM") or "verilator"
        if sim == "verilator" then
            assert(os.isfile("test.fst"), "test.fst not found")
            os.cp("test.fst", prj_dir)
        elseif sim == "iverilog" then
            assert(os.isfile("test.vcd"), "test.vcd not found")
            os.cp("test.vcd", prj_dir)
        elseif sim == "vcs" then
            assert(os.isfile("test.vcd.fsdb"), "test.vcd.fsdb not found")
            os.cp("test.vcd.fsdb", prj_dir)
        end
    end)

    add_files("./top.sv")
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "gen_wave_main.lua")
end)

target("sim_wave", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")

    if wtype == "fst" then
        add_files("./test.fst")
    elseif wtype == "vcd" then
        add_files("./test.vcd")
    elseif wtype == "fsdb" then
        add_files("./test.vcd.fsdb")
    else
        raise("unknown WTYPE: %s", wtype)
    end

    set_values("cfg.top", "tb_top")
    set_values("cfg.lua_main", "sim_wave_main.lua")
end)

target("run_test", function()
    set_default(true)
    set_kind("phony")

    on_run(function()
        local function split_lines(text)
            local lines = {}
            for line in (text .. "\n"):gmatch("(.-)\n") do
                line = line:gsub("\r$", "")
                table.insert(lines, line)
            end
            if #lines > 0 and lines[#lines] == "" then
                table.remove(lines, #lines)
            end
            return lines
        end

        local function build_mismatch_message(expected_lines, actual_lines, golden_file)
            local max_lines = math.max(#expected_lines, #actual_lines)
            for i = 1, max_lines do
                local exp_line = expected_lines[i]
                local act_line = actual_lines[i]
                if exp_line ~= act_line then
                    return string.format(
                        "golden output mismatch for %s at line %d\nexpected: %s\nactual:   %s",
                        golden_file,
                        i,
                        tostring(exp_line),
                        tostring(act_line)
                    )
                end
            end
            return "golden output mismatch for " .. golden_file
        end

        local function run_case(sim, wave_type, expected_marker, golden_file)
            local gen_report_file = path.join(prj_dir, ".module_name_gen_report.log")
            local sim_report_file = path.join(prj_dir, ".module_name_sim_report.log")

            os.setenv("SIM", sim)
            os.setenv("MODULE_NAME_REPORT_FILE", gen_report_file)
            os.exec("xmake b -P . gen_wave")
            local gen_output = os.iorun("xmake r -P . gen_wave")
            print(gen_output)
            local gen_expected_marker = string.format("[module_name_gen_test] PASS %s", sim)
            assert(
                gen_output:find(gen_expected_marker, 1, true) ~= nil,
                string.format("missing marker `%s` for gen_wave sim=%s", gen_expected_marker, sim)
            )

            os.setenv("WTYPE", wave_type)
            os.setenv("MODULE_NAME_REPORT_FILE", sim_report_file)
            os.exec("xmake b -P . sim_wave")
            local sim_output = os.iorun("xmake r -P . sim_wave")
            print(sim_output)

            assert(
                sim_output:find(expected_marker, 1, true) ~= nil,
                string.format("missing marker `%s` for case sim=%s wave=%s", expected_marker, sim, wave_type)
            )

            os.setenv("MODULE_NAME_REPORT_FILE", "")

            local golden_expected = io.readfile(prj_dir .. "/" .. golden_file)
            assert(golden_expected ~= nil, "golden file not found: " .. golden_file)
            local gen_report = io.readfile(gen_report_file)
            assert(gen_report ~= nil, "gen report file not found: " .. gen_report_file)
            local sim_report = io.readfile(sim_report_file)
            assert(sim_report ~= nil, "sim report file not found: " .. sim_report_file)

            local expected_lines = split_lines(golden_expected)
            local actual_lines = { "[gen_wave]" }
            for _, line in ipairs(split_lines(gen_report)) do
                table.insert(actual_lines, line)
            end
            table.insert(actual_lines, "[sim_wave]")
            for _, line in ipairs(split_lines(sim_report)) do
                table.insert(actual_lines, line)
            end

            if #actual_lines ~= #expected_lines then
                assert(false, build_mismatch_message(expected_lines, actual_lines, golden_file))
            end
            for i = 1, #expected_lines do
                if expected_lines[i] ~= actual_lines[i] then
                    assert(false, build_mismatch_message(expected_lines, actual_lines, golden_file))
                end
            end
        end

        run_case("verilator", "fst", "[module_name_test] PASS fst", "sim_wave_fst.golden")

        import("lib.detect.find_file")
        if find_file("iverilog", { "$(env PATH)" }) then
            run_case("iverilog", "vcd", "[module_name_test] PASS vcd", "sim_wave_vcd.golden")
        else
            cprint("${yellow}[WARN] skip vcd case: iverilog not found${clear}")
        end

        if find_file("vcs", { "$(env PATH)" }) and find_file("verdi", { "$(env PATH)" }) and os.getenv("VERDI_HOME") then
            run_case("vcs", "fsdb", "[module_name_test] PASS fsdb", "sim_wave_fsdb.golden")
        else
            cprint("${yellow}[WARN] skip fsdb case: vcs/verdi not found${clear}")
        end
    end)
end)

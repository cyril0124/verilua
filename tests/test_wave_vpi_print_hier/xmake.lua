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
        local function normalize_text(text)
            text = text:gsub("\r\n", "\n")
            text = text:gsub("[ \t]+\n", "\n")
            text = text:gsub("\n+$", "\n")
            return text
        end

        local function split_lines(text)
            local lines = {}
            for line in (text .. "\n"):gmatch("(.-)\n") do
                table.insert(lines, line)
            end
            return lines
        end

        local function build_mismatch_message(expected, actual, golden_file)
            local expected_lines = split_lines(expected)
            local actual_lines = split_lines(actual)
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

        local function assert_contains_snippets(text, snippets, context)
            for _, snippet in ipairs(snippets) do
                assert(
                    text:find(snippet, 1, true) ~= nil,
                    string.format("%s missing snippet: %s", context, snippet)
                )
            end
        end

        local function extract_get_hierarchy_subset(text)
            local lines = {}
            for line in (normalize_text(text) .. "\n"):gmatch("(.-)\n") do
                if line == "[gen_wave]" or line == "[sim_wave]" or line:find("get_hierarchy", 1, true) then
                    table.insert(lines, line)
                end
            end
            return table.concat(lines, "\n") .. "\n"
        end

        local function extract_between(text, begin_mark, end_mark)
            local begin_pos = text:find(begin_mark, 1, true)
            assert(begin_pos ~= nil, "missing begin marker: " .. begin_mark)
            local content_start = begin_pos + #begin_mark
            local end_pos = text:find(end_mark, content_start + 1, true)
            assert(end_pos ~= nil, "missing end marker: " .. end_mark)
            local content = text:sub(content_start, end_pos - 1)
            if content:sub(1, 1) == "\n" then
                content = content:sub(2)
            end
            if content:sub(-1) == "\n" then
                content = content:sub(1, -2)
            end
            return content
        end

        local function run_case(sim, wave_type, golden_file)
            os.setenv("SIM", sim)
            os.exec("xmake b -P . gen_wave")
            local gen_output = os.iorun("xmake r -P . gen_wave")
            print(gen_output)
            local gen_golden_section = extract_between(gen_output, "[golden_gen] begin", "[golden_gen] end")

            os.setenv("WTYPE", wave_type)
            os.exec("xmake b -P . sim_wave")
            local sim_output = os.iorun("xmake r -P . sim_wave")
            print(sim_output)
            local sim_golden_section = extract_between(sim_output, "[golden] begin", "[golden] end")

            assert_contains_snippets(gen_golden_section, {
                "[print_hierarchy] max_level=3 style=tree",
                "[print_hierarchy] max_level=3 style=tree show_bitwidth=true",
                "tb_top",
                "|-- u_top",
                "|   |-- u_mid",
                "|-- u_others",
            }, "gen_wave hierarchy output")
            assert_contains_snippets(sim_golden_section, {
                "[print_hierarchy] max_level=3 style=tree",
                "[print_hierarchy] max_level=1 style=tree",
                "[print_hierarchy] max_level=3 style=tree wildcard=*u_mid",
                "[print_hierarchy] max_level=4 style=tree wildcard=*clock",
                "[print_hierarchy] max_level=3 style=tree show_bitwidth=true",
                "tb_top",
                "|-- u_top",
                "|-- u_others",
                "|   |-- u_mid",
                "|   |   |-- u_leaf",
                "(width: 1)",
                "(width: 8)",
            }, "sim_wave hierarchy output")

            local golden_section = string.format("[gen_wave]\n%s\n\n[sim_wave]\n%s\n", gen_golden_section,
                sim_golden_section)
            local golden_expected = io.readfile(prj_dir .. "/" .. golden_file)
            assert(golden_expected ~= nil, "golden file not found: " .. golden_file)
            local actual_subset = extract_get_hierarchy_subset(golden_section)
            local expected_subset = extract_get_hierarchy_subset(golden_expected)
            if actual_subset ~= expected_subset then
                assert(false,
                    build_mismatch_message(expected_subset, actual_subset, golden_file .. " (get_hierarchy subset)"))
            end
        end

        run_case("verilator", "fst", "sim_wave.golden")

        import("lib.detect.find_file")
        if find_file("vcs", { "$(env PATH)" }) and find_file("verdi", { "$(env PATH)" }) and os.getenv("VERDI_HOME") then
            run_case("vcs", "fsdb", "sim_wave_fsdb.golden")
        else
            cprint("${yellow}[WARN] skip fsdb golden case: vcs/verdi not found${clear}")
        end
    end)
end)

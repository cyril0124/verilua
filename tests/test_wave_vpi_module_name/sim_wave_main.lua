local table_sort = table.sort
local table_concat = table.concat
local ONLY_FSDB_SUBSTR = "only supported for FSDB waveform in wave_vpi backend"
local known_sig_types = { "wire", "reg" }
local report_file = os.getenv("MODULE_NAME_REPORT_FILE")
local report_lines = {}

local function emit_line(line)
    print(line)
    if report_file ~= nil and report_file ~= "" then
        report_lines[#report_lines + 1] = line
    end
end

local function flush_report()
    if report_file == nil or report_file == "" then
        return
    end

    local file, err = io.open(report_file, "w")
    assert(file, "[module_name_test] failed to write report file: " .. tostring(err))
    for _, line in ipairs(report_lines) do
        file:write(line, "\n")
    end
    file:close()
end

local function extract_hierarchy_lines(captured_lines)
    local lines = {}
    for _, line in ipairs(captured_lines) do
        if line:find("[print_hierarchy]", 1, true) == 1 or line:find("tb_top", 1, true) == 1 or line:find("|", 1, true) == 1 then
            lines[#lines + 1] = line
        end
    end
    return lines
end

local function extract_sig_type(captured_lines)
    for _, line in ipairs(captured_lines) do
        for _, sig_type in ipairs(known_sig_types) do
            if line:find("(" .. sig_type .. ")", 1, true) then
                return sig_type
            end
        end
    end
    return nil
end

local function sort_and_print_paths(tag, paths)
    table_sort(paths)
    emit_line(string.format("[%s_count] %d", tag, #paths))
    for _, path in ipairs(paths) do
        emit_line(string.format("[%s] %s", tag, path))
    end
end

local function assert_paths_equal(tag, got, expected)
    table_sort(got)
    table_sort(expected)
    assert(#got == #expected, string.format("[%s] expected %d paths, got %d", tag, #expected, #got))
    for i = 1, #expected do
        assert(
            got[i] == expected[i],
            string.format("[%s] path mismatch at index %d, expected=%s got=%s", tag, i, expected[i], tostring(got[i]))
        )
    end
    sort_and_print_paths(tag, got)
end

local function expect_error(tag, fn, expected_substr)
    local ok, err = pcall(fn)
    assert(not ok, string.format("[%s] expected error, but succeeded", tag))
    local err_str = tostring(err)
    assert(
        err_str:find(expected_substr, 1, true) ~= nil,
        string.format("[%s] unexpected error message: %s", tag, err_str)
    )
    emit_line(string.format("[%s] matched_expected_error", tag))
end

local function capture_print(fn)
    local old_print = rawget(_G, "print")
    local captured = {}
    rawset(_G, "print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        local line = table_concat(parts, " ")
        captured[#captured + 1] = line
        old_print(...)
    end)

    local ok, err = pcall(fn)
    rawset(_G, "print", old_print)
    assert(ok, tostring(err))
    return captured
end

local function run_show_sig_type_checks(wtype)
    local function run_sig_type_case(case_tag, wildcard, expected_sig_type)
        local paths = sim.get_hierarchy {
            wildcard = wildcard,
            show_sig_type = true,
        }
        assert(#paths > 0, string.format("[%s_paths] expected non-empty result", case_tag))
        for _, path in ipairs(paths) do
            assert(
                extract_sig_type { path } == expected_sig_type,
                string.format("[%s_paths] expected `%s` suffix", case_tag, expected_sig_type)
            )
        end
        sort_and_print_paths(case_tag .. "_paths", paths)

        emit_line("[" .. case_tag .. "_tree_begin]")
        local captured = capture_print(function()
            sim.print_hierarchy {
                max_level = 4,
                wildcard = wildcard,
                show_sig_type = true,
            }
        end)
        for _, line in ipairs(extract_hierarchy_lines(captured)) do
            emit_line(line)
        end
        emit_line("[" .. case_tag .. "_tree_end]")

        local detected_sig_type = extract_sig_type(captured)
        assert(detected_sig_type == expected_sig_type, string.format("[%s] expected `%s`", case_tag, expected_sig_type))
        emit_line("[" .. case_tag .. "_contains] " .. detected_sig_type)
    end

    local expected_data_sig_type = (wtype == "fst") and "wire" or "reg"
    run_sig_type_case("show_sig_type", "*u_mid_a.data", expected_data_sig_type)
    run_sig_type_case("show_sig_type_wire", "*u_mid_a.leaf_data", "wire")
end

local function run_multi_wildcard_checks()
    local multi_wild_paths = sim.get_hierarchy {
        wildcard = "*u_mid_a.data,*u_mid_b.data",
    }
    assert(#multi_wild_paths >= 2, "[multi_wild_paths] expected at least two paths")
    local has_mid_a_data = false
    local has_mid_b_data = false
    for _, path in ipairs(multi_wild_paths) do
        if path == "tb_top.u_top.u_mid_a.data" then
            has_mid_a_data = true
        elseif path == "tb_top.u_top.u_mid_b.data" then
            has_mid_b_data = true
        end
    end
    assert(has_mid_a_data and has_mid_b_data, "[multi_wild_paths] expected both u_mid_a.data and u_mid_b.data")
    sort_and_print_paths("multi_wild_paths", multi_wild_paths)

    emit_line("[multi_wild_tree_begin]")
    local captured_multi_wild = capture_print(function()
        sim.print_hierarchy {
            max_level = 4,
            wildcard = "*u_mid_a.data,*u_mid_b.data",
        }
    end)
    for _, line in ipairs(extract_hierarchy_lines(captured_multi_wild)) do
        emit_line(line)
    end
    emit_line("[multi_wild_tree_end]")

    local has_mid_a_tree = false
    local has_mid_b_tree = false
    for _, line in ipairs(captured_multi_wild) do
        if line:find("u_mid_a", 1, true) then
            has_mid_a_tree = true
        end
        if line:find("u_mid_b", 1, true) then
            has_mid_b_tree = true
        end
    end
    assert(has_mid_a_tree and has_mid_b_tree, "[multi_wild_tree] expected both u_mid_a and u_mid_b in output")
    emit_line("[multi_wild_contains] u_mid_a,u_mid_b")
end

fork {
    function()
        local wtype = os.getenv("WTYPE") or "fst"
        emit_line("[module_name_test] begin")

        if wtype ~= "fsdb" then
            expect_error(wtype .. "_module_name_error", function()
                sim.get_hierarchy { module_name = "MidMod" }
            end, ONLY_FSDB_SUBSTR)
            expect_error(wtype .. "_show_def_name_error", function()
                sim.print_hierarchy { show_def_name = true }
            end, ONLY_FSDB_SUBSTR)

            run_multi_wildcard_checks()
            run_show_sig_type_checks(wtype)

            emit_line("[module_name_test] PASS " .. wtype)
            emit_line("[module_name_test] end")
            flush_report()
            sim.finish()
            return
        end

        local mid_paths = sim.get_hierarchy { module_name = "MidMod" }
        assert_paths_equal("mid_paths", mid_paths, {
            "tb_top.u_top.u_mid_a",
            "tb_top.u_top.u_mid_b",
            "tb_top.u_top.u_mid_out",
        })

        local mid_wild_paths = sim.get_hierarchy {
            wildcard = "*u_mid_a*",
            module_name = "MidMod",
        }
        assert_paths_equal("mid_wild_paths", mid_wild_paths, {
            "tb_top.u_top.u_mid_a",
        })

        local leaf_wild_paths = sim.get_hierarchy {
            wildcard = "*u_leaf*",
            module_name = "LeafMod",
        }
        assert_paths_equal("leaf_wild_paths", leaf_wild_paths, {
            "tb_top.u_top.u_leaf_top",
            "tb_top.u_top.u_mid_a.u_leaf",
            "tb_top.u_top.u_mid_b.u_leaf",
            "tb_top.u_top.u_mid_out.u_leaf",
        })

        local none_paths = sim.get_hierarchy { module_name = "NoSuchMod" }
        assert(#none_paths == 0, "[none_paths] expected empty result")
        emit_line("[none_paths_count] 0")

        emit_line("[show_def_name_wildcard_tree_begin]")
        local captured = capture_print(function()
            sim.print_hierarchy {
                max_level = 4,
                wildcard = "*u_mid*",
                module_name = "MidMod",
                show_def_name = true,
            }
        end)
        for _, line in ipairs(extract_hierarchy_lines(captured)) do
            emit_line(line)
        end
        emit_line("[show_def_name_wildcard_tree_end]")

        local has_mid_def_name = false
        for _, line in ipairs(captured) do
            if line:find("(MidMod)", 1, true) then
                has_mid_def_name = true
                break
            end
        end
        assert(has_mid_def_name, "[show_def_name] expected output to contain `(MidMod)`")
        emit_line("[show_def_name_contains] MidMod")

        emit_line("[show_def_name_no_wildcard_tree_begin]")
        local captured_no_wildcard = capture_print(function()
            sim.print_hierarchy {
                max_level = 4,
                show_def_name = true,
            }
        end)
        for _, line in ipairs(extract_hierarchy_lines(captured_no_wildcard)) do
            emit_line(line)
        end
        emit_line("[show_def_name_no_wildcard_tree_end]")
        local has_mid_def_name_no_wildcard = false
        for _, line in ipairs(captured_no_wildcard) do
            if line:find("(MidMod)", 1, true) then
                has_mid_def_name_no_wildcard = true
                break
            end
        end
        assert(has_mid_def_name_no_wildcard, "[show_def_name_no_wildcard] expected output to contain `(MidMod)`")
        emit_line("[show_def_name_no_wildcard_contains] MidMod")

        run_multi_wildcard_checks()
        run_show_sig_type_checks(wtype)

        emit_line("[module_name_test] PASS " .. wtype)
        emit_line("[module_name_test] end")
        flush_report()
        sim.finish()
    end
}

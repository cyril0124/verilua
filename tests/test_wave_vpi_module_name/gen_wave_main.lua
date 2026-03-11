local clock = dut.clock:chdl()
local simulator = cfg.simulator
local table_sort = table.sort
local table_concat = table.concat
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
    assert(file, "[module_name_gen_test] failed to write report file: " .. tostring(err))
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

local function sort_and_print_paths(tag, paths)
    table_sort(paths)
    emit_line(string.format("[%s_count] %d", tag, #paths))
    for _, path in ipairs(paths) do
        emit_line(string.format("[%s] %s", tag, path))
    end
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

local function extract_def_name(captured_lines, instance_name)
    for _, line in ipairs(captured_lines) do
        if line:find(instance_name, 1, true) then
            local def_name = line:match("%(([^()]+)%)")
            if def_name ~= nil and def_name ~= "" then
                return def_name
            end
        end
    end
    return nil
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

fork {
    function()
        if simulator == "verilator" then
            sim.dump_wave("test.fst")
        elseif simulator == "iverilog" then
            sim.dump_wave("test.vcd")
        else
            sim.dump_wave()
        end

        clock:posedge(2)
        dut.reset:set(1)
        clock:posedge()
        dut.reset:set(0)
        clock:posedge(8)

        emit_line("[module_name_gen_test] begin")

        emit_line("[gen_show_def_name_wildcard_tree_begin]")
        local captured = capture_print(function()
            sim.print_hierarchy {
                max_level = 4,
                wildcard = "*u_mid*",
                show_def_name = true,
            }
        end)
        for _, line in ipairs(extract_hierarchy_lines(captured)) do
            emit_line(line)
        end
        emit_line("[gen_show_def_name_wildcard_tree_end]")

        local mid_module_name = extract_def_name(captured, "u_mid_a")
        local leaf_module_name = extract_def_name(captured, "u_leaf")
        assert(leaf_module_name ~= nil, "[gen_show_def_name] expected def-name for leaf instances")
        emit_line("[module_name_gen_leaf_def_name] " .. leaf_module_name)

        local leaf_paths = sim.get_hierarchy { module_name = leaf_module_name }
        assert(#leaf_paths > 0, "[gen_leaf_paths] expected non-empty result by module_name filter")
        sort_and_print_paths("gen_leaf_paths", leaf_paths)

        local leaf_wild_paths = sim.get_hierarchy {
            wildcard = "*u_leaf*",
            module_name = leaf_module_name,
        }
        assert(#leaf_wild_paths > 0, "[gen_leaf_wild_paths] expected non-empty result")
        sort_and_print_paths("gen_leaf_wild_paths", leaf_wild_paths)

        if mid_module_name ~= nil then
            emit_line("[module_name_gen_mid_def_name] " .. mid_module_name)
            local mid_paths = sim.get_hierarchy { module_name = mid_module_name }
            assert(#mid_paths > 0, "[gen_mid_paths] expected non-empty result by module_name filter")
            sort_and_print_paths("gen_mid_paths", mid_paths)

            local mid_wild_paths = sim.get_hierarchy {
                wildcard = "*u_mid_a*",
                module_name = mid_module_name,
            }
            assert(#mid_wild_paths > 0, "[gen_mid_wild_paths] expected non-empty result")
            sort_and_print_paths("gen_mid_wild_paths", mid_wild_paths)
        else
            emit_line("[module_name_gen_warn] def-name for `u_mid_a` is unavailable on " .. simulator)
        end

        local none_paths = sim.get_hierarchy { module_name = "NoSuchMod" }
        assert(#none_paths == 0, "[gen_none_paths] expected empty result")
        emit_line("[gen_none_paths_count] 0")
        emit_line("[module_name_gen_show_def_name_contains] " .. leaf_module_name)

        local multi_wild_paths = sim.get_hierarchy {
            wildcard = "*u_mid_a.data,*u_mid_b.data",
        }
        assert(#multi_wild_paths >= 2, "[gen_multi_wild_paths] expected at least two paths")
        local has_mid_a_data = false
        local has_mid_b_data = false
        for _, path in ipairs(multi_wild_paths) do
            if path == "tb_top.u_top.u_mid_a.data" then
                has_mid_a_data = true
            elseif path == "tb_top.u_top.u_mid_b.data" then
                has_mid_b_data = true
            end
        end
        assert(has_mid_a_data and has_mid_b_data, "[gen_multi_wild_paths] expected both u_mid_a.data and u_mid_b.data")
        sort_and_print_paths("gen_multi_wild_paths", multi_wild_paths)

        emit_line("[gen_multi_wild_tree_begin]")
        local captured_multi_wild = capture_print(function()
            sim.print_hierarchy {
                max_level = 4,
                wildcard = "*u_mid_a.data,*u_mid_b.data",
            }
        end)
        for _, line in ipairs(extract_hierarchy_lines(captured_multi_wild)) do
            emit_line(line)
        end
        emit_line("[gen_multi_wild_tree_end]")
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
        assert(has_mid_a_tree and has_mid_b_tree, "[gen_multi_wild_tree] expected both u_mid_a and u_mid_b in output")
        emit_line("[gen_multi_wild_contains] u_mid_a,u_mid_b")

        emit_line("[gen_show_def_name_no_wildcard_tree_begin]")
        local captured_no_wildcard = capture_print(function()
            sim.print_hierarchy {
                max_level = 4,
                show_def_name = true,
            }
        end)
        for _, line in ipairs(extract_hierarchy_lines(captured_no_wildcard)) do
            emit_line(line)
        end
        emit_line("[gen_show_def_name_no_wildcard_tree_end]")
        local expected_def_name_no_wildcard = mid_module_name or leaf_module_name
        local has_def_name_no_wildcard = false
        local expected_def_name_fragment = "(" .. expected_def_name_no_wildcard .. ")"
        for _, line in ipairs(captured_no_wildcard) do
            if line:find(expected_def_name_fragment, 1, true) then
                has_def_name_no_wildcard = true
                break
            end
        end
        assert(has_def_name_no_wildcard, "[gen_show_def_name_no_wildcard] expected def-name in output")
        emit_line("[module_name_gen_show_def_name_no_wildcard_contains] " .. expected_def_name_no_wildcard)

        emit_line("[gen_show_sig_type_tree_begin]")
        local captured_sig_type = capture_print(function()
            sim.print_hierarchy {
                max_level = 4,
                wildcard = "*u_mid_a.data",
                show_sig_type = true,
            }
        end)
        for _, line in ipairs(extract_hierarchy_lines(captured_sig_type)) do
            emit_line(line)
        end
        emit_line("[gen_show_sig_type_tree_end]")
        local detected_sig_type = extract_sig_type(captured_sig_type)
        assert(detected_sig_type ~= nil, "[gen_show_sig_type] expected signal type suffix in output")
        emit_line("[module_name_gen_show_sig_type_contains] " .. detected_sig_type)

        local show_sig_type_paths = sim.get_hierarchy {
            wildcard = "*u_mid_a.data",
            show_sig_type = true,
        }
        assert(#show_sig_type_paths > 0, "[gen_show_sig_type_paths] expected non-empty result")
        for _, path in ipairs(show_sig_type_paths) do
            assert(extract_sig_type { path } ~= nil, "[gen_show_sig_type_paths] expected typed suffix")
        end
        sort_and_print_paths("gen_show_sig_type_paths", show_sig_type_paths)

        emit_line("[module_name_gen_test] PASS " .. simulator)
        emit_line("[module_name_gen_test] end")
        flush_report()

        sim.finish()
    end
}

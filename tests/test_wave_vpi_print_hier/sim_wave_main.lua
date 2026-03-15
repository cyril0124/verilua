local table_sort = table.sort

local function print_sorted_paths(tag, paths)
    table_sort(paths)
    print(string.format("[%s_count] %d", tag, #paths))
    for _, path in ipairs(paths) do
        print(string.format("[%s] %s", tag, path))
    end
end

fork {
    function()
        print("[golden] begin")

        sim.print_hierarchy { max_level = 3 }
        sim.print_hierarchy { max_level = 1 }
        sim.print_hierarchy {
            max_level = 3,
            wildcard = "*u_mid",
        }
        local u_mid_paths = sim.get_hierarchy {
            max_level = 3,
            wildcard = "*u_mid",
        }
        print_sorted_paths("golden_get_hierarchy_u_mid", u_mid_paths)

        local clock_paths = sim.get_hierarchy { wildcard = "*clock" }
        print_sorted_paths("golden_get_hierarchy_clock", clock_paths)

        sim.print_hierarchy { max_level = 4, wildcard = "*clock" }

        -- show_bitwidth tests
        sim.print_hierarchy { max_level = 3, show_bitwidth = true }

        local bitwidth_clock_paths = sim.get_hierarchy { wildcard = "*clock", show_bitwidth = true }
        print_sorted_paths("golden_get_hierarchy_bitwidth_clock", bitwidth_clock_paths)

        local bitwidth_data_paths = sim.get_hierarchy { wildcard = "*data", show_bitwidth = true }
        print_sorted_paths("golden_get_hierarchy_bitwidth_data", bitwidth_data_paths)

        -- show_sig_type + show_bitwidth combined
        local combined_clock_paths = sim.get_hierarchy { wildcard = "*clock", show_sig_type = true, show_bitwidth = true }
        print_sorted_paths("golden_get_hierarchy_combined_clock", combined_clock_paths)

        print("[golden] end")

        sim.finish()
    end
}

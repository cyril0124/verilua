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

        print("[golden] end")

        sim.finish()
    end
}

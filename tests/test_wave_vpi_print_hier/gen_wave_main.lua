local clock = dut.clock:chdl()
local simulator = cfg.simulator
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
        clock:posedge(5)

        print("[golden_gen] begin")

        sim.print_hierarchy { max_level = 3 }

        local u_mid_paths = sim.get_hierarchy {
            max_level = 3,
            wildcard = "*u_mid",
        }
        print_sorted_paths("golden_gen_get_hierarchy_u_mid", u_mid_paths)

        local clock_paths = sim.get_hierarchy { wildcard = "*clock" }
        print_sorted_paths("golden_gen_get_hierarchy_clock", clock_paths)

        print("[golden_gen] end")

        sim.finish()
    end
}

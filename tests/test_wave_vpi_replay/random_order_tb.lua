io.stdout:setvbuf("no")
math.randomseed(2027)

local clock = dut.clock:chdl()

-- Persistent memory evaluation and intermittent requests share a random stream.
for index = 1, 8 do
    fork {
        function()
            for cycle = 1, 10 do
                clock:posedge()
                local positions = { 1, 2, 3, 4 }
                for slot = #positions, 2, -1 do
                    local chosen = math.random(1, slot)
                    positions[slot], positions[chosen] = positions[chosen], positions[slot]
                end
                print(string.format("RANDOM_ORDER MEM%d %d %s", index, cycle, table.concat(positions)))
            end
        end,
    }
end

local request_task_ids = {}
for index = 1, 4 do
    local task_id = scheduler:append_task(nil, "random_request_" .. index, function()
        clock:posedge()
        local qos = math.random(0, 14)
        print(string.format("RANDOM_ORDER REQ%d %s %d", index, sim.get_sim_time("ns"), qos))
    end, true)
    request_task_ids[index] = task_id
end

fork {
    function()
        for cycle = 1, 8 do
            clock:posedge()
            if cycle % 2 == 0 then
                for _, task_id in ipairs(request_task_ids) do
                    scheduler:try_wakeup_task(task_id)
                end
            end
        end
    end,
}

fork {
    function()
        sim.dump_wave("random_order.vcd")
        clock:posedge(10)
        print("RANDOM_ORDER_DONE")
        sim.finish()
    end,
}

-- Runs unchanged in real simulation (records samples) and under wave_vpi (replays them).
io.stdout:setvbuf("no")

local clock = dut.clock:chdl()
local count = dut.u_top.count:chdl()
local reset = dut.reset --[[@as verilua.handles.ProxyTableHandle]]

fork {
    function()
        sim.dump_wave("replay.fst") -- no-op under wave_vpi
        reset:set(1)                -- discarded under --ignore-writes
        clock:negedge(12)
        reset:set(0)

        for cycle = 1, 100 do
            clock:negedge()
            print(string.format("REPLAY_SAMPLE %d %s", cycle, count:get_hex_str()))
        end

        print("REPLAY_TB_PASS samples=100")
        clock:posedge(2)
        sim.finish()
    end,
}

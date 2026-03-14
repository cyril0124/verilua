-- wave_vpi benchmark: hot signal read.
-- HOT_SIGNAL_COUNT controls how many signals to read (default: 100).
-- READ_CYCLES controls how many cycles to iterate (default: 10000).
local HOT_SIGNAL_COUNT = tonumber(os.getenv("HOT_SIGNAL_COUNT")) or 100
local READ_CYCLES = tonumber(os.getenv("READ_CYCLES")) or 10000

local clock = dut.clock:chdl()
local paths = sim.get_hierarchy { wildcard = "*.sig" }
table.sort(paths)
assert(#paths >= HOT_SIGNAL_COUNT, string.format("Need at least %d signals, got %d", HOT_SIGNAL_COUNT, #paths))

local handles = {}
for i = 1, HOT_SIGNAL_COUNT do
    handles[i] = (paths[i]):chdl()
end

fork {
    function()
        clock:posedge()
        local s = os.clock()

        for _ = 1, READ_CYCLES do
            for j = 1, HOT_SIGNAL_COUNT do
                handles[j]:get()
            end
            clock:posedge()
        end

        local e = os.clock()
        print(e - s)
        sim.finish()
    end,
}

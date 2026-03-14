-- Waveform generator for wave_vpi benchmarks.
-- Simulates 20000 clock cycles to produce a waveform file.
-- Use WAVE_DUMP_FILE env var to control the output filename (default: bench.fst).
local clock = dut.clock:chdl()

fork {
    function()
        local wave_file = os.getenv("WAVE_DUMP_FILE")
        if wave_file then
            sim.dump_wave(wave_file)
        else
            sim.dump_wave("bench.fst")
        end

        dut.reset:set(1)
        clock:posedge()
        dut.reset:set(0)
        clock:posedge(20000)

        sim.finish()
    end,
}

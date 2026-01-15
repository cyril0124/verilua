---@diagnostic disable: undefined-global, undefined-field

local sim = os.getenv("SIM") or "verilator"

target("gen_wave", function()
    add_rules("verilua")

    if sim == "iverilog" then
        add_toolchains("@iverilog")
    elseif sim == "vcs" then
        add_toolchains("@vcs")
    else
        add_toolchains("@verilator")
    end

    add_files("./Counter.v")
    add_files("./Monitor.lua")

    set_values("cfg.lua_main", "./main.lua")
    set_values("cfg.top", "Counter")

    set_values("verilator.flags", "--trace", "--no-trace-top")
end)

target("sim_wave", function()
    add_rules("verilua")
    add_toolchains("@wave_vpi")

    if sim == "iverilog" then
        add_files("./build/iverilog/Counter/wave/test.vcd")
    elseif sim == "vcs" then
        add_files("./build/vcs/Counter/wave/test.vcd.fsdb")
    else
        add_files("./build/verilator/Counter/wave/test.vcd")
    end

    add_files("./Monitor.lua")

    set_values("cfg.lua_main", "./main_for_wal.lua")

    --- Note: cfg.top is set to "tb_top" instead of "Counter"
    ---
    --- Background: When running `gen_wave`, verilua's testbench_gen tool automatically
    --- generates a testbench module named `tb_top.sv` which:
    ---   1. Instantiates your DUT (Counter) as `uut` sub-module
    ---   2. Provides clock/reset generation
    ---   3. Exports all DUT ports as signals
    ---   4. Adds DPI interface for verilua interaction
    ---
    --- The waveform file (test.vcd) records signals from the tb_top hierarchy, not directly
    --- from the Counter module. Therefore, when analyzing the waveform with wave_vpi:
    ---
    ---   - cfg.top = "tb_top"  ← Access from testbench level (current setting)
    ---      This gives you access to:
    ---      * tb_top.clk, tb_top.reset (testbench signals)
    ---      * tb_top.count0, tb_top.count1 (exported DUT ports)
    ---      * tb_top.uut.count0 (DUT internal signals via hierarchy)
    ---
    ---   - cfg.top = "Counter" ← Access from DUT level
    ---      This only gives you access to signals inside the Counter module
    set_values("cfg.top", "tb_top")
end)

# wave_vpi example
This is a example for showing the usage of `@wave_vpi` backend which can be used to simulate waveform using the same Lua code as other backends(@vcs, @verilator, @iverilog).

## How to run this example?
First you need to run the `gen_wave` target to generate the waveform file.
```bash
xmake build -P . gen_wave
xmake run -P . gen_wave
```

Now you can run the `sim_wave` target to simulate the waveform you generated in the previous step.
```bash
xmake build -P . sim_wave
xmake run -P . sim_wave
```

You will see the exact same simulate result for both `gen_wave` and `sim_wave` targets except the `@wave_vpi` backend cannot modify the waveform file(signals are read-only).
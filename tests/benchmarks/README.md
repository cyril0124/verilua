# Verilua Benchmarks

Performance benchmarks for the Verilua runtime and the wave_vpi waveform
backend.

## Layout

```
benchmarks/
+-- xmake.lua                 build targets + the `benchmarks` runner
+-- cases/                    Lua test drivers (one per benchmark)
|   +-- signal_operation.lua
|   +-- multitasking.lua
|   +-- matrix_multiplier.lua
|   +-- matrix_multiplier_no_internal_clock.lua
|   +-- wave_vpi_gen.lua       generate a waveform to replay
|   +-- wave_vpi_bench.lua     replay/query the waveform via wave_vpi
+-- rtl/
|   +-- wave_vpi_bench.sv      DUT for the wave_vpi benchmarks
+-- waves/                    generated waveforms (fst/vcd/fsdb)
+-- *.json                    hyperfine result files (git-ignored)
```

The shared RTL `top.sv` / `matrix_multiplier.sv` live one level up in
`tests/rtl/`.

## Requirements

- `hyperfine` on `PATH` (the `benchmarks` runner uses it for timing).
- At least one simulator: `iverilog`, `verilator`, or `vcs`.
- For the FSDB wave benchmarks: `wave_vpi_main_fsdb`, `vcs`, and `verdi`.

## Running the full suite

```bash
# from repo root
xmake run -P tests/benchmarks benchmarks
```

This builds and times every case across the available simulators with
JIT on/off, then writes aggregated results to `output.json`. It covers:

- Runtime cases: `signal_operation`, `multitasking`, `matrix_multiplier`
- wave_vpi replay: fst / vcd / fsdb x Hot-Prefetch JIT on/off
  x hot-signal counts {5, 10, 100, 1000}

Warmup/runs default to 5/10 (2/4 for the slower wave_vpi cases).

## Running a single case

```bash
# build then run one target (SIM selects the simulator)
SIM=verilator xmake build -P tests/benchmarks signal_operation
SIM=verilator xmake run   -P tests/benchmarks signal_operation
```

## Environment variables

| Variable             | Used by              | Meaning                                    |
|----------------------|----------------------|--------------------------------------------|
| `SIM`                | all targets          | `iverilog` / `verilator` / `vcs` / `xcelium` |
| `JIT_V`              | runtime cases        | `on` / `off` (LuaJIT)                       |
| `WAVE_VPI_ENABLE_JIT`| wave_vpi bench       | `1` / `0` Hot-Prefetch JIT                  |
| `HOT_SIGNAL_COUNT`   | wave_vpi bench       | number of hot signals to query             |
| `WAVE_DUMP_FILE`     | wave_vpi gen         | output waveform file name                   |

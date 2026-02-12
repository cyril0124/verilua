# CHANGELOG.md

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org)

## Unreleased

### ✨ Added

- **wave_vpi**: Add `VL_QUIET` environment variable support to suppress all C++ log output in the wave_vpi module, providing consistent quiet mode behavior across both Lua and C++ components
- **xmake**: Add `VL_QUIET` environment variable support to suppress all build/run output in verilua xmake rule, providing quiet mode for automated workflows
- Add comprehensive time management API
    - Add `sim.get_sim_time(unit)` to query current simulation time with automatic unit conversion
    - Add `cfg.time_precision` and `cfg.time_unit` configuration fields
    - Add `await_time_fs()`, `await_time_ps()`, `await_time_ns()`, `await_time_us()`, `await_time_ms()`,
  `await_time_s()` scheduler APIs for precise time delays
    - Add `vpiml_get_time_precision()` and `vpiml_get_sim_time()` FFI functions
    - **wave_vpi**: Implement `vpi_get_time()` for FSDB and Wellen backends with automatic timescale detection from waveform files
    - **dummy_vpi**: Add `vpiTimePrecision` property support with configurable `DUMMY_VPI_TIME_PRECISION` macro (default: -9 for ns)
- **LuaSimulator**: Add function guards to prevent calling unsupported APIs in HSE/WAL scenarios

### 🐛 Fixed

- **verilator_main.cpp**: Fixed incorrect clock period for timescale 1ns/1ps

---

## v3.0.0 - 2026-01-25

---

## v2.0.0

---

## v1.0.0


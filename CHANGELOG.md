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
- **Queue**/**StaticQueue**: Add push_waitable(), pop_waitable() and wait_not_empty() methods for blocking queue operations
- **BitVec**: Add `to_hex_str_1()` method for full 32-bit aligned hex output (faster path without bit_width trimming)

### 🐛 Fixed

- **verilator_main.cpp**: Fixed incorrect clock period for timescale 1ns/1ps
- **scheduler**: Fixed race condition in event wakeup where tasks that call wait() again during wakeup would be immediately scheduled in the same cycle. Now uses a snapshot pattern to ensure re-waiting tasks are properly queued for the next event send
- **scheduler**: Fixed task event list cleanup issue where `remove_task()` did not remove the task ID from `event_task_id_list_map`, causing incorrect wake-up behavior when the same task ID was reused. This fix:
  - Adds `task_id_to_event_id_map` field to track task-to-event bidirectional mapping
  - Cleans up event task list entries when `remove_task()` is called
  - Clears stale `user_removal_tasks_set` flags in `append_task()` and `try_wakeup_task()` to prevent task reuse issues
  - Prioritizes user_removal checks in `wakeup_task()` to handle removal-before-wakeup scenarios correctly
- **BitVec**: Fixed `to_hex_str()` to respect `bit_width` and mask unused high bits, ensuring bit-precise output for non-32-bit-aligned widths (e.g., 28-bit, 30-bit, 31-bit)


---

## v3.0.0 - 2026-01-25

---

## v2.0.0

---

## v1.0.0


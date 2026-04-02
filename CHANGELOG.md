# CHANGELOG.md

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org)

## Unreleased

### ✨ Added

### 🐛 Fixed

- **xmake/nosim**: Fix toolchain detection log to print the resolved `nosim` binary name instead of the unrelated `wave_vpi_main` value
- **wave_vpi/wellen_impl**: Reuse a thread-local buffer for string value returns to avoid repeated `CString` allocations on the hot path

### 💥 Breaking Changes

---

## v3.2.0 - 2026-03-30

### ✨ Added

- **wave_vpi**: Add `vpiDecStrVal` support for decimal string value retrieval across all backends (FSDB JIT/normal, Wellen JIT/Binary/FourValue). Returns `"x"` when X/Z state is present, decimal number string otherwise
- **wave_vpi/libverilua**: Add backend support for Lua APIs `sim.print_hierarchy` and `sim.get_hierarchy`
- **wave_vpi/libverilua**: Add module definition name (`vpiDefName`) support for hierarchy collection and expose Lua hierarchy options `module_name` (filter) and `show_def_name` (display)
- **wave_vpi/libverilua**: `sim.get_hierarchy()` / `sim.print_hierarchy()` wildcard now supports comma-separated patterns (e.g. `*clock,*data`) with OR semantics.
- **AgeStaticQueue**: enhance `list_data` output
- **AgeStaticQueue**: Add `push_waitable()`, `pop_waitable()` and `wait_not_empty()` methods for blocking queue operations
- **libverilua**: Reuse a per-handle buffer for VCS/iVerilog string getters to avoid repeated `CString` allocations in `get_hex_str()` / `get_bin_str()` / `get_oct_str()` / `get_dec_str()` hot paths
- **libverilua**: Add hierarchy cache (`hierarchy_cache` feature) — binary file persistence with mmap reading and mtime-based cache invalidation to eliminate redundant VPI hierarchy traversals across calls and simulation restarts
- **wave_vpi**: Add progressive read optimization to Hot-Prefetch JIT — `vpi_get_value` can use the fast path incrementally as compilation threads produce results, instead of waiting for the entire window to finish
- **wave_vpi**: Add sliding window memory optimization to Hot-Prefetch JIT — limit `optValueVec` allocation to `2 × compileWindowSize` instead of the full waveform size, reducing memory usage for large waveforms
- **wave_vpi**: Add zero-allocation `bytes_last_u32_be` helper to replace `Vec`-based conversion in `wellen_get_int_value`, eliminating a heap allocation on the int-value read hot path
- **libverilua/wave_vpi**: Add signal bitwidth tracking to hierarchy collection API — `sim.get_hierarchy()` and `sim.print_hierarchy()` now support `show_bitwidth` option to display bit widths (e.g., `signal_name (width: 8)`). Bitwidth data is retrieved via `vpi_get(vpiSize)` and included in hierarchy cache format v2
- **LuaSimulator**: Add `sim.collect_signals(hier_path)` API for VPI-based signal introspection
- **LuaSimulator**: Implement `auto_bundle_via_hierarchy()` — optimized auto_bundle path using VPI hierarchy API instead of SignalDB
- **wave_vpi**: Add hierarchy-only mode (`--hierarchy-only` CLI flag / `WAVE_VPI_HIERARCHY_ONLY` env var) — skips signal data loading and time table parsing during wave_vpi initialization, reducing hierarchy query startup time from ~5s to ~0.7s (with cache hit) for large FSDB waveforms
- **wave_vpi**: Share single `ffrObject` across all FSDB JIT threads instead of creating per-thread instances, eliminating ~190 MiB memory overhead from separate decompression buffers

### 🐛 Fixed

- **wave_vpi**: Fix SIGSEGV race condition on process exit by using `_exit(0)` instead of `exit(0)` to skip C++ static destructors that conflict with background threads
- **wave_vpi**: Flush `stdout/stderr` before normal `_exit(0)` in `wave_vpi_loop()` to prevent losing buffered Lua output when running with pipes (e.g. `bash run.sh | tee t.log`)
- **wave_vpi**: Fix FSDB JIT recompilation running without mutex protection — recompilation is now serialized under `optMutex` to match FsdbReader's thread-safety requirements
- **wave_vpi**: Fix signed/unsigned comparison in FSDB JIT bitwise parsing loop (`int` → `uint_T`)
- **rules/xmake**: Fix `table.concat` crash when simulator flags (`wave_vpi.flags`, `wave_vpi.run_flags`) contain only a single value — `target:values()` may return a string instead of a table

### 💥 Breaking Changes

- **LuaDut**: `dut.signal = value` (`__newindex`) now delegates to `CallableHDL.value` instead of directly calling `vpiml_set_imm_value`. This changes from immediate-set (`set_imm`) to end-of-step-set (`set`) semantics, and adds support for `string`, `table` (BitVec, multi-beat), `cdata` (uint64_t, uint32_t[]), and `boolean` value types

## v3.1.0 - 2026-03-03

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
- **Queue**/**StaticQueue**: Add `push_waitable()`, `pop_waitable()` and `wait_not_empty()` methods for blocking queue operations
- **BitVec**: Add `to_hex_str_1()` method for full 32-bit aligned hex output (faster path without bit_width trimming)
- **scheduler**: Add `get_curr_task_id()` and `get_curr_task_name()` APIs for querying current task execution context
- **NativeClock**: Add high-performance native clock driver for HVL mode
    - Drives clock signals entirely in Rust native code using VPI `cbAfterDelay` callbacks
    - Avoids Lua context switching overhead for each clock edge
    - Supports configurable period, duty cycle, and start phase
    - Supports time units: `step`, `fs`, `ps`, `ns`, `us`, `ms`, `s`
    - Only available in HVL mode (not supported in HSE/WAL modes)
- **WaveVpiCtrl**: Add optional `unit` parameter to `get_max_cursor_time()` and `set_cursor_time()` for automatic time unit conversion
    - Supported units: `"fs"`, `"ps"`, `"ns"`, `"us"`, `"ms"`, `"s"`, `"step"`
    - Reuses the same `UNIT_TO_EXPONENT` pattern as `sim.get_sim_time(unit)`
    - `set_cursor_time` parameter order changed to `(time, unit?, flush_scheduler?)`
- **wave_vpi**: Support X/Z state preservation in `get_hex_str()` and `get_bin_str()` for both Wellen and FSDB backends. Previously X/Z values were silently converted to `0`; now correctly output `'x'`/`'z'` characters in string representations
- **wave_vpi**: Add Hot-Prefetch JIT limitation documentation — Hot-Prefetch JIT optimization uses 2-state(`uint32_t`) storage, which cannot represent X/Z. Disable via `WAVE_VPI_ENABLE_JIT=0` or `WaveVpiCtrl.jit_options:set("enableJIT", false)` when X/Z information is needed
- **wave_vpi/wellen_impl**: Switch the Wellen signal cache from YAML to a binary MessagePack format and load it through `memmap2` to reduce cache load/save overhead. Cache file name changed from `.wave_vpi.signal.yaml` to `.wave_vpi.signal.bin`

### 🐛 Fixed

- **verilator_main.cpp**: Fixed incorrect clock period for timescale 1ns/1ps
- **scheduler**: Fixed race condition in event wakeup where tasks that call `wait()` again during wakeup would be immediately scheduled in the same cycle. Now uses a snapshot pattern to ensure re-waiting tasks are properly queued for the next event send
- **scheduler**: Fixed task event list cleanup issue where `remove_task()` did not remove the task ID from `event_task_id_list_map`, causing incorrect wake-up behavior when the same task ID was reused. This fix:
  - Adds `task_id_to_event_id_map` field to track task-to-event bidirectional mapping
  - Cleans up event task list entries when `remove_task()` is called
  - Clears stale `user_removal_tasks_set` flags in `append_task()` and `try_wakeup_task()` to prevent task reuse issues
  - Prioritizes user_removal checks in `wakeup_task()` to handle removal-before-wakeup scenarios correctly
- **BitVec**: Fixed `to_hex_str()` to respect `bit_width` and mask unused high bits, ensuring bit-precise output for non-32-bit-aligned widths (e.g., 28-bit, 30-bit, 31-bit)
- **WaveVpiCtrl**: Fix LuaJIT FFI `uint64_t` cdata arithmetic truncation when multiplying with fractional scale factors (e.g., converting ps to ns). Now uses `tonumber()` to convert cdata to Lua number before scaling
- **WaveVpiCtrl**: Add missing boundary checks — `to_percent` now validates `percent >= 0`, `set_cursor_index` now validates `index < maxIndex`

---

## v3.0.0 - 2026-01-25

---

## v2.0.0

---

## v1.0.0

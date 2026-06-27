# CHANGELOG.md

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org)

## Unreleased

### 🐛 Fixed

- **libverilua**: Report an explicit error when HDL writes are attempted from an `await_rd()` / `cbReadOnlySynch` callback, matching the documented read-only phase semantics.
- **libverilua**: Fix a `cbReadWriteSynch` re-flush panic on VCS/iverilog where a value-change callback woken during the pending-put flush `set()`s a signal still queued, causing `try_put_value`'s dedup search to miss the stale entry and abort the simulation.
- **libverilua**: Fix `set()` + `await_rw()` flush ordering on VCS — the VPI `cbReadWriteSynch` spec (IEEE 1800-2023 38.36.2) does not define the relative order of the user await_rw callback and the internal pending-put flush. On VCS the user callback fires first, so `await_rw()` resumed the coroutine before `set()` values were committed. Now the RW callback explicitly flushes pending puts before resuming in non-`inertial_put` builds, making `set()` visible after `await_rw()` across supported simulators.

---

## v3.4.0 - 2026-06-24

### 💥 Breaking Changes

- **env**: Environment variable `CFG_USE_INERTIAL_PUT` renamed to `VL_USE_INERTIAL_PUT`.
- **sv**: `SVAContext` renamed to `SVBuilder`, directory `sva/` renamed to `sv/`. The require path changes from `verilua.sva.SVAContext` to `verilua.sv.SVBuilder`. `SVATemplate` renamed to `SVTemplate`. All error messages now use the `[SVBuilder]` prefix.
- **sv_lint**: `sv_lint` now reports warnings (e.g. `-Wreversed-range`, `-Wint-bool-conv`) in addition to errors. Previously only errors were surfaced.
- **cov_exporter**: Conditional-coverage semantics changed from per-expression toggle counting to control-flow path counting. Each `if` / `else if` / explicit `else` body now bumps a counter when actually entered, and the guard reflects the full path prefix (e.g. `(!(a)) && (b) && (c)` for an `if (c)` nested inside an `else if (b)`). Counter naming (`_<id>__COV_BIN_EXPR_CNT`), DPI exports (`getCondCoverage`, `getCoverageCount`, `showCoverageCount`, `coverageCtrl`, `resetCoverage`) and meta-json fields stay backward compatible. The denominator now equals the number of distinct guard paths instead of the number of distinct boolean sub-expressions.
- **cov_exporter**: The xmake config key `instrumentation` is deprecated in favor of `verilua.instrument`. The old key still works (with a deprecation warning) but new code should use the new name.
- **sv**: `SVBuilder` now references previously added sequences and properties through the `$(seq:name)` and `$(prop:name)` namespaces. Sequences and properties are no longer injected into the flat env namespace, so a bare `$(name)` will not resolve to them and the referenced kind is explicit at every use site. The `cat` helper function has been removed; pass a plain table to `envs` instead.
- **ChdlAccess**: `set()` / `set_imm()` / `set_force()` / `set_imm_force()` for Double/Multi signals now auto-dispatch by `type(value)` instead of requiring a `force_single_beat` boolean flag. Pass a number/cdata for scalar writes, pass a table for multi-beat writes. The old `set(value, true)` still works (second arg is ignored) but is deprecated.

### ✨ Added

- **LuaUtils**: Add `deepcopy()` for recursive table copying with cycle handling and metatable preservation.
- **LuaUtils**: `get_env_or_else()` now accepts a function default that is called when the environment variable is unset, validates the generated value type, and logs the generated value. Added `rand_int()`, `rand_bool()`, and `rand_choice()` helpers for lightweight runtime parameter randomization; `rand_choice()` also supports optional relative weights.
- **LuaSimConfig**: Seed setup is available before loading user config so function defaults in user config can be reproducible under the same `SEED`.
- **sv**: `SVBuilder` now supports `add "covergroup"` for generating SystemVerilog functional coverage. Covergroups use `default_clocking` as the sampling event by default, with per-covergroup override via `sample_event` parameter. A `final` block is automatically generated to print coverage results via `$display`. Use `ctx:set_coverage_report(false)` to disable.
- **SymbolHelper**: `try_ffi_cast` now accepts a single C function declaration and derives both the function name and the function-pointer type from it (e.g. `SymbolHelper.try_ffi_cast("void *svSetScope(void *scope);")`). The legacy 3-argument form `try_ffi_cast(func_ptr_str, ffi_func_decl_str, func_name)` keeps working unchanged. Internal call sites (`DpiExporter`, `WaveVpiCtrl`, `LuaSimulator`, `LuaUtils`) have been migrated to the minimal form.
- **LuaUtils**: Add `get_scriptdir()` — returns the absolute directory of the calling script, similar to xmake's `os.scriptdir()`
- **Cross**: Add combinatorics utilities for cartesian products, permutations, combinations, filtering, and random sampling for verification stimulus generation
- **Cross**: Add `product_call()` for cartesian-product execution of function blocks. `LuaUtils.matrix_call()` remains as a deprecated compatibility alias.
- **multi_task**: Add `task_group(function(tg) ... end)` — scoped concurrent task management that automatically tracks and joins all `tg:fork` tasks when the scope exits, eliminating forgotten-join bugs
- **multi_task**: Add `join_any { ehdl1, ehdl2, ... }` — waits until any one of the given `jfork` tasks finishes and returns the first completed handle
- **sv_lint**: New CLI tool (`src/sv_lint/`) backed by slang that performs SystemVerilog lint checking. `SVBuilder:add` now automatically invokes `sv_lint` after rendering each statement, catching syntax and semantic errors (e.g. `##[5:2]` range reversal, undeclared identifiers) at definition time. Use `ctx:set_lint(false)` to disable.
- **AliasBundle**: Add `fields`, an ordered list of `{ name, chdl }` entries for iterating available primary alias names and their `CallableHDL` handles.

### ⚙️ Changed

- **ChdlAccess**: Rewrite code generator from LuaJIT-Pro to plain Lua; generated functions are now module-level singletons shared across all handle instances (monomorphic call sites, zero per-instance allocation)

### 🐛 Fixed

- **set**: Fix `set()` timing inconsistency after value-change callbacks: when a coroutine is woken by a value-change triggered by Verilua's own `cbReadWriteSynch` flush, subsequent `set()` calls now produce observable value changes in the same simulation time, matching SV/RTL-driven edge behavior (see [#11](https://github.com/cyril0124/verilua/issues/11))
- **docs**: Clarify `CallableHDL:set()` as a deferred VPI write flushed at `cbReadWriteSynch`, not a write delayed until the next clock edge.
- **cov_exporter**: Fix generated RTL failing to compile when a module has zero cond-path points (e.g. no instrumentable `if` chains). The front `\`ifndef NO_COVERAGE` block was missing its closing `\`endif` due to slang's `parseGuess()` collapsing a single-member insert.
- **cov_exporter**: Fix `--ns` (merged toggle block) generating uncompilable RTL: `_<sig>__LAST` declarations were missing and each increment line carried a stray `end` that broke begin/end balance.
- **cov_exporter**: The lint test now verifies all five generated golden outputs with `verilator --lint-only` in both default and `+define+NO_COVERAGE` modes.
- **cov_exporter**: Wire `test_cov_exporter_dynamic` into the regression suite so it runs under `xmake run test` / `./test-all.sh`.
- **multi_task**: `TaskGroup:join_all()` now dynamically drains — tasks forked by child tasks during execution are also awaited, fixing the early-exit bug where dynamically forked children could be missed (see [#9](https://github.com/cyril0124/verilua/issues/9))
- **multi_task**: `TaskGroup` now reports an explicit error when a non-owner task calls `tg:join_all()` or `tg:join_any()` on that group, avoiding silent self-wait deadlocks while keeping `tg:fork()` unchanged
- **multi_task**: `task_group()` and `jfork()` now report clear errors when called outside a scheduler task, instead of leaking low-level yield/context failures
- **libverilua**: Fix use-after-free in `NativeClock` — `toggle()` registered a new callback before checking `destroy_pending`, leaving a dangling `user_data` pointer after the object was freed
- **libverilua**: Clear upper vector words in `set_value64`/`set_imm_value64` (and force variants), avoiding stale garbage on signals wider than 64 bits
- **libverilua**: Keep deferred string put-value buffers alive until `vpi_put_value` returns, avoiding dangling pointers for hex/dec/oct/bin writes
- **libverilua**: Free edge callback `user_data` when one-shot edge callbacks are removed, avoiding leaked callback allocation memory
- **libverilua**: Skip edge callback dispatch when VPI reports X/Z values instead of panicking on invalid edge values
- **xmake/verilua**: Fix project-relative path resolution after `on_run` changes cwd, and replace append-style target metadata updates with overwrite semantics to avoid stale values across repeated build/run phases
- **init**: Fix `stringx.rstrip` misuse when stripping `.lua` suffix from config file names — names ending with chars in `{a, u, l, .}` were incorrectly truncated, causing `require()` failures
- **CallableHDL**: Fix `expect_bin_str()` / `expect_not_bin_str()` crash due to missing `gsub` replacement argument — these APIs were completely unusable
- **LuaDut**: Fix `release_all()` not clearing `force_path_table` — subsequent `force_all`/`release_all` cycles would double-release previously forced signals and leak memory
- **ChdlAccess**: Fix `set_imm_bitfield_hex_str()` using deferred write instead of immediate write for single-beat and double-beat signals (code generator bug)
- **CallableHDL**: Fix `value_imm` assignment using deferred `set()` instead of `set_imm()` for multi-beat table values

---

## v3.3.0 - 2026-04-28

### ✨ Added

### 🐛 Fixed

- **utils/Queue|StaticQueue|AgeStaticQueue**: `front()` / `last()` now return `nil` for empty queues instead of potentially returning stale data
- **utils/Queue|StaticQueue|AgeStaticQueue**: `query_first_ptr()` / `query_first()` now return `nil` for empty queues instead of potentially returning stale data
- **TypeExpect**: Reject fractional Lua numbers in `expect_integer()` and improve `fake_chdl` missing-`get_width()` diagnostics for width-range `expect_chdl()` checks
- **wave_vpi**: Handle empty and single-time-point waveforms gracefully by avoiding time-table underflow in the Wellen/FSDB backends and skipping the main evaluation loop instead of aborting when no progressable waveform steps exist
- **libverilua/verilator**: Fix `get_dec_str()` fallback for wide signals by switching the Verilator hex-to-decimal workaround from `u128` parsing to arbitrary-precision conversion and reusing the per-handle string buffer
- **xmake/nosim**: Fix toolchain detection log to print the resolved `nosim` binary name instead of the unrelated `wave_vpi_main` value
- **wave_vpi/wellen_impl**: Reuse a thread-local buffer for string value returns to avoid repeated `CString` allocations on the hot path
- **xmake/testbench_gen**: Fix `verilua.tb_gen_flags` argument forwarding for `--custom-code-str` and `--custom-code-str-outer` so values containing spaces or newlines are passed to `testbench_gen` without shell splitting
- **CallableHDL**: Fix `posedge_until()` / `negedge_until()` to stop immediately after the final failed condition check instead of waiting one extra edge before returning `false`

### 💥 Breaking Changes

- **xmake**: Rename all `cfg.*` target values to `verilua.*` (e.g. `cfg.top` → `verilua.top`, `cfg.lua_main` → `verilua.lua_main`) to avoid confusion with the runtime Lua global `cfg` table. The old `cfg.*` names still work but emit a deprecation warning; they will be removed in a future release.
- **LuaDut**: Delegate `dut.<path>` check/read helper APIs to internal cached `CallableHDL` handles while keeping `dut.<path>:chdl()` lookups isolated; legacy `dut.<path>:set*()` and `dut.<path>:get()` keep their Lua number / 32-bit compatibility semantics

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

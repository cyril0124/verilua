# CHANGELOG.md

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org)

## Unreleased

### 💥 Breaking Changes

- **runtime / LuaJIT**: Replace the `luajit-pro` fork with official [LuaJIT](https://github.com/LuaJIT/LuaJIT) (v2.1 branch, built with `LUAJIT_ENABLE_LUA52COMPAT`), installed in place under the top-level `luajit/` submodule (was `luajit-pro/luajit2.1`). Consequences:
  - luajit-pro-only features are gone: `--[[luajit-pro]]` compile-time transforms (`__LJP:COMP_TIME()`, `__ljp:include()`, comp-time enums, Teal/Luau passthrough) and the Lua 5.3 operator syntax extension are no longer supported in user scripts.
  - `libluajit_pro_helper` is no longer built or linked; prebuilt binaries and `vl-*` wrappers now link only `libluajit-5.1`.
  - `table.nkeys` now uses the pure-Lua fallback (openresty `table.nkeys` C API is unavailable in official LuaJIT); behavior is unchanged.
  - Official LuaJIT is built with `LJ_MAX_UPVAL=120` (upstream default is 60).
  - JIT defaults follow OpenResty: `maxtrace=8000`, `maxrecord=16000`, `minstitch=3`, `maxmcode=40960` (KiB).
  - No measurable runtime performance difference (within noise on the `tests/benchmarks` runtime cases).

- **LuaDataBase**: Now an alias of `LuaDataBaseV2` (single implementation; the old lsqlite3-based one is removed). Same constructor params, `save`/`commit` semantics, and `__type`. Notable differences: libsqlite3 is loaded lazily via FFI (no more hard failure at `require` time under stale EDA-bundled libsqlite3), all V2 backends/params are accepted (`backend = "duckdb" | "turso" | "auto"`, `no_check_bind_value`, ...), log prefix is `[LuaDataBaseV2]`, and the private `db` handle is the FFI wrapper instead of an lsqlite3 object.
- **dummy_vpi**: Control macros hard-renamed (old names no longer recognized):
  - `DUMMY_VPI_NOT_USE_WRAPPER` → `VL_DUMMY_VPI_NOT_USE_WRAPPER`
  - `DUMMY_VPI_TIME_PRECISION` → `VL_DUMMY_VPI_TIME_PRECISION`
  - `DUMMY_VPI_STRICT_HANDLE_BY_NAME` → `VL_DUMMY_VPI_STRICT_HANDLE_BY_NAME`
- **env vars**: Hard-rename runtime env names (old names no longer read):
  - `DUT_TOP` → `VL_DUT_TOP`
  - `LUA_SCRIPT` → `VL_LUA_SCRIPT`
  - `NOSIM_BUILD` → `VL_NOSIM_BUILD`
  - `VERILUA_WAVEFORM_FILE` → `VL_WAVEFORM_FILE`
  - `VERILUA_HIERARCHY_CACHE_FILE` → `VL_HIERARCHY_CACHE_FILE`
  - `VERILUA_PRINT_HIER_STYLE` → `VL_PRINT_HIER_STYLE`
  - Preferred config env is `VL_CFG_FILE` (single path; relative or absolute). Directory defaults to `dirname(VL_CFG_FILE)`.
  - Legacy still accepted when `VL_CFG_FILE` is unset: `VERILUA_CFG` (file) and optional `VERILUA_CFG_PATH` (directory).
  Unchanged: `SIM`, `SEED`, `PRJ_DIR`, `PRJ_TOP`, `VERILUA_HOME`.
- **env / xmake**: `VL_USE_INERTIAL_PUT` → `VL_XMK_USE_INERTIAL_PUT` (xmake-rule override for `verilua.use_inertial_put`; old name no longer read).
- **env / xmake**: `NO_INTERNAL_CLOCK` → `VL_XMK_NO_INTERNAL_CLOCK` (xmake-rule override for `verilua.no_internal_clock` when unset; old name no longer read by rule/tests).
- **xmake / verilua rule**: Presence of a `.vlt` file (or `verilua.verilator_config`) no longer auto-disables default `--public-flat-rw`. Use `set_values("verilua.verilator_no_public_flat_rw", "1")` to opt out, then put fine-grained `public_flat_*` in `.vlt` / `verilua.verilator_config`.
- **xmake / verilua rule**: Rename make OPT knobs to `set_values("verilua.verilator_opt_fast", ...)` / `set_values("verilua.verilator_opt_slow", ...)`. Replaces `verilator.opt_fast` / `verilator.opt_slow` (no alias).
- **dpi_exporter / DpiExporter**: Meta field `exportedSignals` (string list) is replaced by `exportedSignalInfos` (`hierPath`, `bitWidth`, `vpiTypeStr`, `handleId`). Old meta files must be regenerated. `DpiExporter:is_exported` is removed; use `DpiExporter:lookup(path)` (info or `nil`).

### ⚙️ Changed

- **release / packaging**: Release and CI artifact zips now contain a single top-level directory named after the package (e.g. `verilua-x64-ubuntu-22.04/`), so `unzip` extracts everything into that folder.
- **CallableHDL / ProxyTableHandle**: Old write names still work and print `verilua_warning` on every call (`set_force`, `set_release`, `set_bitfield*`, `set_unsafe`, `set_shuffled`, `set_freeze`, `set_index*`, their `set_imm_*` counterparts, `force_all`, `release_all`, `force_region`, `set_cached`, `set_force_str`). Exception: `at(i)` now returns the cached `arr[i]` element view and no longer retargets the parent handle, so split-style `chdl:at(i); chdl:set(v)` must migrate to `chdl[i]:set(v)`.
- **ProxyTableHandle**: `force_region` now releases force state if the callback errors, then rethrows.
- **deps / slang**: Upgrade slang from v10.0 to [v11.0](https://github.com/MikePopoloski/slang/releases/tag/v11.0). Rebase the four local patches and adapt `slang_common` plus the slang-backed tools (`testbench_gen`, `sv_lint`, `dpi_exporter`, `cov_exporter`, `signal_db_gen`) to the v11 API.
- **ChdlAccess**: Rewrite the code generator in Python. `gen_chdl_access.py` replaces `gen_chdl_access.lua`, its three `gen_chdl_*.lua` variant modules and `gen_chdl_access.sh`, and writes directly to `src/lua/verilua/handles/`. The generated Lua is unchanged. Together with the scheduler generator, `src/gen` no longer needs a LuaJIT binary.
- **Scheduler**: Rewrite code generator from LuaJIT-Pro to plain Python. The shared implementation now lives in `src/gen/scheduler_template.lua` and is generated by `src/gen/gen_scheduler.py` (`gen_scheduler.sh` removed). Mode switches are emitted as write-once chunk-level `local`s, so LuaJIT constifies them as immutable upvalues and folds the other modes' branches at JIT time instead of stripping them at generation time.
- **C++ tools**: Drop Conan `libassert` and `cpptrace`. `ASSERT` / `PANIC` / `UNREACHABLE` now come from `src/include/vl_assert.h` (fmt + abort). `wave_vpi_main` crash handlers only print the signal name.
- **wave_vpi_main**: Drop Conan `argparse`. CLI is hand-parsed (`-w/--wave-file`, `--hierarchy-only`, `-h/--help`); `WAVE_FILE` env fallback is unchanged.
- **xmake / env**: `source verilua.sh` / `activate_verilua.sh` prepend `$VERILUA_HOME/scripts/xmakerc.lua` to `XMAKE_RCFILES` so `add_rules("verilua")` and simulator toolchains resolve. `unload_verilua` restores the previous `XMAKE_RCFILES`. Rule/toolchain files moved from `scripts/.xmake/` to `scripts/xmake/`. Removed `xmake run apply_xmake_patch`.
- **LuaSimConfig**: `cfg.prj_dir` is now resolved to an absolute path at runtime (nil/`""`/`"."` -> cwd; relative -> cwd-joined; absolute unchanged), making the public field unambiguous in logs and safe to hand to consumers with a different working directory.
- **DpiExporter / CallableHDL**: Exported-signal `hdl` is nil (dpi-only) only when `dummy_vpi` is not linked. If `vl_dummy_vpi_linked` is present, the VPI handle is kept so dummy_vpi still serves `get_hex_str` / `set` / edge. `get` / `get64` / `get_vec` stay on DPI in both cases.
- **dpi_exporter**: Control macros renamed to `VL_DPI_EXP_*` (preferred). Legacy names still accepted:
  - C cflags: `DPI_EXP_CALL_VERILUA_ENV_STEP` → `VL_DPI_EXP_CALL_ENV_STEP`; `DPI_EXP_USE_STRICT_STEP` → `VL_DPI_EXP_USE_STRICT_STEP`
  - SV: `` `DECL_DPI_EXPORTER_TICK `` → `` `VL_DPI_EXP_DECL_TICK ``; `` `CALL_DPI_EXPORTER_TICK `` → `` `VL_DPI_EXP_CALL_TICK ``; `` `MANUALLY_CALL_DPI_EXPORTER_TICK `` → `` `VL_DPI_EXP_MANUAL_TICK ``

### 🚀 Added

- **CallableHDL / ProxyTableHandle**: Signal writes now use `force`, `release`, `randomize`, `freeze`, plus `_imm` variants. CallableHDL also has `set_bits`, `set_bits_hex_str` (bit fields wider than 64 bits), `set_unchecked`, and `set_all`. Index an array from 0 with `arr[i]` or `dut.arr[i]`. The same index returns the same handle.
- **Bundle**: Add `set_all_imm`.
- **libverilua**: Lua time accounting is now runtime-controlled: set `VL_ACC_LUA_TIME=1` (or `true`) to fill the `lua_time_taken` / `lua_overhead` columns in the final statistics table, no rebuild needed. The compile-time cargo feature `acc_time` is removed; when the variable is unset the columns show `--` plus a dim hint on how to enable them.
- **LuaDataBaseV2**: New `backend = "auto"`: probes libsqlite3 health (loadability + `sqlite3_errstr` dlsym canary) and falls back to the turso backend with a loud `verilua_warning` when libsqlite3 is unusable (e.g. VCS's bundled sqlite 3.7.13 on `LD_LIBRARY_PATH`). Explicit `backend = "sqlite3"` still fails hard; pick a concrete backend to opt out of arbitration.
- **LuaDataBaseV2**: New `backend = "turso"` (Rust sqlite-compatible engine via `shared/libturso_ffi.so`, wrapper `verilua.utils.Turso`). Loaded by absolute path with no `libsqlite3.so` dependency, so it is immune to stale sqlite copies that EDA tools put on `LD_LIBRARY_PATH` (e.g. VCS ships sqlite 3.7.13 without `sqlite3_errstr`, which breaks `require "lsqlite3"` / `ffi.load("sqlite3")` inside `simv`). The library is built during `xmake install verilua` (step `setup_verilua`); rebuild manually with `xmake b turso_ffi`.
- **BundleToVlbc**: Pack a module tree into a sealed `.vlbc` (`require("verilua.utils.BundleToVlbc")`). `bundle_to_bc` collects literal `require()` deps into LuaJIT bytecode (lineinfo kept as `vlbc://mod:line`); `bundle_to_vlbc` AES-256-GCM-seals it. Key is compile-time `VL_BUNDLE_KEY_HEX` (64 hex = raw key, otherwise SHA-256). Loader is installed from `init.lua`. Unseal/require maps AES-GCM auth failure to a key-mismatch error.
- **dummy_vpi**: Export `vl_dummy_vpi_linked()` so Lua can distinguish dummy_vpi from real simulator VPI (`SymbolHelper.get_global_symbol_addr` / `DpiExporter:dummy_vpi_linked()`).
- **CallableHDL**: Add `is_dpi_only` (`true` when the signal is exported and dummy_vpi is not linked).
- **sv / SVBuilder**: `add "raw"` injects free-form preamble SV (`typedef` / function / `logic` / `always`) before `default clocking`, sequences/properties/covergroups; lint context includes preamble so later covergroups (and bare clock/reset used by `default_clocking`) can reference helper signals. `default_clocking` also accepts a hierarchical path string when no CHDL handle is available.
- **xmake / verilua rule**: Auto-export `VL_TARGET_NAME` (xmake `target:name()`) and `VL_BUILD_DIR` (target build dir absolute path) into runenvs so both `xmake run` and `setvars.sh` / `run.sh` expose them to Lua scripts.
- **testbench_gen / xmake**: Default log is quiet (one-line `generate ...` / `up-to-date`; warnings always). Detail behind `--verbose`. xmake rule no longer passes `--verbose` by default; use `add_values("verilua.tb_gen_flags", "--verbose")` when needed. Non-verbose runs call slang `runFullCompilation(quiet=true)` to drop "Top level design units" / "Build succeeded" noise.
- **libverilua**: Optional `VL_POST_INIT_SCRIPT` runs after `init.lua` (and auto `VL_DUT_TOP`) and before `VL_LUA_SCRIPT`. Value is an existing file path (`dofile`) or a Lua source string (`load`/`exec`). Empty value panics.
- **dpi_exporter**: Add `--cs/--config-str <lua source>` to pass config Lua inline (mutually exclusive with `-c/--config`; empty/whitespace-only is rejected). Cache still keys on normalized `configFileContent`.
- **libverilua**: Hot-path `sim_event` / `sim_event_chunk_N` now use registry-cached raw `lua_pcall` instead of `mlua::Function::call`, reducing per-callback Rust→Lua fixed overhead.
- **DpiExporter / CallableHDL**: Exported signals can construct without VPI (`hdl = nil`, width/type from meta) and still bind DPI `get`. Lookup is O(1) via an init-time map.
- **xmake / verilua rule**: Add `set_values("verilua.verilator_config", [[...]])` to inline Verilator control-file content without a separate `.vlt` or `add_files`. Content is written to `verilua_generated.vlt` under the target build dir and only adds directives (does not change public strategy).
- **xmake / verilua rule**: Add `set_values("verilua.verilator_no_public_flat_rw", "1")` to skip the default `--public-flat-rw` injection.
- **libverilua**: Enable VPI `set_force` / `set_release` on Verilator (≥ 5.050). Signals must be marked `forceable` (e.g. via `verilua.verilator_config`).
- **xmake / verilua rule**: When a control file (`.vlt` / `verilua.verilator_config`) contains `forceable`, require Verilator ≥ 5.050 at build time so old versions fail the build instead of silently treating force as a normal write.

### 🐛 Fixed

- **Bundle**: A signal whose name collides with a Bundle field or method (`name`, `prefix`, `bits`, `fire`, `get_all`, `set_all`, `dump`, ...) used to silently lose its handle. Construction now fails, and the message gives the full-path form to use instead: `("<hier>.<prefix><signal>"):chdl()`.
- **install / setup_verilua**: Shell rc now gets `source <abs>/verilua.sh` (replaces the broken `VERILUA_HOME=$(curdir)` block on re-run). The current shell still needs one manual `source`. `test_verilua` now fails when no simulator is on `PATH`. `update_verilua` restores the previous install if the new copy fails. `install_luarocks` reuses an existing tarball instead of `wget -P` every time.
- **testbench_gen**: Clock/reset port selection is now priority-based (exact `clk`/`clock`/`rst`/`reset` beat active-low `rst_n`-style names, which beat `clk_*`/`*_clk`/`rst_*`/`*_rst_n` patterns) instead of first-declaration-order, and only input ports are eligible. Multiple same-priority matches now error with an explicit `--clock-signal`/`--reset-signal` hint instead of silently picking the first; a specified signal that is not an input port also errors out.
- **LuaDataBaseV2**: Creating the database directory now tolerates losing the mkdir race: parallel simulations sharing the same `path_name` no longer crash with "Cannot create folder" when another process created the directory first; any other mkdir failure (permission, missing parent, non-directory path) still fails loudly.
- **LuaDataBaseV2**: The sqlite3 backend's checked bind path bound numbers with `sqlite3_bind_int` (32-bit C int), truncating values above 2^31 (e.g. long-run cycle counts). Numbers are now bound as doubles (53-bit exact, matching the no_check fast path); the turso backend binds native int64.
- **LuaDataBase / LuaDataBaseV2**: Manual `commit()` (including the finalization commit) after a partial batch no longer writes one extra stale/duplicate row, and an empty commit no longer writes a garbage row. `save_cnt` now always tracks the next free cache slot and commit flushes `1 .. save_cnt - 1`.
- **DpiExporter / CallableHDL**: dpi-only `get64` (width ≤ 32), `get_hex_str`, and multi-beat `get`/`get(true)` now bind to DPI. `GET_VEC` is copied into the chdl `c_results` layout (`[0]=beat_num`, words from `[1]`).
- **Scheduler**: Task failures no longer emit a second generic `assertion failed!`; the scheduler now reports that execution was aborted after printing the original traceback.
- **NativeClock**: Edge puts now use the deferred `set` path (`vpiml_set_value` / pending queue) instead of immediate `vpiNoDelay`, matching Lua `clock:set` and Verilator RW/comb observation.
- **libverilua build**: `xmake run build_libverilua` no longer rebuilds the dependency graph between variants. `--wrap` for dpi builds is injected through `cargo rustc` link args instead of a global `RUSTFLAGS` toggle, `iverilog_vpi_module` reuses the `libverilua_iverilog` build instead of cleaning first, and dpi variants are built as one group so `mlua/send` is compiled once. A full clean build takes ~1m07s instead of ~1m33s (256 cores) and ~1m21s instead of ~2m20s (4 cores), at about half the CPU time. Per-variant artifacts are unchanged.
- **xmake / verilua rule**: `setvars.sh` now shell-quotes `add_runenvs` values so spaces, quotes, and newlines (e.g. multi-line `VL_POST_INIT_SCRIPT`) survive `source setvars.sh`. `PATH` / `LD_LIBRARY_PATH` still append `:$KEY` outside the quotes.
- **xmake / verilua rule**: Verilator is now invoked with the canonical `--top-module` flag instead of the `--top` alias (kept for compatibility in current Verilator releases), for forward compatibility.
- **testbench_gen**: Non-Verilator (VCS/iverilog/Xcelium) generated testbenches now drive the DUT reset port via an internal `reg reset` (`wire <reset_name>; assign <reset_name> = reset;`) instead of declaring the reset signal directly as a `reg` and aliasing it to an internal `wire reset`, matching the Verilator convention so user code can drive/release `reset`.
- **libverilua**: `get_symbol_address` now loads each ELF symbol table once (symtab + dynsym). Previously every cache miss re-read and re-parsed the whole binary; with a ~200MB Verilator sim and hundreds of DPI mon CHDLs at `abdl` create, env setup became pathologically slow.
- **dpi_exporter**: Sensitive-group ticks (`dpi_exporter_tick_<group>`) are emitted again in the default always-block as multi-line calls. After the large-arg-list fix stopped expanding `` `CALL_DPI_EXPORTER_TICK ``, sensitive groups only lived in that unused macro and never updated shadow values under Verilator.
- **DpiExporter**: `try_get_meta_file` no longer touches `ffi.C.<missing>` (which aborts LuaJIT when `dpi_exporter_get_meta_info_file_path` is not linked); `DpiExporter:init()` now fails with a clear assert message and `DpiExporter:try_init()` returns `false` gracefully instead of crashing.
- **libverilua**: Fix `inertial_put` string put path leaking a heap `CString` on every `_vpiml_*_value_*_str` call.
- **libverilua**: Rebuild iverilog VPI link search paths when `IVERILOG_HOME` / `LD_LIBRARY_PATH` change (`cargo:rerun-if-env-changed` in `build.rs`).
- **libverilua**: Key `get_symbol_address` cache by `(filename, symbol_name)` and parse ELF outside the cache lock.
- **libverilua**: Restore `RUSTFLAGS` after DPI cargo builds even if cargo fails, so `--wrap` flags no longer leak into later builds.
- **libverilua**: Guard null `vpi_iterate` results in `vpiml_iterate_vpi_type`, and free the module iterator after early exit in `vpiml_get_top_module`.
- **dpi_exporter**: Default always-block now calls `dpi_exporter_tick(...)` as a real multi-line call instead of the `CALL_DPI_EXPORTER_TICK` macro, fixing Verilator `Too many preprocessor tokens on a line (>40000)` when exporting large hierarchical signal lists.
- **libverilua / inertial_put**: `set_force` under `VL_XMK_USE_INERTIAL_PUT` used `vpiInertialDelay` instead of `vpiForceFlag`, so force did not stick. Force now keeps `vpiForceFlag`; same-timeslot force+release coalesce remains deferred-only (skip under inertial_put).

---

## v3.5.1 - 2026-07-29

### 💥 Breaking Changes

- **testbench_gen / xmake**: Remove `--lua-meta-file` / `--lm` and stop writing DUT port LuaCATS meta files. The xmake verilua rule no longer passes `--lua-meta-file build/meta.lua`.

### 🚀 Added

- **ChdlAccess / ProxyTableHandle**: Restore `set_imm_force`, `set_imm_release`, and `set_imm_freeze` for immediate force/release/freeze. Deferred `set_force` / `set_release` / `set_freeze` remain the default cycle-accurate path.

### 🐛 Fixed

- **ChdlAccess / ProxyTableHandle / libverilua**: Restore deferred `set_force` / `set_release` / `set_freeze` (applied at `cbReadWriteSynch`). Same-timeslot `set_release()` + `set_force()` coalesce again, so continuous backpressure no longer glitches handshake signals mid-timeslot.

---

## v3.5.0 - 2026-07-22

### 💥 Breaking Changes

- **ChdlAccess / ProxyTableHandle**: Remove `set_imm_force`, `set_imm_release`, and `set_imm_freeze`. Use deferred `set_force` / `set_release` / `set_freeze` instead. On iverilog/xcelium, `set_release` already maps to immediate release internally.

### 🚀 Performance

- **libverilua**: Reclaim chunk edge-callback user data on fire. The `chunk_task` callback handlers boxed their `EdgeCbDataChunk_N` at registration but never freed it on removal, leaking one allocation per fired chunk every cycle. The handlers now drop the box after `vpi_remove_cb`, mirroring the non-chunk path.
- **libverilua**: Replace the edge-callback `IDPool` + `HashMap<EdgeCallbackID, u64>` pair with a single `slab::Slab<u64>`, turning callback registration and removal into O(1) `Vec`-indexed ops with no hashing.

### 🐛 Fixed

- **LuaUtils**: Fix `uint_to_onehot()` for bit positions 31..62 — previously used 32-bit signed `bit.lshift(1, n) + 0ULL`, so bit 31 became `2^63` and bits 32..62 wrapped mod 32. Now uses `bit.lshift(1ULL, n)` for correct 64-bit one-hot values across 0..63.
- **LuaUtils**: Fix `to64bit(hi, lo)` — previously used 32-bit `bit.lshift(hi, 32) + lo`, so the result collapsed to `hi + lo` instead of `(hi << 32) | lo`. Now promotes to `uint64_t` before shifting.
- **IDPool**: Fix `alloc()` on an empty pool corrupting internal size — previously decremented `size` to `-1` before the nil-key error, so a failed alloc left `free_count() == -1`. Now asserts emptiness before mutating state.
- **IDPool**: Honor `shuffle=false` on construction — previously checked `_shuffle ~= nil` after normalizing with `or false`, so the pool was always shuffled. Now uses `if _shuffle then`.
- **BitVec**: Fix `SubBitVec:dump()` printing the parent full value instead of the selected bitfield — it now uses `t:dump_str()` like `tostring`.
- **LuaUtils**: Fix `execute_after(..., { times = 0 })` being treated as unset — `options.times or nil` dropped 0 because it is falsy in Lua, so times=0 behaved like the default one-shot. Now uses `~= nil` and treats `times <= 0` as never-fire.
- **LuaUtils**: Fix `enum_search` error path crashing when the table has no `name` field — message building used `t.name` without `tostring`, so plain maps raised `attempt to concatenate field 'name'` instead of a clean not-found error.
- **LuaUtils**: Fix `exclusive_call` not releasing the file lock when `func()` errors — previously the lock was leaked until process exit, blocking subsequent acquires on the same path. Now uses `pcall` and always `release_lock`.
- **libverilua**: Fix `vpiml_handle_by_index()` not inserting into `hdl_cache` on miss — each call allocated a new `ComplexHandle` for the same parent+index, leaking memory and returning distinct raw pointers. Now caches like `complex_handle_by_name`.
- **libverilua**: Fix `complex_handle_by_name` storing the caller's name pointer without copying — `ComplexHandle.name` was documented as owned but pointed at LuaJIT/C temporary buffers, causing use-after-free when the caller freed them. Now copies into an owned `CString`, matching `handle_by_index`.
- **libverilua**: Bound hierarchy-cache `entry_count` by remaining file bytes before `Vec::with_capacity` — a tiny malicious `.verilua_hierarchy_cache` could previously force multi-GB reservations (or OOM) by claiming millions of entries. Oversized counts are now rejected and the cache is ignored.
- **utils/StaticQueue|AgeStaticQueue**: Reject non-positive `size` at construction — previously `size <= 0` could create a zero/negative capacity ring and later fail with modulo-by-zero on `push`/`pop`. Now asserts `size > 0`.
- **libverilua**: Prevent `vpiml_get_value64()` from reading a second VPI vector word for signals no wider than 32 bits; absent high bits and their X/Z state are now treated as zero.
- **libverilua**: `await_rw()` now resumes only after the design has settled, instead of right after the pending-put flush. Previously a single `await_rw()` after `set()` could observe stale combinational outputs on verilator/iverilog, since the flush and the wakeup could land in the same callback pass, before the simulator re-evaluated the affected combinational logic. Known caveat: on VCS, same-slot reads of flip-flop outputs (and signals depending on them) still observe the pre-edge value, since VCS runs all same-slot `cbReadWriteSynch` callbacks before nonblocking-assignment updates mature (implementation-defined per IEEE 1800-2023 38.36.2).
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

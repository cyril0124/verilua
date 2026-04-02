# AGENTS.md

## Project Map

- Project name: Verilua.
- `./DEVELOPMENT.md` contains extra background for generated-code workflows and broader testing guidance.
- `./xmake.lua` is the top-level build entry. Many subprojects under `./src` also have their own `xmake.lua`.
- `./docs` contains MDX documentation sources. `./docs-website` contains the Docusaurus site.

## Where To Start

- Lua runtime and public scripting APIs: `./src/lua/verilua`
- Rust VPI core and simulator-specific shared libraries: `./libverilua`
- Verilator main program and LightSSS support: `./src/verilator`
- Waveform backend binaries and readers: `./src/wave_vpi`
- No-simulation analysis backend: `./src/nosim`
- Lua code generators for schedulers and CHDL access: `./src/gen`
- Testbench generator: `./src/testbench_gen`
- SignalDB generator and shared library: `./src/signal_db_gen`
- VPI shim over generated DPI accessors: `./src/dummy_vpi`
- DPI code generator for `dummy_vpi`: `./src/dpi_exporter`
- Coverage instrumentation and export generator: `./src/cov_exporter`
- Common C/C++ headers: `./src/include`
- Examples and tutorials: `./examples`
- Xmake rules, plugins, and simulator toolchains: `./scripts/.xmake`
- Verilua's xmake rule implementation: `./scripts/.xmake/rules/verilua/xmake.lua`
- Conan packaging helpers: `./scripts/conan`
- Simulator wrapper commands: `./tools`
- Documentation content: `./docs`
- Docusaurus site sources: `./docs-website`
- Tests: `./tests`

## Generated Code

- Edit `./src/gen/gen_scheduler.lua` and run `cd src/gen && ./gen_scheduler.sh` instead of editing generated scheduler files directly. Generated files live in `./src/lua/verilua/scheduler`.
- Edit `./src/gen/gen_chdl_access.lua` and run `cd src/gen && ./gen_chdl_access.sh` instead of editing generated CHDL access files directly. Generated files live in `./src/lua/verilua/handles`.
- Edit `./libverilua/src/gen/gen.lua` and run `cd libverilua/src/gen && luajit gen.lua` instead of editing generated Rust outputs directly. Generated files live under `./libverilua/src/gen`.

## Code Style

- Lua code must include EmmyLua or LuaCATS type annotations.
- Lua code must follow LuaJIT best practices and account for JIT performance characteristics.
- Follow the best practices already used in the existing codebase.
- Add concise English comments for important or non-obvious code blocks when they improve readability.
- After modifying Lua files, run `xmake r format-lua`.
- After modifying C or C++ files, run `xmake r format-cpp`.

## Code Quality Checks

- After modifying any Lua file, including standalone Lua test files such as `test_idpool.lua`, always run:

```bash
# F must come first, and the path must be absolute.
F=/abs/path/to/<lua file> xmake r lsp-check-lua

# Example
F=/nfs/home/zhengchuyu/tmp/verilua/src/lua/verilua/LuaUtils.lua xmake r lsp-check-lua
```

- If you need to check multiple Lua files, run `xmake r lsp-check-lua` serially, one file at a time. Do not run multiple checks in parallel.
- Make sure the output contains no errors or warnings.
- After modifying any Rust code, run `cargo fmt` and then `cargo clippy --all-targets --all-features -- -D warnings`; fix all warnings.

## Running Tests

- Run only the smallest relevant build or test commands for the files you changed. Do not run a full-project build such as `xmake b`.
- When adding or changing features, include relevant tests.
- To run the broader regression suite, use `xmake run test`.
- To control parallelism for `xmake run test`, set `VL_TEST_JOBS=<n>`. The default is `4`.
    - Use `VL_TEST_FILTER=<token1,token2>` to run only matching test jobs.
    - Use `VL_TEST_LIST=1` to list matched test jobs without running them.
    - Use `STOP_ON_FAIL=1` to stop scheduling new jobs after the first failure.
    - Use `VL_TEST_KEEP_WORKDIR=1` to keep the test log directory under `.xmake/test` even when all jobs pass.
    - Use `VERBOSE=1` or `V=1` for verbose output and failed-job log dumping.
- To run Lua unit tests, use `cd tests && xmake run -P . test-all-lua`.
- To run one Lua test file, use `cd tests && luajit test_lua_utils.lua --stop-on-fail --no-quiet`.
- `./tests/test_*.lua` files can be executed directly with `luajit`.
- For integration-style test directories such as `./tests/test_*/`, enter the directory and usually run `xmake b -P . && xmake r -P .`.
- You can also run a specific integration test from the repo root with `xmake build -P tests/test_basic_signal` and `xmake run -P tests/test_basic_signal`.
- Tests that rely on xmake support the `SIM` environment variable to select the simulator. Supported values include `verilator`, `vcs`, and `iverilog`.
- Example: `SIM=vcs xmake b -P . && SIM=vcs xmake r -P .`
- Example from the repo root: `SIM=iverilog xmake run -P tests/test_basic_signal`
- If `SIM` is not specified, the default simulator is typically `verilator`.

## Component Builds

- If you modify `libverilua`, rebuild it with `xmake run build_libverilua`.
- If the `libverilua` change is simulator-specific, use the matching command:
    - `SIM=verilator xmake run build_libverilua`
    - `SIM=vcs xmake run build_libverilua`
    - `SIM=iverilog xmake run build_libverilua`
    - `SIM=xcelium xmake run build_libverilua`
    - `SIM=wave_vpi xmake run build_libverilua`
- If you modify `wave_vpi`, run `xmake b wave_vpi_main`.
- Run `xmake b wave_vpi_main_fsdb` only on Linux with `VERDI_HOME` set.
- If you modify `testbench_gen`, run `xmake b testbench_gen`.
- If you modify `signal_db_gen`, run `xmake b signal_db_gen` and `xmake b libsignal_db_gen`.
- If you modify `dpi_exporter`, run `xmake b dpi_exporter`.
- If you modify `cov_exporter`, run `xmake b cov_exporter`.
- If you modify `nosim`, run `xmake b nosim`.
- If building `wave_vpi_main` fails, build `wave_vpi_wellen_impl` first with `xmake b wave_vpi_wellen_impl`.
- If you modify Rust code in `wellen_impl`, build `wave_vpi_wellen_impl` first with `xmake b wave_vpi_wellen_impl`.

## Docs Sync

- If you change user-facing behavior, commands, configuration, or workflows, update `./docs` as needed.
- Any user-visible, behavior-changing, feature, bug-fix, workflow, or compatibility-related change must be recorded in `CHANGELOG.md` under `## Unreleased`.
- If you modify `./docs-website`, use Node.js `>=18` and run `npm run build` in `./docs-website`.

## Reference Code

- If you are unsure about a Slang API, inspect the Slang source repository first: `https://github.com/MikePopoloski/slang.git`. Many parts of Verilua depend on Slang.
- For Verilua's Slang helper layer used by multiple generators, inspect `https://github.com/cyril0124/slang-common.git`.
- If something is still unclear, online research is allowed.

## General Rules

- Code comments must always be written in English.

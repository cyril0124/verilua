# Development Guide for Verilua

This document contains important information for developers working on the Verilua project.

## ⚠️ Code Generation Warning

Parts of the Verilua codebase are auto-generated. **DO NOT edit these files directly** as any modifications will be overwritten when the generation scripts are run.

## Code Generation

### Scheduler Files

The scheduler files are auto-generated.

Verilua requires multiple scheduler variants to support different simulation modes and performance optimizations:

- **NORMAL mode**: Standard simulation with time-based scheduling
- **STEP mode**: Fixed-period step simulation
- **EDGE_STEP mode**: Edge-triggered simulation with separate posedge/negedge handling

Each mode has two variants - with and without performance profiling (P suffix). This specialization eliminates runtime conditionals and optimizes memory usage by including only mode-specific code.

**To modify scheduler files:**
1. Edit the generator: `src/gen/gen_scheduler.lua`
2. Run the generation script: `cd src/gen && ./gen_scheduler.sh`

The following files are generated (in `src/lua/verilua/scheduler/`):
- `LuaNormalSchedulerV2.lua`
- `LuaNormalSchedulerV2P.lua`
- `LuaStepSchedulerV2.lua`
- `LuaStepSchedulerV2P.lua`
- `LuaEdgeStepSchedulerV2.lua`
- `LuaEdgeStepSchedulerV2P.lua`

### CHDL Access Files

The CHDL access files are auto-generated.  
They are split into three variants (`Single`, `Double`, `Multi`) to match the different widths of hardware signals that Verilua needs to drive from Lua:

- `Single` – 1–32-bit signals  
- `Double` – 33–64-bit signals  
- `Multi` – wider than 64-bit signals  

This separation keeps the generated Lua glue code minimal and fast: each variant inlines the exact bit-width it needs, avoiding runtime width checks and letting the JIT specialize on the concrete type.  
If you need to change how Lua talks to CHDL (e.g., add a new bit-width, change the FFI signatures, or tweak the callback policy) you edit the single generator instead of touching any of the three hand-tuned files.

**To modify CHDL access files:**
1. Edit the generator: `src/gen/gen_chdl_access.lua`
2. Run the generation script: `cd src/gen && ./gen_chdl_access.sh`

The following files are generated (in `src/lua/verilua/handles/`):
- `ChdlAccessSingle.lua`
- `ChdlAccessDouble.lua`
- `ChdlAccessMulti.lua`

### Rust Code Generation

Some Rust files are auto-generated.

**To modify generated Rust files:**
1. Edit the generator: `libverilua/src/gen/gen.lua`
2. Run the generation script: `cd libverilua/src/gen && luajit gen.lua`

The following files are generated (in `libverilua/src/gen/`):
- `gen_callback_policy.rs`
- `gen_register_callback_func.rs`
- `gen_verilua_env_struct.rs`
- `gen_verilua_env_init.rs`
- `gen_sim_event_chunk_init.rs`

## Running Tests

**Important:** When adding or implementing any new feature, please include relevant tests to ensure correctness and avoid future breakage.

**Running comprehensive test suite:**
- `xmake run test` - Run complete test suite including all example projects(This may take a few minutes to complete!)
- This command automatically detects available simulators and runs tests on all found simulators

**Running Lua unit tests:**
```bash
cd tests
xmake run -P . test_all
```
- Run single test file:
```bash
cd tests
luajit test_lua_utils.lua --stop-on-fail --no-quiet

# or simply
luajit test_lua_utils.lua
```

**Running integration tests:**

To run tests in a specific test directory:
```bash
cd tests/test_basic_signal
xmake build -P .
xmake run -P .
```

Or from the project root directory:
```bash
xmake build -P tests/test_basic_signal
xmake run -P tests/test_basic_signal
```

**Environment variables:**
- `SIM` environment variable specifies the supported simulator (verilator/iverilog/vcs)
- Example: `SIM=iverilog xmake run -P tests/test_basic_signal`

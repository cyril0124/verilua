---
name: verilua-guide
description: "Locate the right Verilua doc, example, test, or source file for any Verilua usage question. Use when asking how to use a Verilua API or where something lives in the repo."
---

# Verilua Guide

## Purpose

A reference source map of the Verilua repository. Covers documentation, examples, and source layout to help locate the right file quickly.

## Repository

- GitHub: <https://github.com/cyril0124/verilua>

All file paths below are relative to the repo root.

## Project Structure

User-facing overview of the Verilua repository layout:

```
verilua/
├── docs/                                      # Documentation sources (MDX)
│   ├── navigation.mdx                         # Goal-based reading paths covering all major topics
│   ├── index.mdx                              # What Verilua is, HVL/HSE/WAL modes, architecture overview
│   ├── getting-started/
│   │   ├── install.mdx                        # Installation (release and source)
│   │   ├── luajit_vs_standard_lua.mdx         # LuaJIT differences relevant to Verilua
│   │   ├── simple_hvl_example.mdx             # Minimal HVL testbench walkthrough
│   │   ├── simple_hse_example.mdx             # Embedding Lua in a running simulation
│   │   └── simple_wal_example.mdx             # Offline waveform analysis with VCD/FST/FSDB
│   ├── how-to-guides/
│   │   ├── write_xmake_lua.mdx                # Writing xmake.lua for a Verilua project
│   │   ├── simple_ut_env.mdx                  # Setting up a simple unit-test environment
│   │   ├── clock_driving.mdx                  # Clock driving strategies (Internal / NativeClock / Lua Clock)
│   │   ├── multi_clock_testing.mdx            # Multi-clock domain testing
│   │   ├── oop_with_pl_class.mdx              # OOP patterns using pl.class
│   │   ├── write_reusable_component.mdx       # Writing reusable monitors/scoreboards/agents
│   │   ├── emmylua_type_annotations.mdx       # EmmyLua/LuaCATS type annotations
│   │   ├── common_lua_pitfalls.mdx            # Common Lua/LuaJIT traps in hardware verification
│   │   ├── call_c_functions.mdx               # Calling C functions from Lua via FFI
│   │   ├── cross_stimulus_generation.mdx      # Combinatorial stimulus generation with Cross
│   │   └── combinational_logic.mdx            # Drive/read combinational logic correctly after set()
│   └── reference/
│       ├── multi_task.mdx                     # fork, jfork, join, task_group, coroutine scheduling
│       ├── await_time.mdx                     # Time-based waiting primitives
│       ├── native_clock.mdx                   # NativeClock API for high-performance clock driving
│       ├── testbench_generate.mdx             # Testbench auto-generation and customization
│       ├── xmake_params.mdx                   # All xmake configuration parameters
│       ├── special_env_variables.mdx          # Environment variables affecting Verilua
│       ├── simulator_control.mdx              # sim.finish, sim.fatal, simulation control API
│       ├── simulator_default_flags.mdx        # Default flags injected by xmake rule per simulator backend
│       ├── global_configuration.mdx           # Runtime global configuration
│       ├── bitvec.mdx                         # BitVec for wide bit-vector manipulation
│       ├── lua_utils.mdx                      # General utility functions
│       ├── str_bits_utils.mdx                 # String-based bit operations
│       ├── type_expect.mdx                    # Runtime type checking helpers
│       ├── type_overview.mdx                  # Instantiable type overview grouped by module
│       ├── slcp.mdx                           # String literal construction pattern for Bundle/AliasBundle
│       ├── queue.mdx                          # Queue, StaticQueue, AgeStaticQueue
│       ├── cross.mdx                          # Combinatorial Cross utility
│       ├── bundle_to_vlbc.mdx                 # BundleToVlbc: seal Lua components as .vlbc
│       ├── symbol_helper.mdx                  # Runtime symbol resolution
│       ├── sv_builder.mdx                     # SVBuilder for assertion + coverage generation
│       └── data_structure/
│           ├── index.mdx                      # Data structure overview
│           ├── callable_hdl.mdx               # CallableHDL: signal read/write handle
│           ├── bundle.mdx                     # Bundle: signal group with Decoupled support
│           ├── alias_bundle.mdx               # AliasBundle: signal group with alias renaming (recommended)
│           ├── proxy_table_handle.mdx         # ProxyTableHandle / dut: global signal proxy
│           └── event_handle.mdx               # EventHandle: task synchronization events
├── examples/                                  # Runnable example projects
│   ├── guided_tour/                           # Comprehensive API walkthrough in a single main.lua
│   ├── simple_mux/                            # Minimal HVL project (good starting point)
│   ├── simple_ut_env/                         # Unit-test environment pattern with monitor/scoreboard
│   ├── tutorial_example/                      # Step-by-step tutorial project
│   ├── fork_basics/                           # fork / jfork / join usage patterns
│   ├── async_queue_lua/                       # Async queue implemented in pure Lua
│   ├── async_queue_native/                    # Async queue using native implementation
│   ├── combinational_logic/                   # Combinational-logic testing example
│   ├── WAL/                                   # Offline waveform analysis examples
│   ├── HSE/                                   # HSE mode: embed Lua in running simulation
│   ├── HSE_dummy_vpi/                         # HSE with dummy VPI (DPI-based signal access)
│   └── HSE_virtual_rtl/                       # HSE with virtual RTL
├── tests/                                     # Integration tests and Lua unit tests (also serve as API usage examples)
├── docs-website/                              # Docusaurus site sources (sidebars.ts)
├── src/
│   ├── lua/verilua/                           # Lua runtime and public scripting APIs
│   │   ├── init.lua                           # Module entry point
│   │   ├── Verilua.lua                        # Core framework initialization
│   │   ├── LuaDut.lua                         # dut proxy implementation
│   │   ├── LuaSimulator.lua                   # Simulator control (sim.finish, etc.)
│   │   ├── LuaSimConfig.lua                   # Runtime global configuration
│   │   ├── LuaUtils.lua                       # General utility functions
│   │   ├── Cross.lua                          # Combinatorial Cross
│   │   ├── TypeExpect.lua                     # Runtime type checking
│   │   ├── TccWrapper.lua                     # TCC runtime C-compiler wrapper
│   │   ├── strict.lua                         # Strict-mode global checking
│   │   ├── coverage/                          # Coverage-related Lua helpers
│   │   ├── handles/                           # Signal handles
│   │   │   ├── LuaCallableHDL.lua             # CallableHDL implementation
│   │   │   ├── LuaBundle.lua                  # Bundle implementation
│   │   │   ├── LuaAliasBundle.lua             # AliasBundle implementation
│   │   │   └── ChdlAccess*.lua                # Signal access backends (Single/Double/Multi)
│   │   ├── utils/                             # Utility modules
│   │   │   ├── NativeClock.lua                # High-performance native clock driver
│   │   │   ├── BitVec.lua                     # Wide bit-vector manipulation
│   │   │   ├── Queue.lua                      # General-purpose queue
│   │   │   ├── StaticQueue.lua                # Fixed-capacity queue
│   │   │   ├── AgeStaticQueue.lua             # Queue with age tracking
│   │   │   ├── BundleToVlbc.lua               # Seal Lua components into encrypted .vlbc packages
│   │   │   ├── StrBitsUtils.lua               # String-based bit operations
│   │   │   ├── Logger.lua                     # Logging utility
│   │   │   ├── IDPool.lua                     # ID allocation pool
│   │   │   ├── SymbolHelper.lua               # Runtime symbol resolution
│   │   │   └── ...                            # DpiExporter, SignalDB, PerfCounter, etc.
│   │   ├── scheduler/                         # Coroutine scheduler (fork, join, posedge, etc.)
│   │   ├── random/                            # Randomization utilities
│   │   ├── sv/                                # SVBuilder + SV templates (assertion/coverage generation)
│   │   ├── vpiml/                             # VPI markup layer (normal / nosim backends)
│   │   ├── ext/                               # stdlib extensions (stringx, tablex)
│   │   └── tcc_snippet/                       # C snippets compiled at runtime via TCC
│   ├── wave_vpi/                              # Waveform backend (VCD/FST/FSDB readers)
│   ├── testbench_gen/                         # Testbench auto-generation tool
│   ├── signal_db_gen/                         # SignalDB generator
│   ├── dpi_exporter/                          # DPI code generator for signal access
│   ├── dummy_vpi/                             # VPI shim over generated DPI accessors
│   ├── cov_exporter/                          # Coverage instrumentation and export generator
│   ├── nosim/                                 # No-simulation analysis backend
│   ├── gen/                                   # Lua generators for scheduler and CHDL access
│   ├── include/                               # Common C/C++ headers
│   ├── sv_lint/                               # SystemVerilog lint tool (slang-backed)
│   ├── verilator/                             # Verilator main program and LightSSS support
│   └── ...                                    # Other subprojects (slang_common, etc.)
├── libverilua/                                # Core VPI implementation (Rust)
├── tools/                                     # Simulator launchers (vl-*) and tool CLI entry points (dpi_exporter, sv_lint, testbench_gen, ...)
├── scripts/                                   # Build scripts, xmake rules, and simulator toolchains
│   └── xmake/
│       ├── rules/verilua/xmake.lua            # Verilua xmake rule implementation
│       └── toolchains/                        # Simulator toolchains
│           ├── vcs/                           # VCS toolchain
│           ├── xcelium/                       # Xcelium toolchain
│           ├── wave_vpi/                      # WAL waveform toolchain
│           └── nosim/                         # No-simulation toolchain
├── xmake.lua                                  # Top-level build entry
└── ...                                        # AGENTS.md, DEVELOPMENT.md, CHANGELOG.md, etc.
```

## Source Order

When answering a Verilua usage question, consult sources in this order:

1. **`docs/navigation.mdx`** — read first for goal-oriented questions ("how do I do X?"); for file-location questions, the Project Structure above is sufficient
2. **Relevant docs page(s)** — from the Project Structure above
3. **Relevant example(s)** — from the Project Structure above
4. If still insufficient, look into `tests/` or `src/lua/verilua/` via the Fallback section below

## Fallback

If docs and examples are insufficient to answer the question, look into:

- `tests/test_*/` — integration tests that double as API usage examples
- `tests/test_*.lua` — Lua unit tests showing individual module behavior

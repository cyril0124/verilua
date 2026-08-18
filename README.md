<div align="center">
  <img src="./docs-website/static/img/logo.svg" height="96" alt="Verilua logo">
</div>

<div align="center">

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/cyril0124/verilua/regression.yml?style=for-the-badge)
![GitHub Release](https://img.shields.io/github/v/release/cyril0124/verilua?style=for-the-badge)
![GitHub commits since latest release](https://img.shields.io/github/commits-since/cyril0124/verilua/latest?style=for-the-badge)
![GitHub Created At](https://img.shields.io/github/created-at/cyril0124/verilua?style=for-the-badge)
[![Static Badge](https://img.shields.io/badge/Benchmark-8A2BE2?style=for-the-badge)](https://cyril0124.github.io/verilua-benchmark-results/dev/bench/)
![Static Badge](https://img.shields.io/badge/LuaJIT%202.1-blue?style=for-the-badge&logo=lua)


</div>

<div align="center">

[💻 **Guided tour**](./examples/guided_tour/main.lua)

[📖 **Documentation**](https://cyril0124.github.io/verilua/)

</div>

## 🔧 Introduction

`Verilua` is a versatile simulation framework for Hardware Verification based on `LuaJIT`. It can be used as a Hardwave Verification Language (`HVL`) to write testbenches and simulate hardware designs. Or it can be used as a Hardware Script Engine (`HSE`) to embed Lua scripts into the simulation. It can also be used as a Waveform Analysis Language(`WAL`) to analyze the provided waveform files(VCD, FST, FSDB, etc).


## 🚀 Getting Started

To get started with Verilua, visit our [documentation website](https://cyril0124.github.io/verilua/) for comprehensive installation guides, tutorials, API references, and examples. You can also try the [guided tour](./examples/guided_tour/main.lua) for a hands-on introduction.

## 📁 Project Structure

```
verilua/
├── docs/                    # Documentation sources (MDX)
├── docs-website/            # Docusaurus site
├── src/
│   ├── lua/verilua/         # Lua runtime & public scripting APIs
│   ├── gen/                 # Lua generators (scheduler, CHDL access)
│   ├── verilator/           # Verilator main program
│   ├── wave_vpi/            # Waveform backend (VCD/FST/FSDB)
│   ├── nosim/               # No-simulation analysis backend
│   ├── sv_lint/             # SystemVerilog lint (slang-backed)
│   ├── slang_common/        # Shared slang helpers for generators
│   ├── testbench_gen/       # Testbench generator
│   ├── signal_db_gen/       # SignalDB generator + shared lib
│   ├── dummy_vpi/           # VPI shim over generated DPI accessors
│   ├── dpi_exporter/        # DPI code generator for signal access
│   ├── cov_exporter/        # Coverage instrumentation exporter
│   ├── turso_ffi/           # Turso FFI DB backend (Rust)
│   └── include/             # Common C/C++ headers
├── libverilua/              # Rust VPI core & simulator shims
├── tests/                   # Tests (also API usage examples)
├── examples/                # Example projects & guided tour
├── scripts/
│   ├── .xmake/              # Xmake rules, plugins, simulator toolchains
│   └── conan/               # Conan packaging helpers
├── tools/                   # Simulator wrappers (vl-verilator, vl-vcs, …)
├── xmake.lua                # Top-level build entry
├── AGENTS.md                # Contributor / agent project map
└── DEVELOPMENT.md           # Generated-code & broader dev notes
```

## 💡 Why Lua/LuaJIT?

- 🚀 **High Performance**: LuaJIT, a Just-In-Time Compiler, transforms Lua code into native machine code, delivering exceptional speed and efficiency.
- ⚡ **Lightweight & Fast**: Lua boasts a minimal runtime and near-instant startup time, outpacing other dynamic languages like Python.
- 💫 **Seamless C Integration**: LuaJIT's Foreign Function Interface (FFI) enables efficient calls to C functions and libraries, and even supports calling Rust code, simplifying integration with native code.
- 👍 **Enhanced Development**: While Lua is dynamically typed, tools like [LuaLS](https://github.com/LuaLS/lua-language-server) and [EmmyLuaLs](https://github.com/EmmyLuaLs/emmylua-analyzer-rust) introduce a comment-based type system, significantly improving code clarity and developer experience.

## 🌟 Credits

- **[LuaJIT](https://github.com/LuaJIT/LuaJIT)** - A high-performance Lua implementation powering Verilua's speed and efficiency.
- **[Cocotb](https://github.com/cocotb/cocotb)** - A source of inspiration for Verilua's design and functionality.
- **[Slang](https://github.com/MikePopoloski/slang)** - A robust parser for Verilog/SystemVerilog files, integral to many tools in this repository.
- **[Xmake](https://github.com/xmake-io/xmake)** - The foundation of our streamlined and efficient build system.

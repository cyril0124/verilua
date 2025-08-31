<div align="center">

# 🌔 Verilua

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

`Verilua` is a versatile simulation framework for Hardware Verification based on `LuaJIT`. It can be used as a Hardwave Verification Language (`HVL`) to write testbenches and simulate hardware designs. Or it can be used as a Hardware Script Engine (`HSE`) to embed Lua scripts into the simulation. It can also can be used as a Waveform Analysis Language(`WAL`) to analyze the provided waveform files(VCD, FST, FSDB, etc).

## 📦 Installation(from release)

### Download from release
```bash
wget https://github.com/cyril0124/verilua/releases/download/v1.0.0/verilua-x64-ubuntu-22.04.zip

unzip verilua-x64-ubuntu-22.04.zip -d <path-to-install>
```

### Activate verilua
Add the following line to your `~/.bashrc` or `~/.zshrc`:
```bash
source <path-to-install>/verilua.sh
```

### Test installation
You need to reload your shell configuration file to activate verilua. After that, you can test the installation by running:
```bash
test_verilua
```
If you see the following output, then the installation is successful:
```bash
[test_verilua] Test verilua finished!
```

### Update verilua
To update the verilua to the latest version, you can run:
```bash
update_verilua
```
> [!IMPORTANT] 
> - Make sure that you have the permission to write to the verilua home directory(or verilua install directory).
> - `update_verilua` is only available if you have installed verilua from release.

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
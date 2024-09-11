# Verilua

`Verilua` is a versatile simulation framework for Hardware Verification based on `LuaJIT`. It can be used as a Hardwave Verification Language (`HVL`) to write testbenches and simulate hardware designs. Or it can be used as a Hardware Script Engine (`HSE`) to embed Lua scripts into the simulation. It can also can be used as a Waveform Analysis Language(`WAL`) to analyze the provided waveform files(VCD, FST, etc).

## Requirements
- [xmake](https://xmake.io/#/getting_started): we use xmake to build verilua, so you need to install xmake first.
- [conan](https://conan.io/downloads): xmake will use conan to manage dependencies, so you need to install conan.
It is fine if you dont't manually install conan. It will will be automatically installed once you install verilua.

## Install verilua
To install verilua, simply run the following command:
```bash
xmake install verilua
```
And to build the shared libraries, run the following command:
```bash
xmake -y -P .
```

## Usage
We provide some examples to show how to use verilua. The example is located in the `examples` directory.
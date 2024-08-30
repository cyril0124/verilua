# Verilua
## Requirements
- [xmake](https://xmake.io/#/getting_started): we use xmake to build verilua, so you need to install xmake first.
- [conan](https://conan.io/downloads): xmake will use conan to manage dependencies, so you need to install conan.

## Install verilua
To install verilua, simply run the following command:
```bash
xmake install verilua
```
And to build the shared libraries, run the following command:
```bash
xmake -y -P .
```

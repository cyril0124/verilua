# combinational_logic example

This example shows how to correctly read a combinational logic output after
driving its inputs with `set()`, using `await_rw()` and `await_rd()`.

The RTL design is a tiny valid/ready handshake: `ready = valid && (counter < 4)`.

## How to run

Run with the default simulator:

```bash
xmake b -P .
xmake r -P .
```

Run with another simulator:

```bash
SIM=iverilog xmake b -P .
SIM=iverilog xmake r -P .
```

You can also replace `iverilog` with `verilator`, `vcs`, or `xcelium` if that backend is available in your environment.

# fork_basics example

This example shows the basic task primitives in Verilua:

- `fork` for launching concurrent tasks
- `EventHandle` for task synchronization
- `jfork` and `join` for waiting on task completion

The RTL design is a tiny counter with `clock`, `reset`, and `enable` signals.
The Lua test drives the counter and checks the behavior of the task APIs above.

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

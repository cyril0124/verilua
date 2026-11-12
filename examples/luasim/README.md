# luasim examples

Run these examples from the repository root.

| Example | Directory | Covers |
| --- | --- | --- |
| Basic request/response | `examples/luasim` | 128-bit data, backpressure and a delayed response |
| AXI4Memory | [`axi4_memory`](./axi4_memory/README.md) | INCR bursts, byte write strobes and concurrent read/write |
| Combinational arbiter | [`comb_arbiter`](./comb_arbiter/README.md) | No clock, automatic propagation on input changes and priority selection |

For example, run AXI4Memory:

```bash
xmake build -P examples/luasim/axi4_memory
xmake run -P examples/luasim/axi4_memory
```

Use `-P examples/luasim` for the basic example and `-P examples/luasim/comb_arbiter` for the arbiter. luasim writes the waveform into the `build/luasim/tb_top/` directory of that example.

## Comparison with the SystemVerilog models

AXI4Memory and the arbiter each ship a `.sv` model with the same name. `main.lua` binds Lua signals or SV ports. It selects the target from `cfg.simulator`. Both models of an example share one driver: `AXI4Driver.lua` or `ArbiterDriver.lua`.

Without `SIM`, the example runs the Lua model. With `SIM=iverilog`, `SIM=vcs` or `SIM=verilator`, it runs the SV model:

```bash
SIM=iverilog xmake build -P examples/luasim/axi4_memory
SIM=iverilog xmake run -P examples/luasim/axi4_memory
```

One command runs both models and compares the sampled records line by line:

```bash
SIM=iverilog python3 examples/luasim/compare.py
```

`SIM` selects the RTL simulator for the comparison and defaults to Icarus. The script runs luasim first, then the selected SV backend. Add `--example axi4_memory` or `--example comb_arbiter` to compare one example only.

Results go to `examples/luasim/build/comparison/`. Each backend keeps its build log, run log and CSV. On a difference the script writes `difference.diff` and exits with a nonzero status.

The AXI comparison samples every channel signal on each rising edge. The combinational comparison samples the inputs and outputs after each `await_rw()`. It also covers several changes with the same timestamp.

These checks show that the sampled behavior matches for the two-state input scenarios listed. They are not a formal equivalence proof. They do not compare the internal delta-cycle scheduling of each simulator, and they do not cover X/Z.

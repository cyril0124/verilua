# A clockless two-input combinational arbiter

This example provides two implementations of a two-input ready/valid arbiter: one in Lua and one in SystemVerilog. Both share the same driver. Input 0 has priority. The model has no register, buffer or clock, so all outputs depend only on the current inputs.

```text
input0.valid / data ─┐
                    ├─ CombArbiter ─→ output.valid / data
input1.valid / data ─┘                       ↑
input0.ready / input1.ready ←──────── output.ready
```

## Run

Run from the repository root:

```bash
xmake build -P examples/luasim/comb_arbiter
xmake run -P examples/luasim/comb_arbiter
```

On success the run prints 13 `CHECK` lines and:

```text
PASS: clockless priority arbitration, data changes, backpressure and zero-time settling
```

The waveform is at `examples/luasim/comb_arbiter/build/luasim/tb_top/comb_arbiter.vcd`. The driver changes the test conditions every 10 ns to make the waveform easy to read. The combinational evaluation itself does not advance simulation time.

## SV comparison

`CombArbiter.sv` expresses the same selection and READY logic with `always_comb`. When `SIM` is set, `main.lua` binds the SV ports and does not start the Lua model. The driver and the assertions stay the same:

```bash
SIM=iverilog xmake build -P examples/luasim/comb_arbiter
SIM=iverilog xmake run -P examples/luasim/comb_arbiter
SIM=iverilog python3 examples/luasim/compare.py --example comb_arbiter
```

`ArbiterDriver.lua` records all inputs and outputs to `comb_trace.csv` after each `await_rw()` returns. The comparison uses 13 samples. They cover all 8 combinations of VALID and READY and a series of data changes within 30 ns. SV artifacts are under `build/<SIM>/CombArbiter/`. The check compares the settled values of the tested scenarios and does not require the same intermediate delta-cycle order.

## Automatic evaluation on input changes

`CombArbiter.start(input0, input1, output)` registers a change waiter on five input signals: two VALID, two DATA and the downstream READY. Each port consists of three `CallableHDL` handles: `valid`, `ready` and `data`. The data width in this example is 32 bits. After one start call, the driver only writes signals and waits for the result to settle.

```lua
CombArbiter.start(input0, input1, output)

input0.valid:set(1)
input0.data:set(0x11223344)
output.ready:set(1)
await_rw()

output.data:expect(0x11223344)
```

`await_edge_hdl()` wakes the watcher when an input value changes. The watcher reads the current inputs, updates the outputs with plain `set()` calls and waits for the next change. `await_rw()` waits until the inputs settle and the output writes they trigger complete. The driver never calls an evaluation function. The watcher stays suspended while nothing changes, so it needs no polling and no clock.

## Logic

```text
output.valid = input0.valid OR input1.valid
output.data  = input0.valid ? input0.data
             : input1.valid ? input1.data : 0
input0.ready = output.ready
input1.ready = output.ready AND NOT input0.valid
```

READY can be high while the matching VALID is 0. A transfer still needs both VALID and READY at 1.

This is a fixed-priority combinational selector without storage. It gives no fairness guarantee and does not lock the selection during backpressure. Output data can change while `output.ready=0`, so it is not a full AXI channel arbiter that holds the payload stable during a stall.

## Self-check scenarios

- Neither input valid, each input valid alone, and priority for input 0 when both compete.
- Data-only changes, READY-only changes, a data change on the unselected input, and two data changes with the same timestamp.
- Output backpressure, and a switch to input 1 when input 0 drops during that backpressure.
- Automatic propagation and zero-time settling: after an input change, `await_rw()` returns with the correct outputs and no increase in simulation time.

`main.lua` binds the ports. `ArbiterDriver.lua` holds the shared driver and assertions. `CombArbiter.lua` and `CombArbiter.sv` each implement the same selection rules.

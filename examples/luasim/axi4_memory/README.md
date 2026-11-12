# AXI4Memory: an AXI4 memory model without RTL

This example provides two memory slave models: `AXI4Memory.lua` and `AXI4Memory.sv`. By default it declares signals with `luasim.signal()` and runs the Lua model. Set `SIM` to switch to the SV model. Both models share `AXI4Driver.lua`, which drives the clock with NativeClock, sends requests on five AXI channels and checks the responses.

Run from the repository root:

```bash
xmake build -P examples/luasim/axi4_memory
xmake run -P examples/luasim/axi4_memory
```

On success the run prints:

```text
PASS: AXI4Memory bursts, WSTRB, channel backpressure, concurrent read/write and reset
```

The waveform is at `examples/luasim/axi4_memory/build/luasim/tb_top/axi4_memory.vcd`.

## Files

- `AXI4Memory.lua`: takes the clock, the active-low reset, the signal handle table and the capacity, then starts the memory model task.
- `AXI4Memory.sv`: the matching behavioral SV memory model. Its ports have the same names as the Lua handles.
- `main.lua`: declares Lua signals or binds SV ports, then starts the selected model.
- `AXI4Driver.lua`: the clock, transaction driver, assertions and per-cycle CSV recording shared by both models.
- `xmake.lua`: uses `@luasim` by default. `SIM=iverilog/vcs/verilator` selects the SV backend.

Model entry point:

```lua
AXI4Memory.start(clock, reset_n, axi, {
    size_bytes = 4096,
    stall_every = 3,
})
```

`axi` maps a signal name to a `CallableHDL`. The field list is in `widths` in `main.lua`. With `stall_every = 0` the model adds no request backpressure. With a value of 2 or more, the model drives AWREADY, WREADY and ARREADY low every N cycles. The master controls BREADY and RREADY.

## SV comparison

```bash
SIM=iverilog xmake build -P examples/luasim/axi4_memory
SIM=iverilog xmake run -P examples/luasim/axi4_memory
SIM=iverilog python3 examples/luasim/compare.py --example axi4_memory
```

The comparison uses the same 4 KiB capacity, the same backpressure every 3 cycles and a 10 ns clock. The Lua model defers output with `set()`. The SV model updates state on the rising edge and commits outputs with nonblocking assignments. Both apply the current cycle byte writes before the new cycle read data. Both clear only the transaction state on reset, not the memory contents.

Each rising edge samples the outputs before they update and writes one row to `axi4_trace.csv`. The script compares timestamps, reset and all AXI channel fields, not only the final read data. SV artifacts are under `build/<SIM>/AXI4Memory/`. Full comparison commands and the limits of the check are in the [parent README](../README.md#comparison-with-the-systemverilog-models).

## Model scope

| Item | Behavior |
| --- | --- |
| Address / data / ID | 32-bit byte address, 32-bit data, 4-bit transaction ID |
| Bursts | INCR, 1 to 256 beats, `AxSIZE=2`, 4-byte aligned, no 4 KiB boundary crossing |
| Concurrency | At most one outstanding burst per direction. The read and write directions run at the same time and keep their own order. |
| Writes | Separate AW and W channels. The W channel can assert VALID first, but the model accepts W data only after it receives AW. The model checks that WLAST matches AWLEN. |
| Byte strobes | Little-endian byte addressing. Each WSTRB bit controls one byte, and a zero strobe keeps the existing byte. |
| Responses | BID and RID return the request ID, and BRESP and RRESP are OKAY. VALID and the response payload stay stable during backpressure. |
| Reset | Sampled on the clock rising edge. It aborts outstanding transactions, clears the handshake outputs and keeps the memory contents. |
| Uninitialized memory | Reads return zero. A read of the same cycle write returns the written value. |

The model does not support FIXED or WRAP bursts, narrow transfers, unaligned access or exclusive access. It also supports only one outstanding transaction per direction and does not implement the optional sideband fields. The model stops with an error on an illegal burst type, size, alignment, address range, 4 KiB boundary or WLAST. It does not generate SLVERR or DECERR, and it is not a full AXI4 protocol checker.

## Demo transactions

1. Read an uninitialized region and check that every byte is zero.
2. Send W data before AW, then complete a four-beat write and read it back.
3. Overwrite selected bytes with different WSTRB values, then check that a zero strobe leaves data unchanged.
4. Run a 32-beat write and a read of another address at the same time, then read the whole burst back.
5. Access the end of the memory, then reset and confirm that the contents survive.

The driver updates requests on the falling edge and checks the handshake on the rising edge. The model uses deferred `set()` writes for its outputs, so the task execution order does not change the values sampled on the same edge. The driver blocks B and each R beat for several cycles and checks payload stability every cycle. A 20 µs simulation timeout reports an unfinished transaction as a failure.

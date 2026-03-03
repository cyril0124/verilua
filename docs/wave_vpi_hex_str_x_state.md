# wave_vpi: 在 `get_hex_str` 中支持 X/Z 态

## 背景

当前 wave_vpi 的 `vpiHexStrVal`（对应 Lua 的 `get_hex_str`）在遇到 X/Z 态信号时将其视为 `0`。
本文档描述如何修改使 `get_hex_str` 能正确输出 `x`/`z`。

> 其他取值方式（`vpiIntVal`、`vpiVectorVal` 等）返回数值类型，无法体现 X 态，保持现有行为（X→0）不变。

---

## 修改点

### 1. Wellen 后端 — `src/wave_vpi/wellen_impl/src/lib.rs`

#### 1a. FourValue 分支添加 `vpiHexStrVal` 处理

当前 `FourValue` 分支（第 716 行起）**没有 `vpiHexStrVal` handler**，会走到 `_ => todo!()`。

wellen 的 `to_bit_string()` 对 FourValue 已能输出 `'x'`/`'z'` 字符（查表 `FOUR_STATE_LOOKUP = ['0', '1', 'x', 'z']`），可以直接复用。

**在第 744 行（`_ =>` 之前）插入：**

```rust
SignalValue::FourValue(_data, bits) => {
    match v_format as u32 {
        // ... existing vpiVectorVal, vpiIntVal, vpiBinStrVal ...

        vpiHexStrVal => {
            let signal_bit_string =
                loaded_signal.get_value_at(&off, 0).to_bit_string().unwrap();
            let hex_string = bit_string_to_hex_with_xz(&signal_bit_string);
            let c_string = CString::new(hex_string).expect("CString::new failed");
            let c_str_ptr = c_string.into_raw();
            unsafe {
                (*value_p).value.str_ = c_str_ptr as *mut PLI_BYTE8;
            }
        }

        _ => { todo!("v_format => {}", v_format) }
    };
}
```

#### 1b. 新增辅助函数 `bit_string_to_hex_with_xz`

将含 x/z 的 bit string 转为 hex string。规则：若 4-bit nibble 中任意一位为 `x` 则该 nibble 输出 `x`，任意一位为 `z`（且无 `x`）则输出 `z`。

```rust
/// Convert a bit string (may contain 'x'/'z') to a hex string.
/// If any bit in a 4-bit nibble is 'x', the nibble becomes 'x'.
/// If any bit is 'z' (and none is 'x'), the nibble becomes 'z'.
fn bit_string_to_hex_with_xz(bit_str: &str) -> String {
    let len = bit_str.len();
    let padding = (4 - (len % 4)) % 4;
    let padded: String = "0".repeat(padding) + bit_str;

    let mut hex = String::with_capacity((len + padding) / 4);
    for chunk in padded.as_bytes().chunks(4) {
        let has_x = chunk.iter().any(|&b| b == b'x');
        let has_z = chunk.iter().any(|&b| b == b'z');
        if has_x {
            hex.push('x');
        } else if has_z {
            hex.push('z');
        } else {
            let mut nibble = 0u8;
            for &b in chunk {
                nibble = (nibble << 1) | (b - b'0');
            }
            hex.push(if nibble < 10 {
                (b'0' + nibble) as char
            } else {
                (b'a' + nibble - 10) as char
            });
        }
    }
    hex
}
```

#### 1c. Binary 分支的 `vpiHexStrVal`（第 651-699 行）

Binary（二态）信号不含 X/Z，**无需修改**。

---

### 2. FSDB 后端 — `src/wave_vpi/src/vpi_compat.cpp`

#### 2a. `vpiHexStrVal` case（第 922-978 行）

在 nibble 累加逻辑中，追踪该 nibble 是否含 X/Z 位。若含则输出 `'x'`/`'z'`。

**修改 for 循环内的 switch（第 936-958 行）：**

```cpp
case vpiHexStrVal: {
    static const char hexLookUpTable[] = {
        '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'
    };
    switch (bpb) {
    [[likely]] case FSDB_BYTES_PER_BIT_1B: {
        int bufferIdx = 0;
        int tmpVal    = 0;
        int tmpIdx    = 0;
        bool hasX     = false;  // NEW
        bool hasZ     = false;  // NEW
        int chunkSize = (bitSize % 4 == 0) ? bitSize / 4 : bitSize / 4 + 1;

        for (int i = bitSize - 1; i >= 0; i--) {
            switch (retVC[i]) {
            case FSDB_BT_VCD_0:
                break;
            case FSDB_BT_VCD_1:
                tmpVal += 1 << tmpIdx;
                break;
            case FSDB_BT_VCD_X:
                hasX = true;   // CHANGED: track X instead of ignoring
                break;
            case FSDB_BT_VCD_Z:
                hasZ = true;   // CHANGED: track Z instead of ignoring
                break;
            default:
                VL_FATAL(false, "unknown verilog bit type found. i: {}", i);
            }
            tmpIdx++;
            if (tmpIdx == 4) {
                if (hasX)
                    buffer[chunkSize - 1 - bufferIdx] = 'x';     // NEW
                else if (hasZ)
                    buffer[chunkSize - 1 - bufferIdx] = 'z';     // NEW
                else
                    buffer[chunkSize - 1 - bufferIdx] = hexLookUpTable[tmpVal];
                tmpVal = tmpIdx = 0;
                hasX = hasZ = false;  // NEW: reset per nibble
                bufferIdx++;
            }
        }
        if (tmpIdx != 0) {
            if (hasX)
                buffer[chunkSize - 1 - bufferIdx] = 'x';         // NEW
            else if (hasZ)
                buffer[chunkSize - 1 - bufferIdx] = 'z';         // NEW
            else
                buffer[chunkSize - 1 - bufferIdx] = hexLookUpTable[tmpVal];
            bufferIdx++;
        }
        buffer[bufferIdx] = '\0';
        break;
    }
    // ... FSDB_BYTES_PER_BIT_4B/8B unchanged ...
    }
    value_p->value.str = (char *)buffer;
    break;
}
```

#### 2b. JIT-Optimized Path（第 754-759 行）

JIT 路径使用 `optValueVec` 存储的是 `uint32_t` 值，已经是二态的（不含 X/Z），**无需修改**。

---

### 3. 不需要修改的部分

| 组件 | 原因 |
|------|------|
| `libverilua/src/vpi_access/value_getters.rs` | `vpiml_get_value_hex_str` 直接透传 `vpi_get_value` 返回的字符串，只要 wave_vpi 返回含 `x`/`z` 的字符串即可 |
| `src/lua/verilua/handles/LuaCallableHDL.lua` | `get_hex_str` 调用 `ffi_string(vpiml.vpiml_get_value_hex_str(this.hdl))`，透传字符串 |
| `vpiIntVal` / `vpiVectorVal` | 数值类型无法表示 X，保持 X→0 |
| `vpiBinStrVal`（Wellen） | FourValue 的 `to_bit_string()` 已输出 `'x'`/`'z'`，无需改动 |

---

### 4. JIT 优化与 X/Z 态

wave_vpi 的 JIT 优化路径使用 `optValueVec`（`uint32_t`）存储预计算的信号值，是二态的，无法表示 X/Z。
当测试需要验证 X/Z 态时，通过环境变量 `WAVE_VPI_ENABLE_JIT=0` 关闭 JIT 优化，
使 wave_vpi 始终走正常的 FSDB/Wellen 读取路径以保留 X/Z 信息。

在 xmake.lua 中通过 `add_runenvs("WAVE_VPI_ENABLE_JIT", "0")` 设置。

---

## 修改文件清单

| 文件 | 改动 |
|------|------|
| `src/wave_vpi/wellen_impl/src/lib.rs` | 新增 `bit_string_to_hex_with_xz()` 函数；FourValue 分支添加 `vpiHexStrVal` 处理 |
| `src/wave_vpi/src/vpi_compat.cpp` | `vpiHexStrVal` case 中增加 `hasX`/`hasZ` 追踪，输出 `'x'`/`'z'` 字符；`vpiBinStrVal` 修复 X/Z 输出 |
| `tests/test_wave_vpi_x/` | 新增 X 态测试目录（Design.v, gen_wave_main.lua, sim_wave_main.lua, xmake.lua） |
| `xmake.lua`（顶层） | Section 9 "WaveVpi Tests" 中新增 test_wave_vpi_x 测试 |

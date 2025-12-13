# String Literal Constructor Pattern (SLCP)

SLCP（String Literal Constructor Pattern，字符串字面量构造器模式）是 Verilua 中的一种核心设计模式，通过扩展 Lua 的 `string` 库，使得用户可以直接使用字符串字面量来构建各种 Verilua 数据结构，而无需显式 `require` 相应的模块。

## 设计动机

在传统的 Lua 编程中，构建一个对象通常需要先 `require` 对应的模块：

```lua
local CallableHDL = require "LuaCallableHDL"
local Bundle = require "LuaBundle"

local clock = CallableHDL("clock", "tb_top.clock")
local bdl = Bundle({"valid", "ready"}, "", "tb_top.dut", "my_bundle", true)
```

这种方式虽然清晰，但在硬件验证场景中存在一些不便：

1. **导入繁琐**：每个测试文件都需要导入多个模块
2. **代码冗长**：构造函数的参数列表可能很长
3. **降低可读性**：真正的业务逻辑被大量的模板代码淹没

SLCP 的设计目标就是解决这些问题，让用户能够以更简洁、更直观的方式构建 Verilua 数据结构。

## 核心原理

SLCP 利用了 Lua 语言的一个重要特性：**所有字符串共享同一个 metatable**。

在 Lua 中，字符串类型的 metatable 的 `__index` 字段指向 `string` 表。这意味着：

```lua
-- 这两种写法是等价的
local upper = string.upper("hello")
local upper = ("hello"):upper()
```

基于这个特性，Verilua 向 `string` 表添加了一系列方法，使得所有字符串字面量都可以调用这些方法来构建各种数据结构：

```lua
-- 向 string 表添加方法
string.chdl = function(hierpath, hdl)
    return CallableHDL(hierpath, "", hdl)
end

-- 然后就可以这样使用
local clock = ("tb_top.clock"):chdl()
```

## 支持的构造器

下表列出了 SLCP 支持的所有构造器方法：

| 方法                | 返回类型           | 说明                                |
|---------------------|--------------------|------------------------------------|
| `<str>:hdl()`       | ComplexHandleRaw   | 获取 VPI 底层句柄                   |
| `<str>:hdl_safe()`  | ComplexHandleRaw   | 安全获取 VPI 句柄（不存在返回 -1）   |
| `<str>:chdl()`      | CallableHDL        | 构建可调用信号句柄                  |
| `<str>:fake_chdl{}` | CallableHDL        | 构建虚拟信号句柄                    |
| `<str>:bdl{...}`    | Bundle             | 构建信号组                          |
| `<str>:bundle{...}` | Bundle             | 同 `:bdl{...}`                      |
| `<str>:abdl{...}`   | AliasBundle        | 构建带别名的信号组                  |
| `<str>:ehdl()`      | EventHandle        | 构建事件句柄                        |
| `<str>:bv()`        | BitVec             | 构建位向量                          |
| `<str>:bit_vec()`   | BitVec             | 同 `:bv()`                          |
| `<str>:auto_bundle{}`| Bundle            | 自动构建信号组                      |

## 详细用法

### CallableHDL 构造

`CallableHDL` 是 Verilua 中最常用的信号句柄类型，用于读写硬件信号。

```lua
-- 基本用法
local clock = ("tb_top.clock"):chdl()
local reset = ("tb_top.reset"):chdl()

-- 访问深层信号
local data = ("tb_top.u_dut.path.to.data"):chdl()

-- 使用信号
clock:posedge()           -- 等待上升沿
local value = data:get()  -- 读取值
data:set(0x123)           -- 设置值
```

### Bundle 构造

`Bundle` 用于将多个相关信号组织在一起，特别适合处理接口信号。

```lua
-- 基本 Bundle
local io = ("valid | ready | data | addr"):bdl {
    hier = "tb_top.u_dut",
    prefix = "io_",
    name = "IO Bundle"
}

-- 访问信号
io.valid:set(1)
io.data:set(0xABCD)

-- Decoupled Bundle（类似 Chisel 的 DecoupledIO）
local axi_ch = ("valid | ready | data | id"):bdl {
    hier = "tb_top.u_dut",
    prefix = "axi_w_",
    is_decoupled = true,
    name = "AXI Write Channel"
}

-- 检查握手
if axi_ch:fire() then
    print("Transaction completed!")
end
```

多行格式（推荐用于较多信号的情况）：

```lua
local bus = ([[
    | valid
    | ready
    | address
    | data
    | strobe
    | resp
]]):bdl {
    hier = "tb_top.u_bus",
    prefix = "bus_",
    is_decoupled = true,
    name = "Bus Interface"
}
```

可选信号（使用方括号语法）：

```lua
-- 使用方括号标记可选信号
local io = ([[
    | valid
    | ready
    | data
    | [debug_info]  -- 可选信号，不存在时不会报错
]]):bdl {
    hier = "tb_top.u_dut",
    prefix = "io_"
}

-- 旧方法（仍然有效）
local io_old = ("valid | ready | data | debug_info"):bdl {
    hier = "tb_top.u_dut",
    prefix = "io_",
    optional_signals = {"debug_info"}
}
```

### AliasBundle 构造

`AliasBundle` 允许为信号创建别名，提高代码可读性。

```lua
-- 使用 => 创建别名
local ctrl = ([[
    | io_in_start => start
    | io_in_stop  => stop
    | io_out_done => done
    | io_out_error => error
]]):abdl {
    hier = "tb_top.u_ctrl",
    name = "Control Signals"
}

-- 通过别名访问
ctrl.start:set(1)
if ctrl.done:get() == 1 then
    print("Operation completed!")
end

-- 支持多个别名（用 / 分隔）
local sig = ([[
    | some_very_long_signal_name => short/alias1/alias2
]]):abdl {
    hier = "tb_top"
}

-- 以下访问方式都是等价的
sig.short:get()
sig.alias1:get()
sig.alias2:get()

-- 可选信号（使用方括号语法）
local ctrl_with_opt = ([[
    | io_in_start => start
    | io_in_stop  => stop
    | [io_debug_port => debug]
]]):abdl {
    hier = "tb_top.u_ctrl"
}

-- 旧方法（仍然有效）
local ctrl_old = ([[
    | io_in_start => start
    | io_in_stop  => stop
    | io_debug_port => debug
]]):abdl {
    hier = "tb_top.u_ctrl",
    optional_signals = {"debug"}
}
```

支持字符串插值：

```lua
local ch = ([[
    | channel_{n}_valid => valid
    | channel_{n}_data  => data
]]):abdl {
    hier = "tb_top.u_router",
    n = 3  -- 将 {n} 替换为 3
}
-- 实际信号路径: tb_top.u_router.channel_3_valid
```

### BitVec 构造

`BitVec` 用于处理大位宽的数据。

```lua
-- 从十六进制字符串构造
local bv = ("deadbeef"):bv(128)  -- 128 位的 BitVec

-- 操作位字段
local field = bv:get_bitfield(0, 31)
bv:set_bitfield(32, 63, 0x12345678)

-- 转换为字符串
local hex_str = bv:get_bitfield_hex_str(0, 127)
```

### EventHandle 构造

`EventHandle` 用于任务间的同步与通信。

```lua
-- 创建事件句柄
local tx_done = ("tx_complete"):ehdl()
local rx_ready = ("rx_ready"):ehdl(1)  -- 带 ID

-- 在一个任务中等待事件
fork {
    function()
        tx_done:wait()
        print("TX completed!")
    end
}

-- 在另一个任务中触发事件
tx_done:fire()
```

### 虚拟信号构造

`fake_chdl` 用于创建不存在于实际设计中的虚拟信号，便于测试和调试。

```lua
local fake_sig = ("virtual.signal"):fake_chdl {
    get = function(self)
        return 42  -- 总是返回 42
    end,
    set = function(self, value)
        print("Setting virtual signal to", value)
    end,
    is = function(self, value)
        return value == 42
    end
}

-- 像普通信号一样使用
assert(fake_sig:get() == 42)
fake_sig:set(100)  -- 打印 "Setting virtual signal to 100"
```

### 自动 Bundle 构造

`auto_bundle` 可以根据模式自动匹配信号创建 Bundle。

```lua
-- 使用 SignalDB 自动发现信号
local io_bdl = ("tb_top.u_dut"):auto_bundle {
    startswith = "io_in_",  -- 匹配以 io_in_ 开头的信号
}

-- 更多匹配选项
local data_bdl = ("tb_top.u_dut"):auto_bundle {
    endswith = "_data",      -- 匹配以 _data 结尾的信号
}

local wide_bdl = ("tb_top.u_dut"):auto_bundle {
    filter = function(name, width)
        return width >= 32   -- 只包含位宽 >= 32 的信号
    end
}
```

## 其他字符串扩展方法

除了数据结构构造器，SLCP 还提供了一些实用的字符串操作方法：

### 字符串渲染

```lua
local template = "Hello {{name}}, your score is {{score}}!"
local result = template:render({
    name = "Alice",
    score = 100
})
-- result: "Hello Alice, your score is 100!"
```

### 数值转换

```lua
-- 支持多种进制
local dec = ("42"):number()      -- 42
local hex = ("0x2A"):number()    -- 42
local bin = ("0b101010"):number() -- 42
```

### 子串检查

```lua
local s = "hello world"
assert(s:contains("world") == true)
assert(s:contains("moon") == false)
```

### 后缀移除

```lua
local s = "signal_valid"
local result = s:strip("_valid")  -- "signal"
```

### 枚举定义

```lua
local Color = ("Color"):enum_define {
    Red = 1,
    Green = 2,
    Blue = 3
}

assert(Color.Red == 1)
assert(Color(1) == "Red")  -- 反向查找
```

### TCC 编译

SLCP 还支持在运行时编译 C 代码：

```lua
local lib = ([[
    int add(int a, int b) {
        return a + b;
    }
]]):tcc_compile({
    {sym = "add", ptr = "int (*)(int, int)"}
})

local result = lib.add(1, 2)  -- 3
```

## 最佳实践

### 1. 优先使用 SLCP

对于简单的信号访问，优先使用 SLCP 而不是传统的 `require` 方式：

```lua
-- 推荐
local clock = ("tb_top.clock"):chdl()

-- 不推荐（除非需要更多控制）
local CallableHDL = require "LuaCallableHDL"
local clock = CallableHDL("clock", "tb_top.clock")
```

### 2. 使用多行格式提高可读性

对于包含多个信号的 Bundle，使用多行格式：

```lua
-- 推荐
local bus = ([[
    | req_valid
    | req_ready
    | req_addr
    | req_data
    | resp_valid
    | resp_data
]]):bdl { hier = "tb_top.u_bus" }

-- 不推荐
local bus = ("req_valid|req_ready|req_addr|req_data|resp_valid|resp_data"):bdl { hier = "tb_top.u_bus" }
```

### 3. 合理使用别名

当信号名称过长或不够直观时，使用 `abdl` 创建别名：

```lua
local ctrl = ([[
    | auto_generated_very_long_signal_name_for_start => start
    | auto_generated_very_long_signal_name_for_done  => done
]]):abdl { hier = "tb_top.u_ctrl" }

-- 使用简洁的别名
ctrl.start:set(1)
ctrl.done:expect(1)
```

### 4. 结合 dut 使用

SLCP 可以与 `dut` 代理表配合使用：

```lua
-- 使用 dut 获取路径，再用 SLCP 构建 Bundle
local hier = dut.u_top.u_bus:get_local_path()
local bus = ("valid | ready | data"):bdl { hier = hier }
```

## 总结

SLCP 是 Verilua 的核心设计模式之一，它通过巧妙地利用 Lua 的语言特性，为用户提供了一种简洁、直观的方式来构建各种数据结构。理解并善用这一模式，可以显著提高验证代码的可读性和开发效率。

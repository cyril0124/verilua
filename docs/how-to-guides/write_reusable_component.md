# 编写可复用的验证组件

Verilua 提倡编写{==可复用的验证组件==}，以便在多个场景（HVL、HSE、WAL）下复用，例如常见的 Monitor 组件，或者 Scoreboard 组件。

## 使用 Bundle 编写验证组件

正常情况下，Verilua 中可以通过一系列的[数据结构](../reference/data_structure.md) 来和硬件信号进行交互，但是在这些数据结构通常需要指定一些和当前设计信号相关的信息从而才能构建出来，例如 hierarchy path、signal name 等。

针对这两个信息，不同的 DUT 下可能会有所不同，有可能是 hierarchy path 不同，例如在 DUT_A 中，hierarchy path 是 `tb_top.path.to.mod`，在 DUT_B 中是 `tb_top.another.path.to.mod`，也有可能是 signal name 不同，例如在 DUT_A 中，signal name 是 `valid` 和 `value`，在 DUT_B 中是 `vld` 和 `value_2`。假设我们的一个验证组件 `Monitor` 需要接收一个 `Bundle` 来作为信号输入来监测前面提到的这两个信号，作用是当 `valid` 或 `vld` 有效的时候，打印出当前的 `value` 或 `value_2` 的值：

```lua title="Monitor.lua" linenums="1" hl_lines="13 14"
local class = require "pl.class"
local texpect = require "TypeExpect"

local Monitor = class()

function Monitor:_init(signals)
    texpect.expect_bdl(signals, "signals")

    self.signals = signals
end

function Monitor:sample(cycles)
    if self.signals.valid:is(1) then
        print("[Monitor] get value =>", self.signals.value:get_hex_str(), "at", cycles)
    end
end
```

上述代码的相关说明如下：

- `#!lua local class = require "pl.class"` 这里使用到了 penlight 库的 class，具体可以参考 [penlight 官方文档](https://lunarmodules.github.io/Penlight)。

- `#!lua local texpect = require "TypeExpect"` 这里使用到了 Verilua 内置的 `TypeExpect` 模块，具体可以参考 [TypeExpect 模块](https://github.com/cyril0124/verilua/blob/master/src/lua/verilua/TypeExpect.lua)，主要用来检查参数的类型。

- `#!lua texpect.expect_bdl(signals, "signals")` 的作用和下面是一样的：
    ```lua
    assert(type(signals) == "table")
    assert(signals.__type == "Bundle")
    ```
    
    !!! tip "Verilua 的数据结构都有 `__type` 字段，这个字段用来表示这个数据结构的类型"

有了上述的模块，我们在 DUT_A 中可以这样创建并使用：

```lua title="test_dut_a.lua" linenums="1"
local Monitor = require "Monitor"

local signals_bdl = ([[
    | valid
    | value
]]):bdl {hier = "tb_top.path.to.mod", prefix = "", is_decoupled = false}

local mon = Monitor(signals_bdl)

fork {
    function ()
        -- ...

        dut.clock:posedge(100, function (c)
            mon:sample(c)
        end)
        
        -- ...

        sim.finish()
    end
}
```

上述代码在 DUT_A 中可以完美使用，但是如果我们在 DUT_B 中使用，则需要改动一下 `Monitor.lua` 的内容来适配 DUT_B 中的不一样的信号信息：

- 在 `Monitor.lua` 中的第 13 行，将 `valid` 改为 `vld`；
- 在 `Monitor.lua` 中的第 14 行，将 `value` 改为 `value_2`。

这样我们就得到了下面的代码：

```lua title="Monitor_1.lua" linenums="1" hl_lines="13 14"
local class = require "pl.class"
local texpect = require "TypeExpect"

local Monitor = class()

function Monitor:_init(signals)
    texpect.expect_bdl(signals, "signals")

    self.signals = signals
end

function Monitor:sample(cycles)
    if self.signals.vld:is(1) then
        print("[Monitor] get value =>", self.signals.value_2:get_hex_str(), "at", cycles)
    end
end
```

可以看到和 `Monitor.lua` 一样，只是在 `Monitor.lua` 中的第 13 行和第 14 行中的 `valid` 和 `value` 改为了 `vld` 和 `value_2`。

我们同样可以在 DUT_B 中使用：

```lua title="test_dut_b.lua" linenums="1" hl_lines="1 4 5 6"
local Monitor = require "Monitor_1"

local signals_bdl = ([[
    | vld
    | value_2
]]):bdl {hier = "tb_top.another.path.to.mod", prefix = "", is_decoupled = false}

local mon = Monitor(signals_bdl)

fork {
    function ()
        -- ...

        dut.clock:posedge(100, function (c)
            mon:sample(c)
        end)
        
        -- ...

        sim.finish()
    end
}
```

这样的做法就会导致原本可以复用的 `Monitor` 组件因为信号信息不同而不得不重新编写。核心的问题在于两个 DUT 中的信号命名不一样，我们的 `Monitor` 组件实现的时候使用的是某个 DUT 中的信号，如果在另一个 DUT 中使用，那么就需要改动一下 `Monitor.lua` 代码，将信号名进行对应的修改。

## 使用 AliasBundle 编写验证组件

我们可以使用 [`AliasBundle`](../reference/data_structure.md#aliasbundle) 来解决这个问题，`Monitor` 组件可以接收一个 `AliasBundle` 作为信号输入（代替原有的 `Bundle`） ，在 `AliasBundle` 可以对信号创建别名，这个别名在 DUT_A 中和 DUT_B 中都可以设置成一样的，这样我们的 `Monitor` 组件不需要做任何修改，就可以在不同的 DUT 中使用了。

下面是一个例子：

```lua title="Monitor.lua" linenums="1" hl_lines="7"
local class = require "pl.class"
local texpect = require "TypeExpect"

local Monitor = class()

function Monitor:_init(signals)
    texpect.expect_abdl(signals, "signals", { "valid", "value" })

    self.signals = signals
end

function Monitor:sample(cycles) 
    if self.signals.valid:is(1) then
        print("[Monitor] get value =>", self.signals.value:get_hex_str(), "at", cycles)
    end
end
```

上述代码中，使用了 `texpect.expect_abdl(signals, "signals", { "valid", "value" })` 来确保用户输入的 `signals` 是一个 `AliasBundle`，其中包含了 `valid` 和 `value` 两个信号。

在 DUT_A 中可以这样使用：
```lua title="test_dut_a.lua" linenums="1" hl_lines="4 5"
local Monitor = require "Monitor"

local signals_bdl = ([[
    | valid => valid
    | value => value
]]):abdl {hier = "tb_top.path.to.mod", prefix = ""}
-- or
-- local signals_bdl = ([[
--     | valid
--     | value
-- ]]):abdl {hier = "tb_top.path.to.mod", prefix = ""}

local mon = Monitor(signals_bdl)

-- ...
```

在 DUT_B 中可以这样使用：
```lua title="test_dut_b.lua" linenums="1" hl_lines="4 5"
local Monitor = require "Monitor"

local signals_bdl = ([[
    | vld => valid
    | value_2 => value
]]):abdl {hier = "tb_top.another.path.to.mod", prefix = ""}

local mon = Monitor(signals_bdl)

-- ...
```

这样我们在 DUT_A 和 DUT_B 中都可以复用同一个 `Monitor` 组件了，不需要因为具体的信号名称不同而修改 `Monitor` 的代码。

## 总结

通过上面的例子，我们可以使用 `AliasBundle` 结合 `TypeExpect` 可以编写出一个可复用的验证组件，并且在不同的 DUT 中使用。`TypeExpect` 的 `expect_abdl` 方法还能检查信号的位宽是否满足要求，具体可以参考[此处](https://github.com/cyril0124/verilua/blob/master/src/lua/verilua/TypeExpect.lua)的代码。
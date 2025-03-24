# 数据结构

在 `Verilua` 中，硬件信号通常被建模为 `Handle`，这也是 `Verilua` 中数据结构的主要命名方式。`Handle` 有多种类型：

1. CallableHDL(`chdl`)

    与信号进行操作的一个底层数据结构，提供了信号赋值和读取等接口，其中还包括了各种硬件信号相关的 Meta 信息，例如 width、hierarchy path。

2. Bundle(`bdl`)

    一种将多个信号封装在一起的数据结构，参考了 `Chisel` 的概念，因此支持 Decoupled 和 Valid 等子类型，能够统一管理多个 `chdl`。 

3. AliasBundle(`abdl`)

    一种特殊的 `bdl`，允许用户为信号组中的部分信号提供**别名**，从而提高代码可读性，同时仍支持对底层 `chdl` 的直接访问。

4. ProxyTableHandle(`dut`)

    通过全局 ProxyTable 智能解析路径（hierarchy path），支持与 `chdl` 几乎相同的信号操作接口，用户可直接访问信号，无需显式构造 `chdl` 或 `bdl`，简化访问复杂性，提升代码灵活性和可维护性。但是这种访问方式的设计之初主要是为了快速的临时访问信号，因此性能是不如 `chdl` 的。

5. EventHandle(`ehdl`)

    用于任务同步与通信，通过事件机制实现任务间的协调，用户可创建不同 `ehdl` 来同步任务执行顺序。需要注意的是，Event Handle 并非用于直接操作信号，而是用于管理任务之间的同步与通信，确保任务按预期顺序执行。

<figure markdown="span">
  ![Verilua data structure](./images/verilua_dsl_datastructure.png){ width="100%" }
  <figcaption>Verilua data structure</figcaption>
</figure>

## CallableHDL

### 创建 CallableHDL
#### 使用 dut 创建
使用 `dut` 来创建 `chdl` 需要完整的使用 `dut` 表示出一个信号的 hierarchy path（这里的 `dut` 表示的是 Testbench 的模块名称，默认是 `tb_top`），例如：
```lua linenums="1"
local signal = dut.path.to.signal:chdl()
```
通常对于一些 DUT 的**顶层信号**，可以使用 `dut.xxx` 表示，例如：
```lua linenums="1"
local signal = dut.clock:chdl()
local signal2 = dut.reset:chdl()
```
对于 DUT 的内部信号，可以使用 `dut.u_<top_module_name>.<internal_signal_name>` 表示，具体原因可以查看[此处的说明](../getting-started/simple_hvl_example.md#about-dut)，代码例子如下： 
```lua linenums="1"
local signal = dut.u_Design.value:chdl()
```

#### 使用 class 创建
本质上 `CallableHDL` 是一个 class，因此可以使用类似 `class` 的方式创建，例如：
```lua linenums="1" 
local CallableHDL = require "LuaCallableHDL"

local chdl = CallableHDL("name of the chdl", "tb_top.clock")

-- equivalent to

local chdl = dut.clock:chdl()
```
`CallableHDL` 接收两个参数，第一个是 `chdl` 的名称，第二个则是信号的完整 hierarchy path。

#### 使用 string literal 创建
Lua 的允许重载 string 的 `metatable`，Verilua 基于这个机制实现了一种简化的方式来创建 `chdl`, 例如：
```lua linenums="1"
local chdl = ("tb_top.clock"):chdl()
```
这种方式在 Verilua 中被称为 **S**tring **L**iteral **C**onstructor **P**attern（SLCP），使用 SLCP 的好处在于可以不用像 `class` 构建那样提前使用 `#!lua require` 将 `LuaCallableHDL` 加载代码中，而是在使用时根据后缀的方法名（`:chdl()`）来直接创建 `chdl`。 除了 `chdl` 之外，其他的数据结构同样也支持使用 SLCP 的方式来创建。


### CallableHDL 接口
`CallableHDL` 支持多种信号操作接口，且相关接口函数的功能会与具体信号的位宽有关，因此在使用时需要注意一些细节。

Verilua 中根据信号的位宽不同，隐式地将 `chdl` 分为了三种类型：

1. Single：位宽 <= 32 bit 的信号
2. Double：位宽 > 32 bit 且 <= 64 bit 的信号
3. Multi：位宽 > 64 bit 的信号

!!! warning "在后续的 API 介绍的内容中，如果没有特别写出针对这三种情况的说明，那么默认情况下相关 API 的行为都是一致的"

!!! note "之所以会有区分是为了尽可能针位宽实施更多性能上的优化"

!!! note "`beat` 的概念"
    硬件信号的位宽是没有限制的，但是在 Lua 中普通的 number 类型能够保存 32 bit 的数值，因此 Verilua 以 32 bit 为单位来表示一部分的信号的值，这个单位称为 `beat`。例如：1 ～ 32 bit 的信号可以用 1 个 beat 来表示，33 ～ 64 bit 的信号可以用 2 个 beat 来表示，以此类推。beat 的概念在后续的 API 介绍中会经常遇到。

#### 信号读取

1. `#!lua <chdl>:get()`

    === "Single"
        返回一个 Lua 的 number 类型的数值，表示当前的信号值。
    === "Double"
        `#!lua <chdl>:get(force_multi_beat)`
        
        - 如果 `force_multi_beat` 为 `true`，那么返回的是一个类型为 `uint32_t[]` 的 LuaJIT `cdata`，这个 `cdata` 的大小为 2，可以使用 `[1]` 访问第一个元素，`[2]` 访问第二个元素，由于 `cdata` 不是 Lua 的 `table` 因此实际上 `[0]` 也是可以访问的，但是这里 Verilua 会将 `[0]` 赋值为 beat 的大小，也就是这里的 2。

            !!! note "这里的 `cdata` 的 index 从 1 开始，这与 Lua 的 `table` 的 index 是一样的"

        - 如果 `force_multi_beat` 为 `false`，那么返回的是 `uint64_t` 类型的数值，由于 Double 类型的 `chdl` 的位宽为 32 ～ 64 bit，因此可以完整表达当前的数值。
    === "Multi"
        返回的是一个类型为 `uint32_t[]` 的 LuaJIT `cdata`，这个 `cdata` 的大小为当前信号的 beat 数，可以使用 `[1]` 访问第一个元素，`[2]` 访问第二个元素，以此类推， `[0]` 也是可以访问的，但是这里 Verilua 会将 `[0]` 赋值为 beat 的大小，例如对于 128 bit 的信号，`[0]` 会被赋值为 4。

2. `#!lua <chdl>:get64()`

    === "Single"
        返回一个 Lua 的 number 类型的数值，表示当前的信号值。
    === "Double / Multi"
        返回 `uint64_t` 类型的数值，由于 Double 类型的 `chdl` 的位宽为 32 ～ 64 bit，因此可以完整表达当前的数值，但是对于 Multi 类型的 `chdl`，此时 beat 大于 2，因此返回的 `uint64_t` 类型的数值不能完整表示当前的信号值，只会返回低 64 bit 的值。

3. `#!lua <chdl>:get_bitvec()`

    返回一个 `BitVec`，关于 `BitVec` 可以查看 [BitVec](./bitvec.md) 的文档。

4. `#!lua <chdl>:get_str(fmt)`

    获得当前信号的数值，并以 String 的类型返回，接受一个 `fmt` 参数，用于指定返回的字符串的格式，可以是 `HexStr`、`BinStr`、`DecStr`。

    ```lua
    local signal = dut.value:chdl()

    local value = signal:get()
    assert(value == 0x123)

    local value_hex_str = signal:get_str(HexStr) 
    assert(value_hex_str == "123")

    local value_bin_str = signal:get_str(BinStr) 
    assert(value_bin_str == "100100011")

    local value_dec_str = signal:get_str(DecStr) 
    assert(value_dec_str == "291")
    ```

    !!! warning "这里的 `HexStr`、`BinStr`、`DecStr` 是 Verilua 预定义的全局变量，可以直接使用"

5. `#!lua <chdl>:get_hex_str()`

    获得当前信号的数值，并以 Hex String 的类型返回。

    ```lua
    local signal = dut.value:chdl()

    local value = signal:get()
    assert(value == 0x123)
    
    local value_hex_str = signal:get_hex_str()
    assert(value_hex_str == "123")
    ```

6. `#!lua <chdl>:get_dec_str()` 
    
    类似 `get_hex_str`，但是返回的是 Decimal String 类型的字符串。

7. `#!lua <chdl>:get_bin_str()`

    类似 `get_hex_str`，但是返回的是 Binary String 类型的字符串。


#### 信号赋值

1. `#!lua <chdl>:set(value)`

    === "Single"
        将 `value` 赋值给当前信号。

        ```lua
        local signal = dut.value:chdl()
        local value = 0x123
        signal:set(value)
        ```
    === "Double / Multi"
        `#!lua <chdl>:set(value, force_single_beat)`

        - 如果 `force_single_beat` 为 `nil`（也就是不传入这个参数），那么此时的 `value` 必须是一个 Lua number 类型的 table，并且这个 table 的大小需要和信号的 beat 数相同，否则会报错。这个 table 的数值以 `<LSB> ~ <MSB>` 的顺序排列。
            ```lua
            local signal = dut.value:chdl()
            local value = {0x123, 0x456}
            signal:set(value)
            ```

        - 如果 `force_single_beat` 为 `true`，那么此时的 `value` 可以是一个 Lua number 类型的数值，此时只能赋值信号的低 32 bit，如果 `value` 是一个 `uint64_t` 的 `cdata`，那么此时就能赋值信号的低 64 bit（对于 Double 类型的 `chdl` 也就是能覆盖整个信号的位宽），且高于 64 bit 的位置将会被赋值为 0。
            ```lua
            local signal = dut.value:chdl()

            local value = 0x123
            signal:set(value, true)

            local value64 = 0x1234567890ABCDEFULL
            signal:set(value64, true)
            ```

            !!! note "LuaJIT 中对一串数字添加上 `ULL` 的后缀就可以表示一个 `uint64_t` 类型的 `cdata`"

2. `#!lua <chdl>:set_unsafe(value)`

    和 `set` 类似，但是这个方法不会检查 `value` 的正确性，减少了一些 `assert` 检查语句的开销，性能会比 `set` 更好一些。

3. `#!lua <chdl>:set_cached(value)`

    === "Single"
        
        和 `set` 一样都用于赋值信号，但是在赋值的时候会将当前的信号值加入到缓存中，如果下次赋值的时候发现当前的信号值没有变化，那么就不会赋值，这样可以减少一些不必要的信号赋值。

    === "Double / Multi"
    
        暂不支持 Cached 赋值方式。

4. `#!lua <chdl>:set_bitfield(s, e, v)`

    设置信号的值 `v`，并且只在 `s` 到 `e` 之间的位宽上赋值。`v` 可以是 Lua number 类型的数值，也可以是一个 `uint64_t` 类型的 `cdata`。
    
    ```lua
    local signal = dut.value:chdl()

    local value = 0x123
    signal:set_bitfield(0, 7, value)
    ```

5. `#!lua <chdl>:set_bitfield_hex_str(s, e, hex_str)`

    设置信号的值，并且只在 `s` 到 `e` 之间的位宽上赋值。`hex_str` 是一个 Hex String 类型的字符串.

    ```lua
    local signal = dut.value:chdl()

    local value = "123"
    signal:set_bitfield_hex_str(0, 7, value)
    ```

6. `#!lua <chdl>:set_force(value)`

    强制赋值（与 `set_release` 配合使用），与 SystemVerilog 中的 `force` 关键字相同。除了 `force` 这个属性上的区别之外，其他和 `set` 一样。

    ```lua
    local signal = dut.value:chdl()
    local value = 0x123
    signal:set_force(value)

    -- ...

    signal:set_release()
    ```

7. `#!lua <chdl>:set_release()`

    释放赋值（与 `set_force` 配合使用），与 SystemVerilog 中的 `release` 关键字相同。对于使用了 `set_force` 的信号，需要使用 `set_release` 来释放赋值，否则会导致信号的值不会更新。

8. `#!lua <chdl>:set_imm(value)`

    立即赋值版本的 `set`，除了立即赋值的属性之外，其他和 `set` 一样。

    <a id="set_and_set_imm"></a>
    !!! note "立即赋值和普通赋值的区别"
        `set` 方法进行赋值会在下一个时钟边沿到来后才会赋值（更接近 RTL 代码的行为，类似 Verilog 中的非阻塞赋值），而立即赋值则会立即赋值，且立即生效。
        ```lua
        local clock = dut.clock:chdl()
        local signal = dut.value:chdl() -- assume that the initial value is 0x00

        signal:set(0x123)
        assert(signal:get() == 0x00)

        clock:posedge()
        assert(signal:get() == 0x123) -- available right after the clock edge


        signal:set_imm(0x100)
        assert(signal:get() == 0x100) -- available right now

        clock:posedge()
        assert(signal:get() == 0x100)

        ```

9. `#!lua <chdl>:set_imm_unsafe(value)`

    立即赋值版本的 `set_unsafe`，除了立即赋值的属性之外，其他和 `set_unsafe` 一样。

10. `#!lua <chdl>:set_imm_cached(value)`

    立即赋值版本的 `set_cached`，除了立即赋值的属性之外，其他和 `set_cached` 一样。

11. `#!lua <chdl>:set_imm_bitfield(s, e, v)`

    立即赋值版本的 `set_bitfield`，除了立即赋值的属性之外，其他和 `set_bitfield` 一样。

12. `#!lua <chdl>:set_imm_bitfield_hex_str(s, e, hex_str)`

    立即赋值版本的 `set_bitfield_hex_str`，除了立即赋值的属性之外，其他和 `set_bitfield_hex_str` 一样。

13. `#!lua <chdl>:set_imm_force(value)`

    立即赋值版本的 `set_force`，除了立即赋值的属性之外，其他和 `set_force` 一样。

14. `#!lua <chdl>:set_imm_release()`

    立即赋值版本的 `set_release`，除了立即赋值的属性之外，其他和 `set_release` 一样。

#### debug 相关

TODO:

#### 验证相关

TODO:

#### 信号回调管理

TODO:

#### 一些提高开发效率的 API

TODO:

### TODO：CallableHDL 接口（Array）

TODO:

## Bundle

TODO:

## AliasBundle

TODO:

## ProxyTableHandle

TODO:

## EventHandle

TODO:

# 一个简单的 HVL 示例

本节将通过一个简单的例子（针对 HVL 场景）来展示 Verilua 的基本使用方法。

本节所使用的示例代码可以在 [这里](https://github.com/cyril0124/verilua/tree/master/examples/tutorial_example) 找到。

## 0. 准备 RTL 文件
下面是本节中使用到的 DUT（Design Under Test）的 RTL 代码，主要是一个简单的 Counter 模块。
```verilog title="Design.v"
--8<-- "examples/tutorial_example/Design.v"
```

## 1. 创建一个 Lua 脚本文件
下面是本节中使用到的 Lua 脚本文件，它将会在 Verilua 中被调用，从而控制硬件仿真的过程，这类似 C 语言中的 main 函数。
```lua title="LuaMain.lua" linenums="1"
--8<-- "examples/tutorial_example/LuaMain.lua"
```

??? note "上述代码的相关语法解释"
    * `#!lua verilua "appendTasks" ` 这个语句用于创建一个新的 task， Verilua 中所有的 task 能够以类似并行的方式进行调用；
    !!! tip "更简洁的方式创建 task"
        推荐使用 `fork` 来创建 task，例如: 
        ```lua
        fork {
            function ()
                print("fork task 1")
            end,
            function ()
                print("fork task 2")
            end,
            -- Other tasks...
        }
        ```
        这里的每一个 function 在 Verilua 的底层中都被用于创建一个个的 coroutine 从而允许 Verilua 的 Scheduler 进行调度。

    * `#!lua sim.dump_wave()` 这一函数用于启动波形文件的输出，也可以接收一个参数用来指定生成的文件，例如 `#!lua sim.dump_wave("./wave.vcd")`，如果没有指定（此处的用法），那么默认生成的波形文件名为 `test.vcd`
    !!! tip "波形文件的输出路径"
        使用 `sim.dump_wave()` 生成的波形文件通常保存在 `./build/<simulator>/<target_name>` 中，其中 `<simulator>` 是仿真器的名称，`<target_name>` 是 target 的名称。例如如果使用的 simulator 是 `verilator`，那么就会生成 `./build/verilator/TestDesign` 的波形文件。

    * `#!lua dut.clock:negedge()` 这一行中的 `dut` 用于指代当前的一整个 DUT，可以使用 `dut.<top_signal>` 来访问 DUT 的接口信号，这里的 `#!lua dut.clock` 就是 DUT 的顶层 clock 信号，而 `#!lua dut.clock:negedge()` 用于等待 clock 信号的下降沿，一旦调用这一函数，那么就会将此时的函数控制权交给仿真器，等到 clock 的下降沿到达的时候再通过 Scheduler 返回交出控制权的位置；
    <a id="about-dut"></a>
    !!! tip "关于 dut"
        `dut` 是 Verilua 中的一个全局的 table，主要用来提供**临时**的信号访问功能，具体的功能将在后续的教程中进行介绍（TODO：），如果想用 `dut` 来访问 DUT 的内部信号，那么需要以 `dut.u_<top_module_name>.<internal_signal_name>` 的方式访问，例如 `dut.u_Design.value`，这里加上 `u_<top_module_name>` 的原因是因为 Verilua 在编译的时候会根据所提供的 RTL 信息自动创建 Testbench，这个 Testbench 中会例化当前的 DUT，并将其取名为 `u_Design`。下面是自动生成的 Testbench 的部分代码：
        ```SystemVerilog title="tb_top.sv" linenums="1" hl_lines="28-34"
        module tb_top;
            // ...

            reg clock;
            reg reset;

            initial begin
                clock = 0;
                reset = 1;
            end

            always #10 clock = ~clock;

            // ...

            // -----------------------------------------
            // reg/wire declaration
            // -----------------------------------------  
            reg                  inc          ; // Input
            reg[7:0]             test         ; // Input
            wire[7:0]            value        ; // Output

            // ...

            // -----------------------------------------
            //  DUT module instantiate
            // ----------------------------------------- 
            Design u_Design (
                .clock   (clock  ), // direction: In         dataType: logic
                .reset   (reset  ), // direction: In         dataType: logic
                .inc     (inc    ), // direction: In         dataType: logic
                .test    (test   ), // direction: In         dataType: reg[7:0]
                .value   (value  )  // direction: Out        dataType: logic[7:0
            ); // u_Design
            
            // ...
        endmodule
        ```
        !!! note "关于 negedge"
            类似 `negedge` 的仿真时间控制函数还有 `posedge`、`edge`等，具体的功能将在后续的教程中进行介绍（TODO：），需要注意的是这些函数只能对**位宽为 1 的信号**进行使用！

    * `negedge` 可以接收两个参数，第一个是等待的次数，第二个是回调函数，回调函数在每次触发事件的时候都会被执行。
        ```lua title="LuaMain.lua" linenums="11" hl_lines="1-3"
                dut.clock:negedge(10, function ()
                    print("current cycle:", dut.cycles:get())
                end)
        ```
    
    * `#!lua dut.reset = 1` 和 `#!lua dut.reset = 0` 用于使用 dut 来给 reset 信号进行赋值，这种对信号赋值的方式是**立即赋值**，并且只对小于 32 bit 的信号可以这么使用，如果对大于 32 bit 的信号也使用这种方式进行赋值就会只赋值低 32 bit。
    也可以使用 `#!lua dut.reset:set_imm(1)` 和 `#!lua dut.reset:set_imm(0)` 来代替这两个方式，这里的 imm 是 immediate 的缩写，即立即（关于立即赋值与普通赋值的区别将会在后续的教程中进行介绍，具体可以看 [这里](../reference/data_structure.md#set_and_set_imm)）。

    * `#!lua local clock = dut.clock:chdl()` 用于创建一个 Verilua 的 `CallableHDL` 对象（也叫 `chdl`），这个对象用于管理 `tb_top.clock` 这个信号（`dut` 默认代表的 Testbench 顶层是 `tb_top`，也可以进行修改，但是不建议这么做）。
        - `CallableHDL` 其内部包括了多种信息，包括信号位宽、hierarchy path 等。
        - 还包括了各种用于控制信号的方法，例如：`<chdl>:set(<value>)` 用于设置信号的值，`<chdl>:get()` 用于获取信号的值，`<chdl>:posedge()` 用于等待信号上升沿，等等。
        - 使用 `CallableHDL` 对象对信号进行操作的性能比使用 `dut` 进行操作时的性能更高（底层实现的差异所导致的，`dut` 主要用于临时访问信号，不建议在性能要求较高的场景大量使用 `chdl`）。

    * `#!lua dut.value:dump()` 用于将信号的值（主要是以 Hex String 的形式）输出到控制台，可以用于查看信号的值，所有的信号相关的操作方式都有这个方法，包括上面提到的 `CallableHDL`。打印的内容如下所示：
        ```shell title="Terminal"
        [tb_top.value] => 0x01
        ```
    
    * `#!lua dut.value:dump_str()` 会将原本`#!lua dut.value:dump()` 的输出的内容作为一个返回值进行返回，因此 `#!lua dut.value:dump()` 也等价于 `#!lua print(dut.value:dump_str())`。
    
    * `#!lua dut.value:expect(0)` 的 `expect` 方法用于断言信号的值，如果信号的值与期望值相等则什么也不会发生，如果不相等则会打印报错信息并停止仿真。错误信息格式如下所示：
        ```shell title="Terminal"
        [tb_top.value] expect => 10, but got => 0
        ```
        类似 `expect` 的其他方法有 `expect_hex_str` 用于断言信号的 Hex String 值，`expect_dec_str` 用于断言信号的 Decimal String 值，`expect_bin_str` 用于断言信号的 Binary String 值。下面的几种写法是等价的：
        ```lua
        dut.value:expect(10)
        dut.value:expect_hex_str("a")
        dut.value:expect_dec_str("10")
        dut.value:expect_bin_str("1010")
        ```
    * `#!lua dut.value:is(2)` 的 `is` 方法用于判断信号的值是否等于某个值，如果等于则返回 `true`，否则返回 `false`。类似 `is` 的方法还有 `is_hex_str`、`is_dec_str`、`is_bin_str`，还有一个 `is_not` 方法，其功能和 `is` 相反，但是如果等于则返回 `false`，否则返回 `true`。

    * `#!lua dut.inc:set(1)` 的 `set` 方法用于设置信号的值，区别于立即赋值的 `dut.inc = 1`，`set` 方法进行赋值会在下一个时钟边沿到来后才会赋值（更接近 RTL 代码的行为），而立即赋值则会立即赋（具体可以看 [这里](../reference/data_structure.md#set_and_set_imm)）。`dut` 的 `set` 方法同样只能赋值最多 32 bit 位宽的信号。

    * `#!lua dut.inc:get()` 的 `get` 方法用于获取信号的值，返回的值是一个 Lua 的 number 类型的值，需要注意的是 `dut` 的 `get` 方法只能用来获得最多 32 bit 位宽信号的值。

    * `#!lua sim.finish()` 用于控制仿真器结束仿真。

    * `#!lua verilua "startTask"` 用于添加仿真开始执行时调用的函数，而 `#!lua verilua "finishTask"` 则用于添加仿真结束执行时调用的函数。这两个函数都能添加多个 function 块，例如：
        ```lua
        verilua "startTask" {
            function ()
                print("Simulation started! 1")
            end,
            function ()
                print("Simulation started! 2")
            end,
            -- ...
        }
        ```

## 2. 创建一个 xmake.lua 文件
Verilua 的工程（HVL 和 WAL 场景）使用 `xmake` 来管理，因此需要先在你的工程文件夹中创建一个 xmake.lua 文件。xmake 是一个基于 Lua 的构建工具（类似 makefile，cmake 等），提供了灵活的构建方式，关于 xmake 的使用，可以参考 [xmake 官方文档](https://xmake.io/#/getting_started)。

=== "xmake.lua"
    ```lua title="xmake.lua"
    target("TestDesign")                -- target 的名称可以随意取
        -- 
        -- Mandatory settings
        -- 
        -- 添加 Verilua 的规则，xmake 中支持自定义 rule，具体可以参考 xmake 相关文档
        add_rules("verilua")

        -- 添加用来执行硬件仿真的仿真器，这里使用的是 Verilator，还可以选择 @vcs 或 @iverilog
        add_toolchains("@verilator")
        
        -- 添加 RTL 文件, 也可以使用通配符进行匹配，如 ./*.v
        -- 如果 LuaMain 中使用到了其他的 Lua 模块，和添加 RTL 文件一样这里也可以添加 Lua 文件
        add_files("./Design.v")
        
        -- 设置 RTL 文件中的 top 实例名称（顶层模块名称），这里就是 Design
        set_values("cfg.top", "Design") 

        -- 设置需要执行的 Lua 脚本文件，一般只有一个主脚本，这里就是前面创建的 LuaMain.lua
        set_values("cfg.lua_main", "./LuaMain.lua")


        -- 
        -- Optional settings
        -- 
        -- `XXX`.flags 用于设置编译时选项，将会在编译仿真的时候被添加到对应的仿真器的命令行中
        -- 这里的 XXX 可以是 verilator、vcs、iverilog 等
        -- 下面这里主要添加了 Verilator 中用于输出波形文件的选项
        set_values("verilator.flags", "--trace", "--no-trace-top")

        -- `XXX`.run_prefix 用于设置仿真器的运行前缀，将会在运行仿真的时候被添加到命令行的前面
        set_values("verilator.run_prefix", "")
    ```
=== "xmake.lua（无注释）"
    ```lua title="xmake.lua"
    target("TestDesign")
        add_rules("verilua")
        add_toolchains("@verilator")
        add_files("./Design.v")
        set_values("cfg.top", "Design") 
        set_values("cfg.lua_main", "./LuaMain.lua")
        set_values("verilator.flags", "--trace", "--no-trace-top")
        set_values("verilator.run_prefix", "")
    ```

## 3. 编译
在创建好 xmake.lua 文件之后，我们就可以开始编译了，只需要执行下面的命令即可进行编译:
```shell
xmake build -P . TestDesign
```

- 上面的命令中，TestDesign 是我们创建的 target 的名称。
- 如果 RTL 文件没有被再次修改，那么只需要执行一次编译即可，如果文件被修改了，那么需要再次执行编译。
- 如果 Lua 文件（这里主要是 LuaMain.lua）被修改了，也不需要重新编译，因为 Lua 是解释执行的语言，不需要编译。
- `-P .` 用于指定 xmake 的运行路径为当前目录，如果不指定，那么 xmake 会自动查找上层的 xmake.lua 文件。因此这里添加了 `-P .` 参数，以便在当前目录下执行 xmake。如果你的工程目录的上一层目录没有 xmake.lua 文件，那么就不需要添加 `-P .` 参数。
- 如果编译成功，会在命令行最后输出 `[100%]: build ok, spent XXXs` 的信息，如果编译失败，那么会显示 error。

## 4. 运行仿真
编译完成后，可以执行下面的命令运行仿真：
```shell
xmake run -P . TestDesign
```

至此，我们就完成了一个简单的 Verilua 示例，并成功运行起仿真，可以看到由于 Verilua 使用 xmake 进行工程管理，因此相关的流程和编译配置都相对简单，提高了开发的效率。
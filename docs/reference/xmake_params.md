# xmake 的配置参数

Verilua 的 HVL/WAL 场景下的工程管理使用的是 [xmake](https://xmake.io/#/)，因此在 xmake 中支持多种可配置的参数，下面将对其进行说明。

!!! tip "用户可以使用 xmake 来编写灵活多样的 xmake.lua 文件来构建工程，具体可以参考 [xmake 官方文档](https://xmake.io/#/getting_started)"

## 必要参数

必要参数为必须在 xmake.lua 中对应的 target 添加的，否则进行编译的时候会报错。

1. `#!lua add_rules("verilua")`

    对于所有的 HVL/WAL 场景下的工程，都需要在 xmake 的 target 中添加这一句配置，否则讲无法正常使用 Verilua。

1. `#!lua add_toolchains(<toolchain>)`

    添加具体的仿真器（Verilua 中称为仿真后端（Backend））。
    
    - 对于 HVL 场景，目前 `<toolchain>` 的可选值为 `@verilator`、`@iverilog`、`@vcs`，分别对应了开源的 [Verilator](https://github.com/verilator/verilator)、开源的 [Icarus Verilog](https://github.com/steveicarus/iverilog)、商业的 Synopsys VCS 等仿真器。
    - 对于 WAL 场景，目前 `<toolchain>` 的可选值为 `@wave_vpi`，`wave_vpi` 是 Verilua 开发的一个用于仿真波形的仿真后端，目前支持的波形格式为: VCD、FST、FSDB。

2. `#!lua add_files(...)`
    
    添加需要进行仿真的文件，可以在一个语句中同时添加多个文件，也可以分为多个语句来添加多个文件。
    
    - 对于 HVL 场景，可以是 Verilog/SystemVerilog 文件、Lua 文件。
        ```lua title="xmake.lua" hl_lines="4 5"
        target("test")
            add_rules("verilua")
            add_toolchains("@verilator")
            add_files("src/main.sv", "src/main.lua")
            add_files("src/other.v")

            -- ...
        ```
    - 对于 WAL 场景，可以是波形文件、Lua文件。
        ```lua title="xmake.lua"
        target("test")
            add_rules("verilua")
            add_toolchains("@wave_vpi")
            add_files("./test.vcd", "test.lua")

            -- ...
        ```

        !!! warning "此时 `add_files` 只能添加**一个**波形文件"

3. `#!lua set_values("cfg.top", <top module name>)`

    <a id="cfg-top"></a>

    设置此时的顶层 DUT 的模块名称，对于 HVL/WAL 场景，这个参数必须设置，例如在[这个例子](../getting-started/simple_hvl_example.md) 中我们顶层 DUT 模块的名称是 `Design`，因此可以这么设置：`#!lua set_values("cfg.top", "Design")`。

4. `#!lua set_values("cfg.lua_main", <lua main file>)`

    设置仿真时候执行的 lua 主脚本文件，对于 HVL/WAL 场景，这个参数必须设置，例如在[这个例子](../getting-started/simple_hvl_example.md) 中我们的 lua 主脚本文件是 `LuaMain.lua`，因此可以这么设置：`#!lua set_values("cfg.lua_main", "LuaMain.lua")`。

    `<lua main file>` 是一个具体的文件，可以包含路径。


## 可选参数

1. `#!lua set_values("cfg.user_cfg", <user cfg file>)`

    设置用户自定义的配置文件，这个配置文件是一个 Lua 脚本，格式如下所示：

    ```lua title="my_cfg.lua" hl_lines="1 6" linenums="1"
    local cfg = {}

    cfg.value1 = 123
    cfg.value2 = "hello"

    return cfg
    ```

    重点在于这个 Lua 脚本要返回一个 key-value 格式的 table。

    当用户在 xmake.lua 中设置了这个配置文件的时候（`#!lua set_values("cfg.user_cfg", "my_cfg.lua")`），那么在仿真进行的时候，可以通过全局变量 `cfg` 获取到这个 table 中的值，例如：
    
    ```lua title="main.lua" linenums="1"
    fork {
        function ()
            print("cfg.value1 => ", cfg.value1)
            print("cfg.value2 => ", cfg.value2)
        
            assert(cfg.value1 == 123)
            assert(cfg.value2 == "hello")
        end
    }
    ```

2. `#!lua set_values("cfg.tb_gen_flags", <flags for testbench_gen>)` / ``#!lua add_values("cfg.tb_gen_flags", "<flags for testbench_gen>")``

    设置需要传递给 `testbench_gen` 的额外参数，具体支持的 flags 可以参考 [这里](./testbench_generate.md) 的介绍。

    !!! tip "xmake 中 `set_values` 和 `add_values` 的区别"
        - `set_values(<key>, <value>)` 对 `<key>` 进行单次赋值，调用多次 `set_values` 时，会覆盖之前的值，一个 `set_values` 只能有一个 `<value>`； 
            ```lua
            set_values("key", "value1") -- "key" = "value1" 
            set_values("key", "value2") -- "key" = "value2", the previous value "value1" is overwritten
            ```
        - `add_values(<key>, <value> ...)` 对 `<key>` 进行多次赋值，调用多次 `add_values` 时，会合并之前的值，一个 `add_values` 可以有多个 `<value>`。
            ```lua
            add_values("key", "value1") -- "key" = "value1" 
            add_values("key", "value2") -- "key" = {"value1", "value2"}, the previous value "value1" is merged

            -- equivalent to

            set_values("key", "value1", "value2")
            ```

3. `#!lua set_values("<sim>.flags", <flags used in compilation>)` / ``#!lua add_values("<sim>.flags", "<flags used in compilation>")``
    
    用来添加需要传递给仿真器进行编译的额外参数，具体支持的 flags 可以与使用的仿真器相关。
    
    !!! warning "注意"
        - 对于 HVL 场景，目前 `<sim>` 可选值为 `verilator`、`iverilog`、`vcs`。
        - 对于 WAL 场景，这一设置不起作用。

4. `#!lua set_values("<sim>.run_flags", <flags used at runtime>)` / ``#!lua add_values("<sim>.run_flags", "<flags used at runtime>")``

    用来添加需要传递给编译后的二进制文件运行时的额外参数。例如 Verilator 编译得到的二进制文件通常叫 `Vtb_top`，则可以使用 `set_values("verilator.run_flags", "--help")` 来添加一个运行时参数，这样在 xmake 执行 run 的时候就会加上这个参数。运行仿真的时候等价于 `#!shell Vtb_top --help`。

    !!! warning "注意"
        - 对于 HVL 场景，目前 `<sim>` 可选值为 `verilator`、`iverilog`、`vcs`。
        - 对于 WAL 场景，这一设置不起作用。

5. `#!lua set_values("<sim>.run_prefix", <prefix flags used at runtime>)` / `#!lua add_values("<sim>.run_prefix", "<prefix flags used at runtime>")`

    用来添加需要传递给编译后的二进制文件运行时的额外**前缀**参数。例如 Verilator 编译得到的二进制文件通常叫 `Vtb_top`，则可以使用 `set_values("verilator.run_prefix", "gdb --args")` 来添加一个运行时前缀参数，这样在 xmake 执行 run 的时候就会加上这个参数。运行仿真的时候等价于 `#!shell gdb --args Vtb_top`。

    !!! warning "注意"
        - 对于 HVL 场景，目前 `<sim>` 可选值为 `verilator`、`iverilog`、`vcs`。
        - 对于 WAL 场景，这一设置不起作用。

    !!! tip "`run_prefix` 和 `run_flags` 的位置区别"
        `#!shell <run_prefix> <binary> <run_flags>`

6. `#!lua set_values("cfg.build_dir_name", <build directory name>)`

    设置构建目录的名称，如果不设置，默认为 [`set_values("cfg.top", <top module name>)`](#cfg-top) 的值。

    !!! note "构建目录生成的位置"
        默认情况下为：`./build/<simulator>/<top module name>`，如果使用了 `set_values("cfg.build_dir_name", "SomeName")`，那么会使用用户自定义的名称：`./build/<simulator>/SomeName`。不过请注意，`./build/<simulator>` 是必须存在的，不支持更改。

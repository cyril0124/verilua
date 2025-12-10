# 全局配置信息

Verilua 中，`#!lua cfg` 这个全局变量（`table`类型）用于存储一些全局的配置信息，具体可以[相关的代码文件](https://github.com/cyril0124/verilua/tree/master/src/lua/LuaSimConfig.lua)，有一些常用的内置信息如下：

1. `#!lua cfg.top`

    这个变量用于存储当前的一个正在进行仿真的设计的顶层模块的名称，例如：`tb_top`。

2. `#!lua cfg.simulator`

    这个变量用于存储当前的仿真器的名称，可以是 `verilator`、`vcs`、 `xcelium`、`iverilog`、或者 `wave_vpi`。

3. `#!lua cfg.script`

    这个变量用于存储当前运行的 Lua 入口脚本文件，例如：`LuaMain.lua`。

4. `#!lua cfg.seed`

    这个变量用于存储当前的仿真的随机种子的值。

!!! tip "除了上面这些，Verilua 还允许用户在 xmake.lua 中指定一个配置文件，并将其合并到全局的 `#!lua cfg` 中，具体可以查看[此处](./xmake_params.md#cfg-user-cfg)的介绍。"
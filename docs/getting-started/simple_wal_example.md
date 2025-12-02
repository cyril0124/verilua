# 一个简单的 WAL 示例

本节将通过一个简单的例子来展示 Verilua 在 WAL 场景下的基本使用方式。

本节所使用的示例代码可以在 [这里](https://github.com/cyril0124/verilua/tree/master/examples/WAL) 找到。

## 1. 生成波形

生成波形主要是使用到了 Verilua 的 HVL 场景，可以现查看[这里](./simple_hvl_example.md)的内容对 HVL 场景的使用有一个基本的了解。

### 1.1. 准备 RTL 文件

下面是本节使用到的 RTL 代码，是一个简单的 Counter 模块。

```verilog title="Counter.v"
--8<-- "examples/WAL/Counter.v"
```

### 1.2. 创建相关 Lua 脚本文件

```lua title="main.lua" linenums="1"
--8<-- "examples/WAL/main.lua"
```

```lua title="Monitor.lua" linenums="1"
--8<-- "examples/WAL/Monitor.lua"
```

!!! note "此处的 `Monitor.lua` 模块将会在接下来仿真波形的时候被**复用**"


### 1.3. 创建 xmake.lua 文件

更具体的 xmake.lua 的介绍可以参考[这里](./simple_hvl_example.md#create-xmake-lua)的内容。

```lua title="xmake.lua"
target("gen_wave", function()
    add_rules("verilua")

    -- 本节中的例子会使用 Verilator 来作为 HVL 的仿真后端
    add_toolchains("@verilator")

    add_files("./Counter.v")
    add_files("./Monitor.lua")

    set_values("cfg.lua_main", "./main.lua")
    set_values("cfg.top", "Counter")

    -- Verilator 需要添加一些额外的参数来生成波形
    set_values("verilator.flags", "--trace", "--no-trace-top")
end)
```

### 1.4. 编译

在创建好 xmake.lua 文件之后，我们就可以开始编译了，只需要执行下面的命令即可进行编译:
```shell
xmake build -P . gen_wave
```

### 1.5. 运行仿真生成波形

编译完成后，可以执行下面的命令运行仿真：
```shell
xmake run -P . gen_wave
```

仿真生成的波形将会保存在 `./build/verilator/Counter/wave/test.vcd` 中，可以用 GTKWave 等波形文件查看器打开查看。

<a id="gen-wave-result"></a>
Monitor 模块会在命令行中打印出下面的信息：
```shell title="Terminal"
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x00
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x01
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x02
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x03
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x04
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x05
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x06
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x07
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x08
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x09
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x0a
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x00
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x01
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x02
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x03
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x04
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x05
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x06
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x07
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x08
[Monitor] [MonitorForGenWave] [tb_top.count] => 0x09
```

## 2. 仿真波形

### 2.1. 准备波形文件

WAL 的输入文件不是 Verilog/SystemVerilog，而是具体的波形文件（VCD、FST、FSDB 等格式），这里我们使用前面创建的波形文件。

### 2.2. 创建相关 Lua 脚本文件

需要有一个 Lua 脚本来作为 WAL 波形分析场景的入口。

```lua title="main_for_wal.lua" hl_lines="5 8 10" linenums="1"
--8<-- "examples/WAL/main_for_wal.lua"
```

!!! note "注意这里 `main_for_wal.lua` 中的 Monitor 模块复用了前面生成波形时候的 `Monitor.lua`"

!!! danger "WAL 场景下，不允许出现赋值的语句，例如 `set` 等，否则会导致报错，目前 WAL 场景下所有的信号都是只读的！"

### 2.3. 创建 xmake.lua 文件

```lua title="xmake.lua"
target("sim_wave", function()
    add_rules("verilua")

    -- WAL 场景下这里必须是 @wave_vpi
    add_toolchains("@wave_vpi")

    -- 输入文件不是 Verilog/SystemVerilog，而是波形文件
    -- 这里的波形文件路径指向的是前面生成波形时候的路径
    add_files("./build/verilator/Counter/wave/test.vcd")

    -- 这个复用了前面生成波形时候创建的模块
    add_files("./Monitor.lua")

    set_values("cfg.lua_main", "./main_for_wal.lua")

    -- 设计的顶层还是需要手动指定
    set_values("cfg.top", "Counter")
end)
```

### 2.4. 编译

在创建好 xmake.lua 文件之后，我们就可以开始编译了，只需要执行下面的命令即可进行编译:
```shell
xmake build -P . sim_wave
```

### 2.5. 运行仿真 

编译完成后，可以执行下面的命令运行仿真：
```shell
xmake run -P . sim_wave
```

此时查看命令行输出会发现 Monitor 的模块会在命令行中打印出下面的信息：

```shell title="Terminal"
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x00
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x01
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x02
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x03
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x04
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x05
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x06
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x07
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x08
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x09
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x0a
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x00
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x01
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x02
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x03
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x04
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x05
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x06
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x07
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x08
[Monitor] [MonitorForSimWave] [tb_top.count] => 0x09
```

这和前面我们运行 RTL 仿真时候的[输出](#gen-wave-result)是一样的。

# 仿真器控制

Verilua 提供了一些接口用来控制底层的仿真器：

1. `#!lua sim.dump_wave(wave_file)`

    用来控制仿真器开始生成波形，`wave_file` 是一个可选的波形文件名，如果没有指定，那么默认生成的波形文件名为 `test.vcd`（或者 `test.vcd.fsdb`）。

    需要注意的是如果仿真器使用的是 Verilator，那么还需要在 xmake.lua 中添加下面的信息来开启波形生成功能：
    ```lua
    add_values("verilator.flags", "--trace", "--no-trace-top")
    ```

2. `#!lua sim.disable_trace()`

    用来控制仿真器停止生成波形。

3. `#!lua sim.finish()`

    用来控制结束仿真。
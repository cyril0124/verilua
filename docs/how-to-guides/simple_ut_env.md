# 搭建一个简单的 UT 环境

Verilua 的启动速度很快，并且运行时足够轻量，能够用来搭建 Unit Test（UT）环境，测试一些中小规模的硬件模块。

在本节中，我们将介绍如何基于 Verilua 搭建一个简单的 UT 环境，所有的代码可以在[这里](https://github.com/cyril0124/verilua/tree/master/examples/simple_ut_env)找到。

## 1. 编写 UT 环境代码

我们可以编写一个简单的 UT 环境代码，它将包含一些实际验证中较为常用的函数，具体可以看下面的代码片段:

```lua title="env.lua" linenums="1"
--8<-- "examples/simple_ut_env/env.lua"
```

上述代码片段提供了如下的函数：

- `#!lua env.posedge(...)` / `#!lua env.negedge(...)`

    对全局的 `clock` 这个 `chdl` 的 `posedge` 函数进行封装，其使用方式和 [`<chdl>:posedge(...)`](../reference/data_structure.md/#chdl-posedge) / [`<chdl>:negedge(...)`](../reference/data_structure.md/#chdl-negedge) 是一样的。

- `#!lua env.dut_reset(reset_cycles)`

    对 DUT 进行复位，其中会对 reset 信号进行赋值，可以通过 `reset_cycles` 来指定复位的周期。

- `#!lua env.expect_happen_until(limit_cycles, func)`

    检查 `func` 在 `limit_cycles` 周期内是否发生，如果发生则立即返回，否则会触发 `assert` 错误，这在具体编写验证代码的时候比较常用，用来检查特定信号是否在预期时间内发生。

- `#!lua env.expect_not_happen_until(limit_cycles, func)`

    和 `#!lua env.expect_happen_until(limit_cycles, func)` 作用相反。

- `#!lua env.TEST_SUCCESS()`

    用来打印一个显眼的信息到 Terminal 上，表示测试已经成功结束。

- `#!lua env.register_test_case(case_name)`

    注册一个测试用例，其中 `case_name` 是测试用例的名称，返回一个被注册的测试用例函数。使用示例如下：

    ```lua 
    local env = require "env"
    
    local some_test_case = env.register_test_case "name of the test case" {
        -- Test case body
        function ()
            -- Do something
        end
    }

    fork {
        function ()
            env.dut_reset()

            -- Execute the test case
            some_test_case()
            
            env.TEST_SUCCESS()
            sim.finish()
        end
    }
    ```

通过上面这个简单的 `env.lua` 模块，就能为 UT 测试创建一个简易的验证环境。

## 2. 编写 UT 测试主体

接下来需要编写 UT 的具体业务代码（一个 lua 文件），这里同样以一个 Counter 模块为例：
```verilog title="Counter.v"
--8<-- "examples/simple_ut_env/Counter.v"
```

那么上述设计的 UT 业务代码可以写成这样：
```lua title="test_counter.lua" linenums="1"
--8<-- "examples/simple_ut_env/test_counter.lua"
```

这里我们写了三个测试用例：（1）test value incr，（2）test value no incr，（3）test value overflow。并在 `fork` 中启动了这三个测试用例。

## 3. 编写 xmake.lua

对于 HVL 场景，我们都需要编写一个 xmake.lua 文件来管理整个工程。

```lua title="xmake.lua" linenums="1"
--8<-- "examples/simple_ut_env/xmake.lua"
```

## 4. 执行测试

执行下面的命令即可编译并进行测试，这里如果 RTL 代码没有修改则只需要编译一次，修改 Lua 代码并不需要重新编译。

```shell
xmake build -P . test_counter

xmake run -P . test_counter
```

如果所有的测试用例都测试成功，那么就会打印一个成功的提示信息，并调用 `sim.finish()` 来结束仿真。命令行打印的信息如下所示：
``` title="Terminal"
-----------------------------------------------------------------
| [0] start test case ==> test value incr
-----------------------------------------------------------------
-----------------------------------------------------------------
| [0] end test case ==> test value incr
-----------------------------------------------------------------
-----------------------------------------------------------------
| [1] start test case ==> test value no incr
-----------------------------------------------------------------
-----------------------------------------------------------------
| [1] end test case ==> test value no incr
-----------------------------------------------------------------
-----------------------------------------------------------------
| [2] start test case ==> test value overflow
-----------------------------------------------------------------
-----------------------------------------------------------------
| [2] end test case ==> test value overflow
-----------------------------------------------------------------
total_test_cases: <3>

>>>TEST_SUCCESS!<<<
  _____         _____ _____ 
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___  
 |  ___/ /\ \  \___ \\___ \ 
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/ 

```


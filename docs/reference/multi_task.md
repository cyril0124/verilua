# 多任务系统

Verilua 实现了一个基于事件轮询调度的调度器（Scheduler），用于管理和记录用户注册的任务，Verilua 通过这种调度系统来实现多任务的调度。
在具体实现上，每个任务在执行到特定事件时，会通过 Scheduler 注册对应的回调函数（callback），并主动让出控制权，直到回调函数被触发后由 Scheduler 唤醒。这种协作式多任务模型依赖于任务的主动控制权让出，任务在让出控制权时可指定回调类型，例如上升沿（posedge）或下降沿（negedge）等。Scheduler 采用 Round Robin 仲裁策略，确保所有注册任务能够公平地获得执行机会，从而在单线程环境中实现高效的任务调度与并发执行。

下图是 Verilua 的任务调度流程，可以分为五个步骤：

1. Scheduler 遍历所有已注册的任务，每个任务通过唯一的 Task ID 进行标识；
2. 进入到其中一个任务中执行，执行特定位置让出任务控制权并提供回调类型与 Task ID进行回调注册；
3. Scheduler 通过 VPI-ML（Verilua 定义的一个中间层）与仿真器交互，控制仿真器注册指定的回调函数；
4. 回调函数注册后，仿真器继续运行，直到回调触发；
5. 仿真器在特定时间点触发回调后，通过 Task ID 定位对应任务，并恢复任务执行。

<figure markdown="span">
  ![Scheduler workflow](./images/scheduler_workflow.png){ width="70%" }
  <figcaption>Scheduler workflow</figcaption>
</figure>

这一过程实现了任务的调度，且回调注册是异步的，任务无需等待回调完成即可继续执行其他任务，任务之间不存在依赖运行。


## 创建任务
在 Verilua 中，我们可以通过 `fork` 来创建任务，并将其添加到 Scheduler 中，同时被创建的任务会随机分配一个唯一的任务 ID。例如：
```lua linenums="1" hl_lines="1"
fork { -- 也可以使用 `verilua "appendTasks"`，不过目前推荐使用 fork 来创建任务
    function ()
        print("fork task 1")
    end,

    function ()
        print("fork task 2")
    end,
    
    -- Other tasks...
}
```

使用 `fork` 来创建任务的时候也可以指定任务的名称，例如：
```lua linenums="1" hl_lines="2 6"
fork {
    simple_task = function ()
        print("fork task 1")
    end,

    ["another simple task"] = function ()
        print("fork task 2")
    end,

    -- Other tasks...
}
```

如果没有指定任务名称，那么 Verilua 会自动生成一个名称，具体格式为: `unnamed_task_<task_id>`。

这里的每一个 function 在 Verilua 的底层中都被用于创建一个个的 coroutine 从而允许 Verilua 的 Scheduler 进行调度。


## 注册任务回调
Verilua 的 task 中支持 `posedge`、`negedge`、`edge`、`time` 仿真行为控制机制，能够满足大部分的硬件仿真交互场景。

其中`posedge`、`negedge`、`edge`只能作用在位宽为 1 bit 的信号上，并且可以由 `CallableHDL`、`ProxyTableHandle` 等数据结构来创建。
下面是一个简单的例子：
```lua linenums="1"
fork {
    function ()
        print("start task 1")

        --
        -- Use ProxyTableHandle(dut)
        --
        dut.clock:posedge()
        print("posedge clock")

        dut.clock:negedge()
        print("negedge clock")

        dut.clock:posedge(10)

        dut.clock:negedge(5, function(c)
            print("repeat negedge clock 5 times, now is " .. c)
        end)

        --
        -- Use CallableHDL
        --
        local clock = dut.clock:chdl()
        clock:posedge()
        clock:negedge()
    end
}
```
`posedge`/`negedge`/`edge` 等回调注册函数可以接收两个参数，第一个是回调的等待次数，第二个是回调函数，回调函数在每次触发事件的时候都会被执行，回调函数还会接收一个参数，表示第几次进入到回调函数中。

`time` 这一个行为控制机制不需要使用到具体的硬件信号，只需要在任务中使用 `await_time(XXX)` 即可，其中 `XXX` 是指定的时间，单位与仿真器的时间单位相当，例如：
```lua linenums="1"
fork {
    function ()
        print("start task 1")

        await_time(10)
        print("await time 10")

        await_time(100)
        print("await time 100")
    end
}
```

## 任务同步
多个任务之间的同步可以使用 `EventHandle` 来创建特定事件实现，不同于直接使用全局变量进行同步，`EventHandle` 能够更进一步在事件触发的时候对正在等待的任务进行唤醒，从而实现了及时的任务同步。具体代码如下：
```lua linenums="1" hl_lines="8 12 18"
-- Create a EvevntHandle with name "name of the event"
local e = ("name of the event"):ehdl()

fork {
    task_1 = function ()
        dut.clock:posedge(10)
        print("send event")
        e:send()
    end,

    task_2 = function ()
        e:wait()
        print("task_2 is awakened")
    end,

    task_3 = function ()
        dut.clock:posedge(5)
        e:wait()
        print("task_3 is awakened")
    end,
}
```
上述代码中，task_2 将会在第十个仿真周期到来的时候被 task_1 唤醒，并且在唤醒后会打印出 `task_2 is awakened`，而 task_3 则在第五个仿真周期到来的时候被 task_1 唤醒，并且在唤醒后会打印出 `task_3 is awakened`。

需要注意的是，Verilua 允许有多个任务在等待同一个事件，但是同一时间点不能有多个任务同时 send 同一个 `EventHandle`，如果多个任务同时 send 事件，则会导致待唤醒的任务被唤醒多次，出现不符合预期的行为，但是 Verilua 底层并不会检查这一种情况，因此用户需要自行规避。


## Scheduler 底层 API 的使用
Verilua 的 Scheduler 提供了一系列 API 来查看和管理任务，下面是一些常用的 API 的介绍。

### 注册任务
`#!lua scheduler:append_task(task_id, namee, task_body, start_now)` 用于注册一个任务。

- `task_id` 是任务的唯一标识，可以输入`#!lua nil` 来让 Scheduler 自动生成一个唯一的任务 ID，否则 Scheduler 则会使用这里指定的 task_id 作为任务的唯一标识；
- `name` 是被注册任务的名称；
- `task_body` 是任务的代码块，也就是一个 `#!lua function`；
- `start_now` 是否立即启动该任务，默认为 `false`，如果设置为 `true` 则会在调用 `append_task` 之后立即启动任务（执行 `task_body` 代码块）.

`append_task` 在调用之后会创建一个任务并将其添加到 Scheduler 中，同时返回一个任务 ID。`scheduler` 是一个全局的变量，可以通过 `#!lua local scheduler = require "LuaScheduler"` 来引入。

下面是一个简单的例子：
```lua linenums="1"
local scheduler = require "LuaScheduler"

local id = scheduler:append_task(nil, "task_1", function ()
    print("task_1 is running")
    dut.clock:posedge(10)
    print("task_1 is finished")
ene)

local id2 = scheduler:append_task(nil, "task_2", function ()
    print("task_2 is running")
    dut.clock:posedge(10)
    print("task_2 is finished")
end, true)

local id3 = scheduler:append_task(123, "task_3", function ()
    print("task_3 is running")
    dut.clock:posedge(10)
    print("task_3 is finished")
end)
assert(id3 == 123, "task_id should be 123")
```

!!! note "`#!lua scheduler:append_task(...)` 返回的 `task_id` 可以结合 `#!lua scheduler:check_task_exists(task_id)` 来检查任务是否存在"

### 列出所有任务
`#!lua scheduler:list_tasks()` 用于列出所有注册的任务，并打印出其信息。下面是一个输出的示例：
```shell title="Terminal"
[scheduler list tasks]:
-----------------------------------------------------------
[0] name: task_1    id: 1123     cnt:12
[1] name: task_2    id: 2323     cnt:13
[2] name: task_3    id: 3456     cnt:14
-----------------------------------------------------------
```
其中的 `id` 为任务的唯一标识，`cnt` 为任务在调度器中的执行次数。

!!! note "每次仿真结束的时候，Verilua 都会自动调用一次 `#!lua scheduler:list_tasks()`"


### 检查任务是否存在
`#!lua scheduler:check_task_exists(task_id)` 用于检查任务是否存在，如果任务不存在则返回 `false`，否则返回 `true`。
```lua linenums="1"
local scheduler = require "LuaScheduler"

local id = scheduler:append_task(nil, "task_1", function ()
    print("task_1 is running")
    dut.clock:posedge(10)
    print("task_1 is finished")
end)

local exists = scheduler:check_task_exists(id)
assert(exists, "task_1 should exist")

```

## Scheduler 任务性能统计
Verilua 内置了一个 Scheduler 的任务性能统计功能，可以通过在仿真开始之前将环境变量 `VL_PERF_TIME` 设置为 `1` 来动态开启该功能。例如：
```shell title="Terminal"
VL_PERF_TIME=1 xmake run TestDesign

# or
export VL_PERF_TIME=1
xmake run TestDesign
```

在仿真结束之后，Verilua 会自动调用 `#!lua scheduler:list_tasks()` 来输出任务性能统计信息，下面是一个输出的示例：
```shell title="Terminal"
[scheduler list tasks]:
-------------------------------------------------------------
[ 58254@fake_cmoclient_0/TLULAgent a task resolve]    0.39 ms   percent:  0.05%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[83942@fake_mmioclient_0/TLULAgent a task resolve]    1.93 ms   percent:  0.23%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[                       21509@unnamed_fork_task_0]    2.64 ms   percent:  0.31%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[           65687@fake_mmioclient_0 timeout check]    2.70 ms   percent:  0.32%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[               34459@fake_icache_0 timeout check]    3.46 ms   percent:  0.41%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[                                   49198@pf_init]    4.29 ms   percent:  0.50%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[     45191@fake_dcache_0/TLCAgent c task resolve]    7.32 ms   percent:  0.86%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[     49389@fake_dcache_0/TLCAgent e task resolve]    9.37 ms   percent:  1.10%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[75477@fake_mmioclient_0/TLULAgent d task resolve]   24.26 ms   percent:  2.84%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[ 87630@fake_cmoclient_0/TLULAgent d task resolve]   24.29 ms   percent:  2.85%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[    43364@fake_icache_0/TLULAgent a task resolve]   24.65 ms   percent:  2.89%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[     96595@fake_dcache_0/TLCAgent a task resolve]   25.38 ms   percent:  2.98%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[                               6330@send_pf_task]   26.54 ms   percent:  3.11%  ┃▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[                              87302@recv_tlb_req]   31.96 ms   percent:  3.75%  ┃█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[     28004@fake_dcache_0/TLCAgent b task resolve]   35.42 ms   percent:  4.15%  ┃█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[    28108@fake_icache_0/TLULAgent d task resolve]   36.69 ms   percent:  4.30%  ┃█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[     15833@fake_dcache_0/TLCAgent d task resolve]   40.14 ms   percent:  4.71%  ┃█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[                                 63208@main_task]   51.69 ms   percent:  6.06%  ┃█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[                   53008@fake_dcache_0 eval task]   175.71 ms   percent: 20.60% ┃██████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
[                              27178@monitor_task]   324.09 ms   percent: 38.00% ┃███████████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒┃
total_time: 0.85 s / 852.91 ms
```

-- jit.opt.start(3)
jit.opt.start("loopunroll=100")

require("LuaScheduler")
require("LuaSimConfig")
local VERILUA_CFG, VERILUA_CFG_PATH = LuaSimConfig.get_cfg()
local cfg = require(VERILUA_CFG)


local verilua = {}

---@class single_step_task_table
---@field name string
---@field func thread
---@field param table
verilua.single_step_task_table = {}
verilua.single_step_task_cnt = 1
verilua.single_step_is_register_task_table = false


verilua.is_register_task_table = false
verilua.start_time = 0
verilua.end_time = 0

verilua._main_task = function ()
    assert(false, "[main_task] Not implemented!")
end

verilua._step_main_task = function ()
    assert(false, "[step_task] Not implemented!")
end

verilua._start_callback = function ()
    assert(false, "[start_callback] Not implemented!")
end

verilua._finish_callback = function ()
    assert(false, "[finishe_callback] Not implemented!")
end

verilua.start_callback = function ()
    verilua_hello()
    print("----------[Lua] Verilua Init!----------")
    print((ANSI_COLOR_MAGENTA .. "configuration file is %s/%s.lua" .. ANSI_COLOR_RESET):format(VERILUA_CFG_PATH, VERILUA_CFG))
    verilua.start_time = os.clock()

    -- User code
    verilua._start_callback()
    
    print("----------[Lua] Verilua Init finish!----------")
    if not cfg.single_step_mode then
        scheduler:schedule_all_tasks()
    end
end

verilua.finish_callback = function ()
    print("\n")
    if not cfg.single_step_mode then
        scheduler:list_tasks()
    end

    -- User code
    verilua._finish_callback()

    verilua.end_time = os.clock()
    print(ANSI_COLOR_MAGENTA)
    print("----------[Lua] Simulation finish!----------")
    print("----------[Lua] Time elapsed: " .. (verilua.end_time - verilua.start_time).. " seconds" .. "----------")
    print(ANSI_COLOR_RESET)
end

function verilua.register_tasks(task_table)
    assert(task_table ~= nil)
    assert(type(task_table) == "table")
    assert(task_table[1] ~= nil)
    assert(type(task_table[1]) == "table")
    
    if not cfg.single_step_mode then
        assert(verilua.is_register_task_table == false, "already reigister task table!")
        verilua.is_register_task_table = true

        table.insert(task_table, {"main task", verilua.main_task, {}})

        scheduler:create_task_table(task_table)
    else
        assert(verilua.single_step_is_register_task_table == false, "already reigister task table!")
        verilua.single_step_is_register_task_table = true

        table.insert(verilua.single_step_task_table, verilua.single_step_task_cnt, {name = "main task", func = coroutine.create(verilua._step_main_task), param = {}})
        verilua.single_step_task_cnt = verilua.single_step_task_cnt + 1

        for _it, task in ipairs(task_table) do
            local id = verilua.single_step_task_cnt
            print(string.format("[single step] append task, name: %s  id:%d", task[1], id))
            table.insert(verilua.single_step_task_table, id, {name = task[1], func = coroutine.create(task[2]), param = task[3]})
            verilua.single_step_task_cnt = verilua.single_step_task_cnt + 1
        end
    end
end

function verilua.main_task()
    
    -- User code
    verilua._main_task()

    verilua_info("Finish")
    vpi.simulator_control(SimCtrl.FINISH)
end

function verilua.register_main_task(func)
    if not cfg.single_step_mode then
        verilua._main_task = func
    else
        verilua._step_main_task = func
    end
end

function verilua.register_start_callback(func)
    verilua._start_callback = func
end

function verilua.register_finish_callback(func)
    verilua._finish_callback = func
end


function verilua_init()
    verilua.start_callback()
end

function finish_callback()
    verilua.finish_callback()
end

function sim_event(id)
    scheduler:schedule_tasks(id)
end

function lua_main_step()
    local coro_resume = coroutine.resume
    local coro_status = coroutine.status

    local will_remove = {}

    for id, task in pairs(verilua.single_step_task_table) do
        local task_name = task.name
        local task_coro = task.func
        local task_param = task.param

        local ok, msg = coro_resume(task_coro, table.unpack(task_param))
        if not ok then
            local err_msg = msg
            print(debug.traceback(task_coro, err_msg))
            assert(false, "failed at " .. task_name)
        end

        if coro_status(task_coro) == 'dead' then
            -- print("will remove id:", id, "name:", task_name)
            table.insert(will_remove, task_name)
        end
    end
    
    for id, _ in ipairs(will_remove) do
        verilua.single_step_task_table[id] = nil
    end
    
end

function await_step()
    coroutine.yield()
end


return verilua
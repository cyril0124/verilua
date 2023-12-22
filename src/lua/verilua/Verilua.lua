-- jit.opt.start(3)
jit.opt.start("loopunroll=100")

require("LuaSimConfig")
local VERILUA_CFG, VERILUA_CFG_PATH = LuaSimConfig.get_cfg()
local cfg = require(VERILUA_CFG)
local scheduler = require("LuaScheduler")


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
    if not cfg.single_step_mode then
        assert(verilua.is_register_task_table == false, "already reigister task table!")
        verilua.is_register_task_table = true

        table.insert(task_table, {"main task", verilua.main_task, {}})

        if task_table ~= nil and #task_table ~= 0 then
            assert(task_table ~= nil)
            assert(type(task_table) == "table")
            assert(task_table[1] ~= nil)
            assert(type(task_table[1]) == "table")
            scheduler:create_task_table(task_table)
        end
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


local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    void verilator_next_sim_step(void);
]]

local next_sim_step = C.verilator_next_sim_step

local dut = require('LuaDut')
local inspect = require("inspect")


function verilua_schedule_loop()
    verilua_warning("enter verilua_schedule_loop")

    local clock_hdl = dut.clock("hdl")
    local MAIN_TIME_STEP = 5

    local main_time = 0LL
    while true do
        local task_max = scheduler.task_max
        local task_table = scheduler.task_table
        local will_remove_tasks = scheduler.will_remove_tasks
        local callback_table = scheduler.callback_table

        for i = 1, task_max do -- Better performance for LuaJIT
            local task_id = will_remove_tasks[i]
            if task_id ~= nil then
                if task_table[task_id] ~= nil then
                    local _ = scheduler.verbose and scheduler:_log("remove task_id:" .. task_id .. " task_name:" ..  task_table[task_id].name)
                    task_table[task_id] = nil
                    callback_table[task_id] = nil
                end
            end
        end
        scheduler.will_remove_tasks = {}

        for id, task in pairs(task_table) do
            local task_name = task.name
            local task_func = task.func
            local task_param = task.param
            local callback = callback_table[id]

            if callback.valid == false then
                local types, value, signal = task_func(table.unpack(task_param))
                task.cnt = task.cnt + 1

                if types == nil then
                    scheduler:remove_task(id)
                else
                    if types ~= YieldType.NOOP then
                        callback.valid = true
                    end
                    callback.types = types
                    callback.value = value
                    callback.start_time = main_time

                    local is_clock_signal = false
                    local signal_is_str = false
                    if type(signal) == "string" then
                        callback.signal_str = signal
                        is_clock_signal = signal == "tb_top.clock"
                        signal_is_str = true
                    else
                        callback.signal = signal
                        is_clock_signal = signal == clock_hdl
                    end
                    callback.signal_is_str = signal_is_str

                    local is_posedge = (types == YieldType.SIGNAL_EDGE_HDL and value == EdgeType.POSEDGE) or 
                                        (types == YieldType.SIGNAL_EDGE_ALWAYS and value == EdgeType.POSEDGE) or
                                        (types == YieldType.SIGNAL_EDGE and value == EdgeType.POSEDGE)
                    local is_negedge = (types == YieldType.SIGNAL_EDGE_HDL and value == EdgeType.NEGEDGE) or 
                                        (types == YieldType.SIGNAL_EDGE_ALWAYS and value == EdgeType.NEGEDGE) or
                                        (types == YieldType.SIGNAL_EDGE and value == EdgeType.NEGEDGE)
                    local is_clock_posedge = is_posedge and is_clock_signal
                    local is_clock_negedge = is_negedge and is_clock_signal
                    local is_normal_posedge = is_posedge and not is_clock_signal
                    local is_normal_negedge = is_negedge and not is_clock_signal
                    local is_timer = types == YieldType.TIMER

                    callback.is_negedge = is_negedge
                    callback.is_posedge = is_posedge
                    callback.is_clock_posedge = is_clock_posedge
                    callback.is_clock_negedge = is_clock_negedge
                    callback.is_timer = is_timer

                    if is_normal_posedge or is_normal_negedge then
                        if signal_is_str then
                            callback.signal_value = vpi.get_value_by_name(signal)
                        else
                            callback.signal_value = C.c_get_value(signal)
                        end
                    end
                end
            end
        end

        next_sim_step(); main_time = main_time + MAIN_TIME_STEP
        -- Deal with callback
        for id, callback in pairs(callback_table) do
            if callback.valid == true then
                if callback.is_clock_posedge == true then
                    callback.valid = false
                elseif callback.is_timer == true then
                    if main_time >= (callback.start_time + callback.value) then
                        callback.valid = false
                    end
                else
                    -- Normal posedge callback
                    if callback.is_posedge == true then
                        local old_val = callback.signal_value
                        local new_val = 0

                        if callback.signal_is_str then
                            new_val = vpi.get_value_by_name(callback.signal_str)
                        else
                            new_val = C.c_get_value(callback.signal)
                        end

                        if old_val == 0 then
                            if new_val == 1 then
                                callback.valid = false
                            end
                        elseif old_val == 1 then
                            callback.signal_value = new_val
                        else
                            assert(false)
                        end

                    elseif callback.is_negedge == true then
                        -- PASS
                    else
                        assert(false, inspect(callback))
                    end
                end
            end
        end
        

        next_sim_step(); main_time = main_time + MAIN_TIME_STEP
        -- Deal with callback
        for id, callback in pairs(callback_table) do
            if callback.valid == true then
                if callback.is_clock_negedge == true then
                    callback.valid = false
                elseif callback.is_timer == true then
                    if main_time >= (callback.start_time + callback.value) then
                        callback.valid = false
                    end
                else
                    -- Normal negedge callback
                    if callback.is_negedge == true then
                        local old_val = callback.signal_value
                        local new_val = 0
                        
                        if callback.signal_is_str then
                            new_val = vpi.get_value_by_name(callback.signal_str)
                        else
                            new_val = C.c_get_value(callback.signal)
                        end

                        if old_val == 1 then
                            if new_val == 0 then
                                callback.valid = false
                            end
                        elseif old_val == 0 then
                            callback.signal_value = new_val
                        else
                            assert(false)
                        end

                    else
                        assert(false, inspect(callback))
                    end
                end
            end
        end
    end
end

return verilua
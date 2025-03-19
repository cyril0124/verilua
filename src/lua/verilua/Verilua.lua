local os = require "os"
local scheduler = require "verilua.scheduler.LuaScheduler"

local type = type
local print = print
local assert = assert
local ipairs = ipairs
local table_insert = table.insert

local cfg = _G.cfg
local SchedulerMode = _G.SchedulerMode
local verilua_info = _G.verilua_info
local verilua_hello = _G.verilua_hello
local verilua_warning = _G.verilua_warning

assert(scheduler ~= nil)

local verilua = {}

verilua.is_register_task_table = false
verilua.start_time = 0
verilua.end_time = 0

verilua._start_callback = function ()
    verilua_warning("[start_callback] Not implemented!")
end

verilua._finish_callback = function ()
    verilua_warning("[finish_callback] Not implemented!")
end

verilua.start_callbacks = {}
verilua.finish_callbacks = {}

verilua.start_callback = function ()
    verilua_hello()
    verilua_info("-------------- [Lua] Verilua init --------------")
    verilua.start_time = os.clock()

    -- 
    -- user callbacks
    -- 
    if #verilua.start_callbacks == 0 then
        verilua_warning("[start_callback] Not implemented!")
    else
        for i, callback_func in ipairs(verilua.start_callbacks) do
            callback_func()
        end
    end
    
    verilua_info("---------- [Lua] Verilua init finish! ----------")

    scheduler:schedule_all_tasks()
end

verilua.finish_callback = function ()
    print()
    verilua_info(("--------------------- [Lua] Start doing finish_callback ---------------------"):format(verilua.end_time - verilua.start_time))
	scheduler:list_tasks()

    -- Automatically save default coverage group into json file
    if #_G.default_cg.cover_points > 0 then
        _G.default_cg:report()
        _G.default_cg:try_save_once()
    end

    -- User defined finish callbacks
    if #verilua.finish_callbacks == 0 then
        verilua_warning("[finish_callback] Not implemented!")
    else
        local verilua_get_error = _G.verilua_get_error -- Set by each scheduler when there is an error in the ongoing task
        for i, callback_func in ipairs(verilua.finish_callbacks) do
            callback_func(verilua_get_error)
        end
    end

    verilua.end_time = os.clock()
    verilua_info(("---------- [Lua] Simulation finish! Time elapsed: %4.6f seconds ----------"):format(verilua.end_time - verilua.start_time))
    print()
end

function verilua.register_start_callback(func)
    assert(type(func) == "function")
    table_insert(verilua.start_callbacks, func)
end

function verilua.register_finish_callback(func)
    assert(type(func) == "function")
    table_insert(verilua.finish_callbacks, func)
end


verilua.append_start_callback = verilua.register_start_callback
verilua.append_finish_callback = verilua.register_finish_callback

_G.verilua_init = function()
    verilua.start_callback()
end

_G.finish_callback = function()
    verilua.finish_callback()
end

_G.sim_event = function(id)
    scheduler:schedule_task(id)
end

_G.lua_main_step = function()
    scheduler:schedule_all_tasks()
end

_G.lua_posedge_step = function ()
	scheduler:schedule_posedge_tasks()
end

_G.lua_negedge_step = function ()
	scheduler:schedule_negedge_tasks()
end

----------------------------------
-- dominant mode
------------------------------------
_G.verilua_schedule_loop = function()
    verilua_warning("enter verilua_schedule_loop")

    assert(scheduler.schedule_loop ~= nil)
    assert(type(scheduler.schedule_loop) == "function")

    scheduler:schedule_loop()
end


_G.sim_event_chunk_1 = function (task_id_1)
	scheduler:schedule_task(task_id_1)
end

_G.sim_event_chunk_2 = function (task_id_1, task_id_2)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
end

_G.sim_event_chunk_3 = function (task_id_1, task_id_2, task_id_3)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
end

_G.sim_event_chunk_4 = function (task_id_1, task_id_2, task_id_3, task_id_4)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
end

_G.sim_event_chunk_5 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
end

_G.sim_event_chunk_6 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
end

_G.sim_event_chunk_7 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
end

_G.sim_event_chunk_8 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
end

_G.sim_event_chunk_9 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8, task_id_9)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
	scheduler:schedule_task(task_id_9)
end

_G.sim_event_chunk_10 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8, task_id_9, task_id_10)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
	scheduler:schedule_task(task_id_9)
	scheduler:schedule_task(task_id_10)
end

_G.sim_event_chunk_11 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8, task_id_9, task_id_10, task_id_11)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
	scheduler:schedule_task(task_id_9)
	scheduler:schedule_task(task_id_10)
	scheduler:schedule_task(task_id_11)
end

_G.sim_event_chunk_12 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8, task_id_9, task_id_10, task_id_11, task_id_12)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
	scheduler:schedule_task(task_id_9)
	scheduler:schedule_task(task_id_10)
	scheduler:schedule_task(task_id_11)
	scheduler:schedule_task(task_id_12)
end

_G.sim_event_chunk_13 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8, task_id_9, task_id_10, task_id_11, task_id_12, task_id_13)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
	scheduler:schedule_task(task_id_9)
	scheduler:schedule_task(task_id_10)
	scheduler:schedule_task(task_id_11)
	scheduler:schedule_task(task_id_12)
	scheduler:schedule_task(task_id_13)
end

_G.sim_event_chunk_14 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8, task_id_9, task_id_10, task_id_11, task_id_12, task_id_13, task_id_14)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
	scheduler:schedule_task(task_id_9)
	scheduler:schedule_task(task_id_10)
	scheduler:schedule_task(task_id_11)
	scheduler:schedule_task(task_id_12)
	scheduler:schedule_task(task_id_13)
	scheduler:schedule_task(task_id_14)
end

_G.sim_event_chunk_15 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8, task_id_9, task_id_10, task_id_11, task_id_12, task_id_13, task_id_14, task_id_15)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
	scheduler:schedule_task(task_id_9)
	scheduler:schedule_task(task_id_10)
	scheduler:schedule_task(task_id_11)
	scheduler:schedule_task(task_id_12)
	scheduler:schedule_task(task_id_13)
	scheduler:schedule_task(task_id_14)
	scheduler:schedule_task(task_id_15)
end

_G.sim_event_chunk_16 = function (task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8, task_id_9, task_id_10, task_id_11, task_id_12, task_id_13, task_id_14, task_id_15, task_id_16)
	scheduler:schedule_task(task_id_1)
	scheduler:schedule_task(task_id_2)
	scheduler:schedule_task(task_id_3)
	scheduler:schedule_task(task_id_4)
	scheduler:schedule_task(task_id_5)
	scheduler:schedule_task(task_id_6)
	scheduler:schedule_task(task_id_7)
	scheduler:schedule_task(task_id_8)
	scheduler:schedule_task(task_id_9)
	scheduler:schedule_task(task_id_10)
	scheduler:schedule_task(task_id_11)
	scheduler:schedule_task(task_id_12)
	scheduler:schedule_task(task_id_13)
	scheduler:schedule_task(task_id_14)
	scheduler:schedule_task(task_id_15)
	scheduler:schedule_task(task_id_16)
end


return verilua
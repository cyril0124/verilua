--[[luajit-pro]]

local scheduler = require "LuaScheduler"
local os = require "os"

local verilua_hello = verilua_hello
local verilua_info = verilua_info
local verilua_warning = verilua_warning
local VeriluaMode = VeriluaMode
local cfg = cfg
local print = print
local assert = assert
local tinsert = table.insert
local type = type

assert(scheduler ~= nil)

local verilua = {}

verilua.is_register_task_table = false
verilua.start_time = 0
verilua.end_time = 0

verilua._main_task = function ()
    assert(false, "[main_task] Not implemented!")
end

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
    if cfg.mode ~= VeriluaMode.STEP then
        scheduler:list_tasks()
    end

    -- 
    -- user callbacks
    -- 
    if #verilua.finish_callbacks == 0 then
        verilua_warning("[finish_callback] Not implemented!")
    else
        for i, callback_func in ipairs(verilua.finish_callbacks) do
            callback_func()
        end
    end

    verilua.end_time = os.clock()
    verilua_info(("---------- [Lua] Simulation finish! Time elapsed: %4.6f seconds ----------"):format(verilua.end_time - verilua.start_time))
    print()
end

function verilua.register_tasks(task_table)
    assert(verilua.is_register_task_table == false, "already reigister task table!")
    verilua.is_register_task_table = true

    tinsert(task_table, {"main_task", verilua.main_task, {}})

    if task_table ~= nil and #task_table ~= 0 then
        assert(task_table ~= nil)
        assert(type(task_table) == "table")
        assert(task_table[1] ~= nil)
        assert(type(task_table[1]) == "table")
        scheduler:create_task_table(task_table)
    end
end

function verilua.main_task()
    -- 
    -- user code
    -- 
    verilua._main_task()
end

function verilua.register_main_task(func)
    assert(type(func) == "function")
    verilua._main_task = func
    scheduler:append_task(nil, "main_task", verilua._main_task, {}, false)
end

function verilua.register_start_callback(func)
    assert(type(func) == "function")
    tinsert(verilua.start_callbacks, func)
end

function verilua.register_finish_callback(func)
    assert(type(func) == "function")
    tinsert(verilua.finish_callbacks, func)
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
    scheduler:schedule_tasks(id)
end

_G.lua_main_step = function()
    scheduler:schedule_all_tasks()
end

$include("gen_sim_event")

----------------------------------
-- dominant mode
------------------------------------
_G.verilua_schedule_loop = function()
    verilua_warning("enter verilua_schedule_loop")

    assert(scheduler.schedule_loop ~= nil)
    assert(type(scheduler.schedule_loop) == "function")

    scheduler:schedule_loop()
end


return verilua
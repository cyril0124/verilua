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
    -- assert(false, "[start_callback] Not implemented!")
    verilua_warning("[start_callback] Not implemented!")
end

verilua._finish_callback = function ()
    -- assert(false, "[finishe_callback] Not implemented!")
    verilua_warning("[finishe_callback] Not implemented!")
end

verilua.start_callback = function ()
    verilua_hello()
    verilua_info("----------[Lua] Verilua Init!----------")
    verilua.start_time = os.clock()

    -- User code
    verilua._start_callback()
    
    verilua_info("----------[Lua] Verilua Init finish!----------")

    scheduler:schedule_all_tasks()
end

verilua.finish_callback = function ()
    print("\n")
    if not (cfg.mode == VeriluaMode.STEP) then
        scheduler:list_tasks()
    end

    -- User code
    verilua._finish_callback()

    verilua.end_time = os.clock()
    verilua_info("----------[Lua] Simulation finish!----------")
    verilua_info("----------[Lua] Time elapsed: " .. (verilua.end_time - verilua.start_time).. " seconds" .. "----------")
end

function verilua.register_tasks(task_table)
    assert(verilua.is_register_task_table == false, "already reigister task table!")
    verilua.is_register_task_table = true

    tinsert(task_table, {"main task", verilua.main_task, {}})

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
    -- User code
    -- 
    verilua._main_task()
end

function verilua.register_main_task(func)
    verilua._main_task = func
    scheduler:create_task_table({{"main task", verilua._main_task, {}}})
end

function verilua.register_start_callback(func)
    verilua._start_callback = func
end

function verilua.register_finish_callback(func)
    verilua._finish_callback = func
end


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
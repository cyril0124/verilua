---@diagnostic disable: need-check-nil

local os = require "os"
local Logger = require "verilua.utils.Logger"

--- Lazy load scheduler to avoid circular dependency with verilua.scheduler.LuaScheduler(loaded at `start_callback`)
---@type verilua.scheduler.LuaScheduler
local scheduler

local table_insert = table.insert

local verilua_info = _G.verilua_info

-- Create a logger instance for Verilua core
local logger = Logger.new("VERILUA")

local verilua_hello = function()
    logger:banner()
    print()
end

--- `VeriluaCore` is a singleton object that manages the simulation process of Verilua
---@class verilua.VeriluaCore
---@field private start_time number Start time of the simulation
---@field private end_time number End time of the simulation
---@field private got_error boolean Indicates if an error occurred during the simulation
---@field private start_callback_vec table<integer, fun()>
---@field private finish_callback_vec table<integer, fun()|fun(got_error: boolean)>
---@field record_error fun()
---@field append_start_callback fun(func: fun())
---@field append_finish_callback fun(func: fun()|fun(got_error: boolean))
---@field register_start_callback fun(func: fun()) Alias of `append_start_callback`
---@field register_finish_callback fun(func: fun()|fun(got_error: boolean)) Alias of `append_finish_callback`
---@field start_callback fun()
---@field finish_callback fun()
local verilua = {
    start_time = 0.0,
    end_time = 0.0,
    got_error = false,
    start_callback_vec = {},
    finish_callback_vec = {}
}

--- Records that an error has occurred during task execution.
--- Called by the scheduler when a task fails.
verilua.record_error = function()
    assert(not verilua.got_error, "Error has already been recorded!")
    verilua.got_error = true
end

verilua.start_callback = function()
    verilua_hello()
    logger:header("[Verilua] Initialization Start", 56)
    verilua.start_time = os.clock()

    -- Call user defined start callbacks
    if #verilua.start_callback_vec == 0 then
        -- verilua_warning("[start_callback] Not implemented!")
    else
        for _, callback_func in ipairs(verilua.start_callback_vec) do
            callback_func()
        end
    end

    verilua_info("Initialization sequence finished.")

    scheduler = require "verilua.scheduler.LuaScheduler"
    scheduler:schedule_all_tasks()
end

verilua.finish_callback = function()
    print()
    logger:header("[Verilua] Finalization Start", 56)

    if not scheduler then
        scheduler = require "verilua.scheduler.LuaScheduler"
    end

    scheduler:list_tasks()

    -- Automatically save default coverage group into json file
    if _G.default_cg and #_G.default_cg.cover_points > 0 then
        _G.default_cg:report()
        _G.default_cg:try_save_once()
    end

    -- User defined finish callbacks
    if #verilua.finish_callback_vec == 0 then
        -- verilua_warning("[finish_callback] Not implemented!")
    else
        for _, callback_func in ipairs(verilua.finish_callback_vec) do
            --- e.g.
            --- ```lua
            ---     fork {
            ---         function()
            ---             -- ...
            ---             assert(false, "Error occurred")
            ---             -- ...
            ---         end
            ---     }
            ---
            ---     final {
            ---         function(got_error)
            ---             assert(got_error == true)
            ---         end
            ---     }
            --- ```
            callback_func(verilua.got_error)
        end
    end

    verilua.end_time = os.clock()

    local elapsed_time = verilua.end_time - verilua.start_time
    logger:sim_summary(elapsed_time)
end

function verilua.register_start_callback(func)
    assert(type(func) == "function")
    table_insert(verilua.start_callback_vec, func)
end

function verilua.register_finish_callback(func)
    assert(type(func) == "function")
    table_insert(verilua.finish_callback_vec, func)
end

verilua.append_start_callback = verilua.register_start_callback
verilua.append_finish_callback = verilua.register_finish_callback

_G.verilua_init = function()
    verilua.start_callback()
end

_G.schedule_all_tasks = function()
    scheduler:schedule_all_tasks()
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

_G.lua_posedge_step = function()
    scheduler:schedule_posedge_tasks()
end

_G.lua_negedge_step = function()
    scheduler:schedule_negedge_tasks()
end

_G.sim_event_chunk_1 = function(task_id_1)
    scheduler:schedule_task(task_id_1)
end

_G.sim_event_chunk_2 = function(task_id_1, task_id_2)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
end

_G.sim_event_chunk_3 = function(task_id_1, task_id_2, task_id_3)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
end

_G.sim_event_chunk_4 = function(task_id_1, task_id_2, task_id_3, task_id_4)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
end

_G.sim_event_chunk_5 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
end

_G.sim_event_chunk_6 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
end

_G.sim_event_chunk_7 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
end

_G.sim_event_chunk_8 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
end

_G.sim_event_chunk_9 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8,
                                task_id_9)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
    schedule_task(scheduler, task_id_9)
end

_G.sim_event_chunk_10 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8,
                                 task_id_9, task_id_10)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
    schedule_task(scheduler, task_id_9)
    schedule_task(scheduler, task_id_10)
end

_G.sim_event_chunk_11 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8,
                                 task_id_9, task_id_10, task_id_11)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
    schedule_task(scheduler, task_id_9)
    schedule_task(scheduler, task_id_10)
    schedule_task(scheduler, task_id_11)
end

_G.sim_event_chunk_12 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8,
                                 task_id_9, task_id_10, task_id_11, task_id_12)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
    schedule_task(scheduler, task_id_9)
    schedule_task(scheduler, task_id_10)
    schedule_task(scheduler, task_id_11)
    schedule_task(scheduler, task_id_12)
end

_G.sim_event_chunk_13 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8,
                                 task_id_9, task_id_10, task_id_11, task_id_12, task_id_13)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
    schedule_task(scheduler, task_id_9)
    schedule_task(scheduler, task_id_10)
    schedule_task(scheduler, task_id_11)
    schedule_task(scheduler, task_id_12)
    schedule_task(scheduler, task_id_13)
end

_G.sim_event_chunk_14 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8,
                                 task_id_9, task_id_10, task_id_11, task_id_12, task_id_13, task_id_14)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
    schedule_task(scheduler, task_id_9)
    schedule_task(scheduler, task_id_10)
    schedule_task(scheduler, task_id_11)
    schedule_task(scheduler, task_id_12)
    schedule_task(scheduler, task_id_13)
    schedule_task(scheduler, task_id_14)
end

_G.sim_event_chunk_15 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8,
                                 task_id_9, task_id_10, task_id_11, task_id_12, task_id_13, task_id_14, task_id_15)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
    schedule_task(scheduler, task_id_9)
    schedule_task(scheduler, task_id_10)
    schedule_task(scheduler, task_id_11)
    schedule_task(scheduler, task_id_12)
    schedule_task(scheduler, task_id_13)
    schedule_task(scheduler, task_id_14)
    schedule_task(scheduler, task_id_15)
end

_G.sim_event_chunk_16 = function(task_id_1, task_id_2, task_id_3, task_id_4, task_id_5, task_id_6, task_id_7, task_id_8,
                                 task_id_9, task_id_10, task_id_11, task_id_12, task_id_13, task_id_14, task_id_15,
                                 task_id_16)
    local schedule_task = scheduler.schedule_task
    schedule_task(scheduler, task_id_1)
    schedule_task(scheduler, task_id_2)
    schedule_task(scheduler, task_id_3)
    schedule_task(scheduler, task_id_4)
    schedule_task(scheduler, task_id_5)
    schedule_task(scheduler, task_id_6)
    schedule_task(scheduler, task_id_7)
    schedule_task(scheduler, task_id_8)
    schedule_task(scheduler, task_id_9)
    schedule_task(scheduler, task_id_10)
    schedule_task(scheduler, task_id_11)
    schedule_task(scheduler, task_id_12)
    schedule_task(scheduler, task_id_13)
    schedule_task(scheduler, task_id_14)
    schedule_task(scheduler, task_id_15)
    schedule_task(scheduler, task_id_16)
end


return verilua

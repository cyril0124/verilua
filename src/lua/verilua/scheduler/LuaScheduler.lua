local cfg = _G.cfg

---@alias verilua.scheduler.TaskID integer
---@alias verilua.scheduler.EventID integer
---@class verilua.scheduler.TaskName: string
---@alias verilua.scheduler.TaskCallbackType verilua.scheduler.YieldType
---@alias verilua.scheduler.CoroutineTaskBody fun()

--- Task function used in `fork`, `jfork`, `initial`, `final`.
--- It should be a function without parameters and return value.
---@alias verilua.scheduler.TaskFunction fun()

---@class (exact) verilua.handles.EventHandle
---@field __type "EventHandle" | "EventHandleForJFork"
---@field _scheduler verilua.scheduler.LuaScheduler
---@field name string
---@field event_id verilua.scheduler.EventID
---@field has_pending_wait fun(self: verilua.handles.EventHandle): boolean Check if there are pending tasks waiting for this event
---@field wait fun(self: verilua.handles.EventHandle)
---@field send fun(self: verilua.handles.EventHandle)
---@field remove fun(self: verilua.handles.EventHandle) Mark this EventHandle as removed

---@class (exact) verilua.scheduler.LuaScheduler
---@field private task_coroutine_map table<verilua.scheduler.TaskID, thread> Map of task IDs to coroutine threads
---@field private task_body_map table<verilua.scheduler.TaskID, verilua.scheduler.CoroutineTaskBody> Map of task IDs to coroutine task bodies
---@field private task_name_map_running table<verilua.scheduler.TaskID, string> Map of running task IDs to task names
---@field private task_name_map_archived table<verilua.scheduler.TaskID, string> Map of archived task IDs to task names
---@field private task_fired_status_map table<verilua.scheduler.TaskID, boolean> Map of task IDs to their fired status
---@field private task_execution_count_map table<verilua.scheduler.TaskID, integer> Map of task IDs to their execution count
---@field private pending_removal_tasks verilua.scheduler.TaskID[] List of task IDs pending removal
---@field private user_removal_tasks verilua.scheduler.TaskID[] List of user specified task IDs to be removed
---@field private user_removal_tasks_set table<verilua.scheduler.TaskID, boolean> Set of user specified task IDs to be removed
---@field private posedge_tasks table<verilua.scheduler.TaskID, boolean> Set of task IDs triggered on posedge (available only when EDGE_STEP is enabled)
---@field private negedge_tasks table<verilua.scheduler.TaskID, boolean> Set of task IDs triggered on negedge (available only when EDGE_STEP is enabled)
---@field private next_task_id verilua.scheduler.TaskID Next available task ID
---@field private next_event_id verilua.scheduler.EventID Next available event ID
---@field event_task_id_list_map table<verilua.scheduler.EventID, verilua.scheduler.TaskID[]> Map of event IDs to lists of task IDs
---@field event_name_map table<verilua.scheduler.EventID, string> Map of event IDs to event names
---@field private has_wakeup_event boolean Indicates if there is a wakeup event
---@field private pending_wakeup_event table<verilua.scheduler.EventID, any> List of pending wakeup event IDs
---@field private acc_time_table table<string, number> Accumulated time table
---@field private _is_valid_task_id fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID): boolean Checks if a task ID is valid
---@field private _is_valid_event_id fun(self: verilua.scheduler.LuaScheduler, event_id: verilua.scheduler.EventID): boolean Checks if an event ID is valid
---@field private _alloc_task_id fun(self: verilua.scheduler.LuaScheduler): verilua.scheduler.TaskID Allocates a new task ID
---@field private _alloc_event_id fun(self: verilua.scheduler.LuaScheduler): verilua.scheduler.EventID Allocates a new event ID
---@field private _remove_task fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID) Removes a task by ID
---@field private _register_callback fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID, callback_type: verilua.scheduler.TaskCallbackType, integer_value: integer) Registers a callback for a task
---@field NULL_TASK_ID verilua.scheduler.TaskID Constant representing an invalid task ID(0)
---@field curr_task_id verilua.scheduler.TaskID Current task ID
---@field curr_wakeup_event_id verilua.scheduler.EventID Current wakeup event ID
---@field private new_event_hdl fun(self: verilua.scheduler.LuaScheduler, event_name: string, user_event_id?: verilua.scheduler.EventID): verilua.handles.EventHandle Creates a new event handle
---@field private get_event_hdl fun(self: verilua.scheduler.LuaScheduler, event_name: string, user_event_id?: verilua.scheduler.EventID): verilua.handles.EventHandle Alias for new_event_hdl
---@field private send_event fun(self: verilua.scheduler.LuaScheduler, event_id: verilua.scheduler.EventID) Sends an event
---@field remove_task fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID) Removes a task by ID
---@field check_task_exists fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID): boolean Checks if a task exists
---@field append_task fun(self: verilua.scheduler.LuaScheduler, task_id?: verilua.scheduler.TaskID, task_name: string, task_body: verilua.scheduler.CoroutineTaskBody, start_now?: boolean): verilua.scheduler.TaskID Appends or registers a new task
---@field wakeup_task fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID) Wakes up a registered task
---@field try_wakeup_task fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID) Tries to wake up a registered task, does nothing if the task is still running
---@field schedule_task fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID) Schedules a specific task
---@field schedule_tasks fun(self: verilua.scheduler.LuaScheduler, task_id: verilua.scheduler.TaskID) Schedules multiple tasks
---@field schedule_all_tasks fun(self: verilua.scheduler.LuaScheduler) Schedules all tasks
---@field schedule_posedge_tasks fun(self: verilua.scheduler.LuaScheduler)|nil Schedules positive edge tasks (available only when EDGE_STEP is enabled)
---@field schedule_negedge_tasks fun(self: verilua.scheduler.LuaScheduler)|nil Schedules negative edge tasks (available only when EDGE_STEP is enabled)
---@field list_tasks fun(self: verilua.scheduler.LuaScheduler) List all running tasks

local scheduler
do
    local scheduler_mode = cfg.mode
    local perf_time = os.getenv("VL_PERF_TIME") == "1"
    local scheduler_suffix = perf_time and "P" or ""

    if scheduler_mode == "normal" then
        scheduler = require("verilua.scheduler.LuaNormalSchedulerV2" .. scheduler_suffix)
    elseif scheduler_mode == "step" then
        scheduler = require("verilua.scheduler.LuaStepSchedulerV2" .. scheduler_suffix)
    elseif scheduler_mode == "edge_step" then
        scheduler = require("verilua.scheduler.LuaEdgeStepSchedulerV2" .. scheduler_suffix)
    else
        assert(false, [[
            Unknown scheduler mode! maybe you forget to set it? please set `cfg.mode` to "normal", "step" or "edge_step"
        ]])
    end

    verilua_debug("Scheduler mode: %s", scheduler_mode)
end

---@cast scheduler verilua.scheduler.LuaScheduler
return scheduler

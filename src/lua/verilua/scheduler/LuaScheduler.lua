local cfg = _G.cfg

---@alias TaskID integer
---@alias EventID integer
---@alias TaskCallbackType integer
---@alias FunctionTaskBody fun(): boolean|nil
---@alias CoroutineYieldInfo [integer, string, integer]
---@alias CoroutineTaskBody fun()

---@class (exact) EventHandle
---@field __type "EventHandle" | "EventHandleForJFork"
---@field _scheduler LuaScheduler
---@field name string
---@field event_id EventID
---@field has_pending_wait fun(self: EventHandle): boolean Check if there are pending tasks waiting for this event
---@field wait fun(self: EventHandle)
---@field send fun(self: EventHandle)
---@field remove fun(self: EventHandle) Mark this EventHandle as removed

---@class (exact) LuaScheduler
---@field private running_task_count integer Number of running tasks
---@field private task_yield_info_map table<TaskID, CoroutineYieldInfo> Map of task IDs to coroutine yield info
---@field private task_coroutine_map table<TaskID, thread> Map of task IDs to coroutine threads
---@field private task_body_map table<TaskID, CoroutineTaskBody> Map of task IDs to coroutine task bodies
---@field private task_name_map_running table<TaskID, string> Map of running task IDs to task names
---@field private task_name_map_archived table<TaskID, string> Map of archived task IDs to task names
---@field private task_fired_status_map table<TaskID, boolean> Map of task IDs to their fired status
---@field private task_execution_count_map table<TaskID, integer> Map of task IDs to their execution count
---@field private pending_removal_tasks table<TaskID> List of task IDs pending removal
---@field private user_removal_tasks table<TaskID> List of user specified task IDs to be removed
---@field private posedge_tasks table<TaskID, boolean>|nil Available only when EDGE_STEP is enabled)
---@field private negedge_tasks table<TaskID, boolean>|nil Available only when EDGE_STEP is enabled)
---@field event_task_id_list_map table<EventID, TaskID[]> Map of event IDs to lists of task IDs
---@field event_name_map table<EventID, string> Map of event IDs to event names
---@field private has_wakeup_event boolean Indicates if there is a wakeup event
---@field private pending_wakeup_event table<EventID, any> List of pending wakeup event IDs
---@field private acc_time_table table<string, number> Accumulated time table
---@field private _is_coroutine_task fun(self: LuaScheduler, task_id: TaskID): boolean Checks if a task is a coroutine task
---@field private _alloc_coroutine_task_id fun(self: LuaScheduler): TaskID Allocates a new coroutine task ID
---@field private _remove_task fun(self: LuaScheduler, task_id: TaskID) Removes a task by ID
---@field private _register_callback fun(self: LuaScheduler, task_id: TaskID, callback_type: TaskCallbackType, str_value: string, integer_value: integer) Registers a callback for a task
---@field curr_task_id TaskID Current task ID
---@field curr_wakeup_event_id EventID Current wakeup event ID
---@field private new_event_hdl fun(self: LuaScheduler, event_name: string, user_event_id?: EventID): EventHandle Creates a new event handle
---@field private get_event_hdl fun(self: LuaScheduler, event_name: string, user_event_id?: EventID): EventHandle Alias for new_event_hdl
---@field private send_event fun(self: LuaScheduler, event_id: EventID) Sends an event
---@field remove_task fun(self: LuaScheduler, task_id: TaskID) Removes a task by ID
---@field check_task_exists fun(self: LuaScheduler, task_id: TaskID): boolean Checks if a task exists
---@field append_task fun(self: LuaScheduler, task_id?: TaskID, task_name: string, task_body: CoroutineTaskBody, start_now?: boolean): TaskID Appends or registers a new task
---@field wakeup_task fun(self: LuaScheduler, task_id: TaskID) Wakes up a registered task
---@field try_wakeup_task fun(self: LuaScheduler, task_id: TaskID) Tries to wake up a registered task, does nothing if the task is still running
---@field schedule_task fun(self: LuaScheduler, task_id: TaskID) Schedules a specific task
---@field schedule_tasks fun(self: LuaScheduler, task_id: TaskID) Schedules multiple tasks
---@field schedule_all_tasks fun(self: LuaScheduler) Schedules all tasks
---@field schedule_posedge_tasks fun(self: LuaScheduler)|nil Schedules positive edge tasks (available only when EDGE_STEP is enabled)
---@field schedule_negedge_tasks fun(self: LuaScheduler)|nil Schedules negative edge tasks (available only when EDGE_STEP is enabled)
---@field list_tasks fun(self: LuaScheduler) Lists all running tasks

local scheduler
if os.getenv("VL_PREBUILD") then
    scheduler = require("verilua.scheduler.LuaDummyScheduler")
else
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

---@cast scheduler LuaScheduler
return scheduler

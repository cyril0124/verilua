local cfg = _G.cfg
local SchedulerMode = _G.SchedulerMode

---@alias TaskID integer
---@alias EventID integer
---@alias TaskCallbackType integer
---@alias FunctionTaskBody fun(): boolean|nil
---@alias CoroutineYieldInfo [integer, string, integer]
---@alias CoroutineTaskBody fun()

---@class (exact) EventHandle
---@field _scheduler LuaScheduler
---@field name string
---@field event_id EventID
---@field wait fun(self: EventHandle)
---@field send fun(self: EventHandle)

--- @class (exact) LuaScheduler
--- @field private task_count integer Number of tasks
--- @field private task_function_map table<TaskID, FunctionTaskBody> Map of task IDs to function task bodies
--- @field private task_yield_info_map table<TaskID, CoroutineYieldInfo> Map of task IDs to coroutine yield info
--- @field private task_coroutine_map table<TaskID, thread> Map of task IDs to coroutine threads
--- @field private task_body_map table<TaskID, CoroutineTaskBody> Map of task IDs to coroutine task bodies
--- @field private task_name_map_running table<TaskID, string> Map of running task IDs to task names
--- @field private task_name_map_archived table<TaskID, string> Map of archived task IDs to task names
--- @field private task_fired_status_map table<TaskID, boolean> Map of task IDs to their fired status
--- @field private task_execution_count_map table<TaskID, integer> Map of task IDs to their execution count
--- @field private pending_removal_tasks table<TaskID> List of task IDs pending removal
--- @field private user_removal_tasks table<TaskID> List of user specified task IDs to be removed
--- @field private posedge_tasks table<TaskID, boolean>|nil Available only when EDGE_STEP is enabled)
--- @field private negedge_tasks table<TaskID, boolean>|nil Available only when EDGE_STEP is enabled)
--- @field private event_task_id_list_map table<EventID, table<TaskID, any>> Map of event IDs to lists of task IDs
--- @field private event_name_map table<EventID, string> Map of event IDs to event names
--- @field private has_wakeup_event boolean Indicates if there is a wakeup event
--- @field private pending_wakeup_event table<EventID, any> List of pending wakeup event IDs
--- @field private acc_time_table table<string, number> Accumulated time table
--- @field private _is_coroutine_task fun(self: LuaScheduler, task_id: TaskID): boolean Checks if a task is a coroutine task
--- @field private _alloc_coroutine_task_id fun(self: LuaScheduler): TaskID Allocates a new coroutine task ID
--- @field private _alloc_function_task_id fun(self: LuaScheduler): TaskID Allocates a new function task ID
--- @field private _remove_task fun(self: LuaScheduler, task_id: TaskID) Removes a task by ID
--- @field private _register_callback fun(self: LuaScheduler, task_id: TaskID, callback_type: TaskCallbackType, str_value: string, integer_value: integer) Registers a callback for a task
--- @field remove_task fun(self: LuaScheduler, task_id: TaskID) Removes a task by ID
--- @field check_task_exists fun(self: LuaScheduler, task_id: TaskID): boolean Checks if a task exists
--- @field append_task fun(self: LuaScheduler, task_id: TaskID|nil, task_name: string, task_body: CoroutineTaskBody, start_now: boolean): TaskID Appends or registers a new task
--- @field wakeup_task fun(self: LuaScheduler, task_id: TaskID) Wakes up a registered task
--- @field try_wakeup_task fun(self: LuaScheduler, task_id: TaskID) Tries to wake up a registered task, does nothing if the task is still running
--- @field append_function_task fun(self: LuaScheduler, task_id: TaskID, task_name: string, task_body: FunctionTaskBody, yield_task: CoroutineTaskBody, start_now: boolean): TaskID Appends a function task
--- @field schedule_task fun(self: LuaScheduler, task_id: TaskID) Schedules a specific task
--- @field schedule_tasks fun(self: LuaScheduler, task_id: TaskID) Schedules multiple tasks
--- @field schedule_all_tasks fun(self: LuaScheduler) Schedules all tasks
--- @field schedule_posedge_tasks fun(self: LuaScheduler)|nil Schedules positive edge tasks (available only when EDGE_STEP is enabled)
--- @field schedule_negedge_tasks fun(self: LuaScheduler)|nil Schedules negative edge tasks (available only when EDGE_STEP is enabled)
--- @field list_tasks fun(self: LuaScheduler) Lists all tasks
--- @field new_event_hdl fun(self: LuaScheduler, event_name: string, user_event_id: EventID): EventHandle Creates a new event handle
--- @field get_event_hdl fun(self: LuaScheduler, event_name: string, user_event_id: EventID): EventHandle Alias for new_event_hdl
--- @field send_event fun(self: LuaScheduler, event_id: EventID) Sends an event

local scheduler
if os.getenv("VL_PREBUILD") then
    scheduler = require("verilua.scheduler.LuaDummyScheduler")
else
    local mode = cfg.mode
    local perf_time = os.getenv("VL_PERF_TIME") == "1"

    if mode == SchedulerMode.NORMAL then
        scheduler = require("verilua.scheduler.LuaNormalSchedulerV2" .. (perf_time and "P" or ""))
    elseif mode == SchedulerMode.STEP then
        scheduler = require("verilua.scheduler.LuaStepSchedulerV2" .. (perf_time and "P" or ""))
    elseif mode == SchedulerMode.DOMINANT then
        assert(false, "TODO:")
        scheduler = require("verilua.scheduler.LuaDominantSchedulerV2" .. (perf_time and "P" or ""))
    elseif mode == SchedulerMode.EDGE_STEP then
        scheduler = require("verilua.scheduler.LuaEdgeStepSchedulerV2" .. (perf_time and "P" or ""))
    else
        assert(false, "Unknown scheduler mode! maybe you forget to set it? please set `cfg.mode` to `normal`, `SchedulerMode.STEP` or `SchedulerMode.DOMINANT`")
    end
end

---@cast scheduler LuaScheduler
return scheduler
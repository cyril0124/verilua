--[[luajit-pro, {NORMAL = 1, STEP = 0, EDGE_STEP = 0, ACC_TIME = 0, SAFETY = 0}]]

---@diagnostic disable: need-check-nil, unnecessary-assert

if _G.NORMAL and _G.STEP and _G.EDGE_STEP then
    assert(false, "Should not have both NORMAL, STEP and EDGE_STEP")
end

if not _G.NORMAL and not _G.STEP and not _G.EDGE_STEP then
    assert(false, "Should have either NORMAL, STEP or EDGE_STEP")
end

local safety_assert
if _G.SAFETY then
    safety_assert = function(cond, ...)
        if not cond then
            print(debug.traceback())
            assert(false, ...)
        end
    end
end

local debug = require "debug"
local vpiml = require "vpiml"
local class = require "pl.class"
local coroutine = require "coroutine"
local table_clear = require "table.clear"
local Logger = require "verilua.utils.Logger"

local f = string.format
local table_remove = table.remove
local table_insert = table.insert
local coro_yield = coroutine.yield
local coro_resume = coroutine.resume
local coro_create = coroutine.create

---@cast coro_yield verilua.scheduler.CoroYieldFunc

---@type fun(): number
local os_clock
if _G.ACC_TIME then
    os_clock = os.clock
end

local Timer = 0
local PosedgeHDL = 1
local NegedgeHDL = 2
local PosedgeAlways = 3
local PosedgeAlwaysHDL = 4
local NegedgeAlways = 5
local NegedgeAlwaysHDL = 6
local EdgeHDL = 7
local EarlyExit = 8
local Event = 9
local ReadWrite = 10
local ReadOnly = 11
local NextSimTime = 12
local NOOP = 5555

---@class (exact) verilua.scheduler.LuaScheduler_gen
---@field private task_coroutine_map table<verilua.scheduler.TaskID, thread> Map of task IDs to coroutine threads
---@field private task_body_map table<verilua.scheduler.TaskID, verilua.scheduler.CoroutineTaskBody> Map of task IDs to coroutine task bodies
---@field private task_name_map_running table<verilua.scheduler.TaskID, string> Map of running task IDs to task names
---@field private task_name_map_archived table<verilua.scheduler.TaskID, string> Map of archived task IDs to task names
---@field private task_fired_status_map table<verilua.scheduler.TaskID, boolean> Map of task IDs to their fired status
---@field private task_execution_count_map table<verilua.scheduler.TaskID, integer> Map of task IDs to their execution count
---@field private pending_removal_tasks table<integer, verilua.scheduler.TaskID> List of task IDs pending removal
---@field private nr_pending_removal_tasks integer Number of tasks pending removal
---@field private nr_user_removal_tasks integer Number of user specified task IDs to be removed
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
---@field private _is_valid_task_id fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID): boolean Checks if a task ID is valid
---@field private _is_valid_event_id fun(self: verilua.scheduler.LuaScheduler_gen, event_id: verilua.scheduler.EventID): boolean Checks if an event ID is valid
---@field private _alloc_task_id fun(self: verilua.scheduler.LuaScheduler_gen): verilua.scheduler.TaskID Allocates a new task ID
---@field private _alloc_event_id fun(self: verilua.scheduler.LuaScheduler_gen): verilua.scheduler.EventID Allocates a new event ID
---@field private _remove_task fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID) Removes a task by ID
---@field private _register_callback fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID, callback_type: verilua.scheduler.TaskCallbackType, integer_value: integer) Registers a callback for a task
---@field NULL_TASK_ID verilua.scheduler.TaskID Constant representing an invalid task ID(0)
---@field curr_task_id verilua.scheduler.TaskID Current task ID
---@field curr_wakeup_event_id verilua.scheduler.EventID Current wakeup event ID
---@field private new_event_hdl fun(self: verilua.scheduler.LuaScheduler_gen, event_name: string, user_event_id?: verilua.scheduler.EventID): verilua.handles.EventHandle Creates a new event handle
---@field private get_event_hdl fun(self: verilua.scheduler.LuaScheduler_gen, event_name: string, user_event_id?: verilua.scheduler.EventID): verilua.handles.EventHandle Alias for new_event_hdl
---@field get_running_tasks fun(self: verilua.scheduler.LuaScheduler_gen): table<integer, verilua.scheduler.TaskInfo> Get all running tasks
---@field private send_event fun(self: verilua.scheduler.LuaScheduler_gen, event_id: verilua.scheduler.EventID) Sends an event
---@field remove_task fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID) Removes a task by ID
---@field check_task_exists fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID): boolean Checks if a task exists
---@field append_task fun(self: verilua.scheduler.LuaScheduler_gen, task_id?: verilua.scheduler.TaskID, task_name: string, task_body: verilua.scheduler.CoroutineTaskBody, start_now?: boolean): verilua.scheduler.TaskID Appends or registers a new task
---@field wakeup_task fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID) Wakes up a registered task
---@field try_wakeup_task fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID) Tries to wake up a registered task, does nothing if the task is still running
---@field schedule_task fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID) Schedules a specific task
---@field schedule_tasks fun(self: verilua.scheduler.LuaScheduler_gen, task_id: verilua.scheduler.TaskID) Schedules multiple tasks
---@field schedule_all_tasks fun(self: verilua.scheduler.LuaScheduler_gen) Schedules all tasks
---@field schedule_posedge_tasks fun(self: verilua.scheduler.LuaScheduler_gen)|nil Schedules positive edge tasks (available only when EDGE_STEP is enabled)
---@field schedule_negedge_tasks fun(self: verilua.scheduler.LuaScheduler_gen)|nil Schedules negative edge tasks (available only when EDGE_STEP is enabled)
---@field list_tasks fun(self: verilua.scheduler.LuaScheduler_gen) List all running tasks
local Scheduler = class()

-- `0` represents invalid task id/event id
local NULL_TASK_ID = 0

local SCHEDULER_MIN_TASK_ID = 1
local SCHEDULER_MAX_TASK_ID = 0xFFFFFFF -- 268435455

local SCHEDULER_MIN_EVENT_ID = 1
local SCHEDULER_MAX_EVENT_ID = 0xFFFFFFF -- 268435455

function Scheduler:_init()
    self.task_coroutine_map = {}
    self.task_body_map = {}
    self.task_name_map_running = {}
    self.task_name_map_archived = {}
    self.task_fired_status_map = {} -- Used to check if a task has been fired
    self.task_execution_count_map = {}

    self.nr_user_removal_tasks = 0
    self.user_removal_tasks_set = {}

    self.pending_removal_tasks = {}
    self.nr_pending_removal_tasks = 0

    ---@diagnostic disable-next-line: undefined-global
    if _G.EDGE_STEP then
        self.posedge_tasks = {}
        self.negedge_tasks = {}
    end

    self.next_task_id = SCHEDULER_MIN_TASK_ID
    self.next_event_id = SCHEDULER_MIN_EVENT_ID

    self.event_task_id_list_map = {}
    self.event_name_map = {}
    self.has_wakeup_event = false
    self.pending_wakeup_event = {}

    self.NULL_TASK_ID = NULL_TASK_ID
    self.curr_task_id = NULL_TASK_ID

    ---@diagnostic disable-next-line: undefined-global
    if _G.ACC_TIME then
        self.acc_time_table = {}
    end

    ---@diagnostic disable-next-line: undefined-global
    if _G.NORMAL then
        verilua_debug("[Scheduler]", "Using NORMAL scheduler")
        ---@diagnostic disable-next-line: undefined-global
    elseif _G.STEP then
        verilua_debug("[Scheduler]", "Using STEP scheduler")
    end
end

function Scheduler:_is_valid_task_id(id)
    return id <= SCHEDULER_MAX_TASK_ID and id >= SCHEDULER_MIN_TASK_ID
end

function Scheduler:_is_valid_event_id(id)
    return id <= SCHEDULER_MAX_EVENT_ID and id >= SCHEDULER_MIN_EVENT_ID
end

function Scheduler:check_task_exists(id)
    return self.task_name_map_running[id] ~= nil
end

function Scheduler:_alloc_task_id()
    while self.task_name_map_archived[self.next_task_id] ~= nil do
        self.next_task_id = self.next_task_id + 1
        if self.next_task_id > SCHEDULER_MAX_TASK_ID then
            assert(
                false,
                "[Scheduler] Failed to allocate task id! There are no available task id!"
            )
        end
    end

    -- TODO: How to recycle task id?
    local id = self.next_task_id
    self.next_task_id = self.next_task_id + 1
    if self.next_task_id > SCHEDULER_MAX_TASK_ID then
        assert(
            false,
            "[Scheduler] Failed to allocate task id! There are no available task id!"
        )
    end

    return id
end

function Scheduler:_alloc_event_id()
    while self.event_name_map[self.next_event_id] ~= nil do
        self.next_event_id = self.next_event_id + 1
        if self.next_event_id > SCHEDULER_MAX_EVENT_ID then
            assert(
                false,
                "[Scheduler] Failed to allocate event id! There are no available event id!"
            )
        end
    end

    local id = self.next_event_id
    self.next_event_id = self.next_event_id + 1
    if self.next_event_id > SCHEDULER_MAX_EVENT_ID then
        assert(
            false,
            "[Scheduler] Failed to allocate event id! There are no available event id!"
        )
    end

    return id
end

function Scheduler:_remove_task(id)
    table_insert(self.pending_removal_tasks, id)
    self.nr_pending_removal_tasks = self.nr_pending_removal_tasks + 1

    ---@diagnostic disable-next-line: undefined-global
    if _G.EDGE_STEP then
        if self.posedge_tasks[id] then
            self.posedge_tasks[id] = nil
        elseif self.negedge_tasks[id] then
            self.negedge_tasks[id] = nil
        end
    end
end

function Scheduler:remove_task(id)
    if not self.task_name_map_archived[id] then
        if id == 0 then
            assert(
                false,
                "[Scheduler] Invalid task id: 0, `task id: 0` is not a valid task id(used for representing a non-initialized task), the available task id range is from " ..
                SCHEDULER_MIN_TASK_ID .. " to " .. SCHEDULER_MAX_TASK_ID
            )
        else
            assert(false, "[Scheduler] Invalid task id! task id: " .. id)
        end
    end

    ---@cast id -0

    if self.task_name_map_running[id] ~= nil then
        self.user_removal_tasks_set[id] = true
        self.nr_user_removal_tasks = self.nr_user_removal_tasks + 1
    end
end

function Scheduler:_register_callback(id, cb_type, integer_value)
    if _G.NORMAL then
        if cb_type == PosedgeHDL then
            vpiml.vpiml_register_posedge_callback(integer_value, id)
        elseif cb_type == PosedgeAlwaysHDL then
            vpiml.vpiml_register_posedge_callback_always(integer_value, id)
        elseif cb_type == NegedgeHDL then
            vpiml.vpiml_register_negedge_callback(integer_value, id)
        elseif cb_type == NegedgeAlwaysHDL then
            vpiml.vpiml_register_negedge_callback_always(integer_value, id)
        elseif cb_type == ReadWrite then
            vpiml.vpiml_register_rw_synch_callback(id)
        elseif cb_type == ReadOnly then
            vpiml.vpiml_register_rd_synch_callback(id)
        elseif cb_type == NextSimTime then
            vpiml.vpiml_register_next_sim_time_callback(id)
        elseif cb_type == Timer then
            vpiml.vpiml_register_time_callback(integer_value, id)
        elseif cb_type == Event then
            if self.event_name_map[integer_value] == nil then
                assert(false, "Unknown event => " .. integer_value)
            end
            table_insert(self.event_task_id_list_map[integer_value], id)
        elseif cb_type == NOOP then
            -- do nothing
        else
            assert(false, "Unknown YieldType => " .. tostring(cb_type))
        end
    elseif _G.STEP then
        if cb_type == Event then
            if self.event_name_map[integer_value] == nil then
                assert(false, "Unknown event => " .. integer_value)
            end
            table_insert(self.event_task_id_list_map[integer_value], id)
        end
    elseif _G.EDGE_STEP then
        if cb_type == PosedgeHDL or cb_type == PosedgeAlwaysHDL or cb_type == Timer then
            self.posedge_tasks[id] = true
        elseif cb_type == NegedgeHDL or cb_type == NegedgeAlwaysHDL then
            self.negedge_tasks[id] = true
        elseif cb_type == NOOP then
            -- do nothing
        elseif cb_type == Event then
            if self.event_name_map[integer_value] == nil then
                assert(false, "Unknown event => " .. integer_value)
            end
            table_insert(self.event_task_id_list_map[integer_value], id)
        else
            assert(false, "Unknown YieldType => " .. tostring(cb_type))
        end
    end
end

-- Used for creating a new coroutine task
function Scheduler:append_task(id, name, task_body, start_now)
    ---@diagnostic disable: undefined-global
    if _G.SAFETY then
        local id_type = type(id)
        local name_type = type(name)
        local task_body_type = type(task_body)
        local start_now_type = type(start_now)
        safety_assert(
            id_type == "nil" or id_type == "number",
            "[Scheduler] append_task: `id` must be a number! but got " .. id_type .. "!"
        )
        safety_assert(
            name_type == "string",
            "[Scheduler] append_task: `name` must be a string! but got " .. name_type .. "!"
        )
        safety_assert(
            task_body_type == "function",
            "[Scheduler] append_task: `task_body` must be a function! but got " .. task_body_type .. "!"
        )
        safety_assert(
            start_now_type == "boolean" or start_now_type == "nil",
            "[Scheduler] append_task: `start_now` must be a boolean! but got " .. start_now_type .. "!"
        )
    end

    local task_id = id
    if id then
        if not self:_is_valid_task_id(id) then
            assert(false, "[Scheduler] Invalid coroutine task id!")
        end

        if self:check_task_exists(id) then
            local task_name = self.task_name_map_running[id]
            assert(false, "[Scheduler] Task already exists! task_id: " .. id .. ", task_name: " .. task_name)
        end
    else
        task_id = self:_alloc_task_id()
    end
    ---@cast task_id verilua.scheduler.TaskID

    self.task_name_map_running[task_id] = name
    self.task_name_map_archived[task_id] = name
    self.task_fired_status_map[task_id] = false
    self.task_coroutine_map[task_id] = coro_create(task_body)
    self.task_body_map[task_id] = task_body
    self.task_execution_count_map[task_id] = 0

    -- print("[Scheduler] Task registered! task_id: " .. task_id .. ", task_name: " .. name)

    if (_G.NORMAL or _G.EDGE_STEP) then
        if start_now then
            self.task_fired_status_map[task_id] = true
            self:schedule_task(task_id)
        end
    end

    return task_id
end

function Scheduler:wakeup_task(id)
    local task_name = self.task_name_map_archived[id]
    if task_name == nil then
        assert(false, "[Scheduler] Task not registered! task_id: " .. id)
    end

    local removal_task_id = 1
    local found_in_removal_tasks = false
    if self.task_name_map_running[id] ~= nil then
        for i, r_id in ipairs(self.pending_removal_tasks) do
            if r_id == id then
                removal_task_id = i
                found_in_removal_tasks = true
                break
            end
        end

        if not found_in_removal_tasks then
            assert(false, "[Scheduler] Task already running! task_id: " .. id .. ", task_name: " .. task_name)
        end
    end

    if found_in_removal_tasks then
        table_remove(self.pending_removal_tasks, removal_task_id)
        self.nr_pending_removal_tasks = self.nr_pending_removal_tasks - 1
    end

    self.task_name_map_running[id] = task_name
    self.task_fired_status_map[id] = true
    self.task_coroutine_map[id] = coro_create(self.task_body_map[id])
    self:schedule_task(id)
end

function Scheduler:try_wakeup_task(id)
    if self:check_task_exists(id) then
        return
    else
        local task_name = self.task_name_map_archived[id]
        if task_name == nil then
            assert(false, "[Scheduler] Task not registered! task_id: " .. id)
        end

        self.task_name_map_running[id] = task_name
        self.task_fired_status_map[id] = true
        self.task_coroutine_map[id] = coro_create(self.task_body_map[id])
        self:schedule_task(id)
    end
end

function Scheduler:schedule_task(id)
    local nr_pending_removal_tasks = self.nr_pending_removal_tasks
    if nr_pending_removal_tasks > 0 then
        local pending_removal_tasks = self.pending_removal_tasks
        for i = 1, nr_pending_removal_tasks do
            local remove_id = pending_removal_tasks[i]

            self.task_name_map_running[remove_id] = nil
            self.task_execution_count_map[remove_id] = 0
            self.task_fired_status_map[remove_id] = false

            if _G.SAFETY then
                if remove_id == id then
                    assert(false, "remove_id == id")
                end
            end
        end
        self.nr_pending_removal_tasks = 0
        table_clear(pending_removal_tasks)
    end

    if self.nr_user_removal_tasks > 0 then
        if self.user_removal_tasks_set[id] then
            self.user_removal_tasks_set[id] = nil
            self.nr_user_removal_tasks = self.nr_user_removal_tasks - 1

            self.task_name_map_running[id] = nil
            self.task_execution_count_map[id] = 0
            self.task_fired_status_map[id] = false
            return
        end
    end

    local task_cnt = self.task_execution_count_map[id]
    self.task_execution_count_map[id] = task_cnt + 1

    local s, e
    if _G.ACC_TIME then
        s = os_clock()
    end

    local old_curr_task_id            = self.curr_task_id
    self.curr_task_id                 = id

    local ok
    local cb_type_or_err
    local integer_value
    ok, cb_type_or_err, integer_value = coro_resume(self.task_coroutine_map[id])

    ---@cast ok boolean
    ---@cast cb_type_or_err verilua.scheduler.TaskCallbackType
    ---@cast integer_value integer

    self.curr_task_id                 = old_curr_task_id
    if not ok then
        print(f(
            "[Scheduler] Error while executing task(id: %d, name: %s)\n\t%s",
            id,
            self.task_name_map_running[id],
            debug.traceback(self.task_coroutine_map[id], cb_type_or_err)
        ))
        io.flush()

        _G.VERILUA_GOT_ERROR = true
        assert(false)
    end

    if cb_type_or_err == nil or cb_type_or_err == EarlyExit then
        self:_remove_task(id)
    else
        self:_register_callback(id, cb_type_or_err, integer_value)
    end

    if _G.ACC_TIME then
        e = os_clock()
        local name = self.task_name_map_running[id]
        if _G.SAFETY then
            assert(
                type(name) == "string",
                "task name is not string => " .. tostring(name) .. " id: " .. tostring(id)
            )
        end

        local key = f("%d@%s", id, name)
        self.acc_time_table[key] = (self.acc_time_table[key] or 0) + (e - s)
    end

    if self.has_wakeup_event then
        self.has_wakeup_event = false
        for _, event_id in ipairs(self.pending_wakeup_event) do
            self.curr_wakeup_event_id = event_id
            local wakeup_task_id_list = self.event_task_id_list_map[event_id]
            for _, wakeup_task_id in ipairs(wakeup_task_id_list) do
                self:schedule_task(wakeup_task_id)
            end
            self.curr_wakeup_event_id = nil
            table_clear(self.event_task_id_list_map[event_id])
        end
        table_clear(self.pending_wakeup_event)
    end
end

function Scheduler:schedule_tasks(id)
    self:schedule_task(id)
end

function Scheduler:schedule_all_tasks()
    for id, _ in pairs(self.task_name_map_running) do
        if _G.NORMAL then
            local fired = self.task_fired_status_map[id]
            if not fired then
                self:schedule_task(id)
                self.task_fired_status_map[id] = true
            end
        else
            self:schedule_task(id)
        end
    end
end

function Scheduler:schedule_posedge_tasks()
    if _G.EDGE_STEP then
        for id, _ in pairs(self.posedge_tasks) do
            self:schedule_task(id)
        end
    else
        assert(false, "[Scheduler] schedule_posedge_tasks() is only available in EDGE_STEP mode!")
    end
end

function Scheduler:schedule_negedge_tasks()
    if _G.EDGE_STEP then
        for id, _ in pairs(self.negedge_tasks) do
            self:schedule_task(id)
        end
    else
        assert(false, "[Scheduler] schedule_negedge_tasks() is only available in EDGE_STEP mode!")
    end
end

function Scheduler:list_tasks()
    local logger = Logger.new("Scheduler")
    logger:section_start("Task Statistics", 74)
    if _G.ACC_TIME then
        local total_time = 0 --[[@as number]]
        local max_key_str_len = 0 --[[@as integer]]

        local task_name_count = {} --[[@as table<string, integer>]]
        for key, _time in pairs(self.acc_time_table) do
            local _task_id, task_name = key:match("([^@]+)@(.*)")
            task_name_count[task_name] = (task_name_count[task_name] or 0) + 1
        end

        -- Merge task names with more than 20 occurence into one key
        local filtered_acc_time_table = {} --[[@as table<string, number>]]
        for key, time in pairs(self.acc_time_table) do
            local _task_id, task_name = key:match("([^@]+)@(.*)")
            if task_name_count[task_name] >= 20 then
                key = f("<...>@%s", task_name)
                filtered_acc_time_table[key] = (filtered_acc_time_table[key] or 0) + time
            else
                filtered_acc_time_table[key] = time
            end

            total_time = total_time + time

            local len = #key
            if len > max_key_str_len then
                max_key_str_len = len
            end
        end
        self.acc_time_table = filtered_acc_time_table

        -- Sort the accumulated time table from small to large
        local sorted_keys = {} --[[@as table<integer, string>]]
        for key, _ in pairs(filtered_acc_time_table) do
            table_insert(sorted_keys, key)
        end
        table.sort(sorted_keys, function(a, b)
            ---@cast a string
            ---@cast b string
            return filtered_acc_time_table[a] < filtered_acc_time_table[b]
        end)

        for _, key in ipairs(sorted_keys) do
            local time = self.acc_time_table[key]
            local percent = time / total_time * 100
            local info = f("[%-" .. max_key_str_len .. "s] %7.2f ms  %s", key, time * 1000,
                logger:progress_bar(percent / 100, 25, true))
            logger:section_line(info, 74)
        end

        logger:section_line(f("total_time: %.2f s / %.2f ms", total_time, total_time * 1000), 74)
        logger:section_line(string.rep("─", 70), 74)
    end

    local max_name_str_len = 0 --[[@as integer]]
    for _, name in pairs(self.task_name_map_running) do
        local len = #name
        if len > max_name_str_len then
            max_name_str_len = len
        end
    end

    local idx = 0
    for id, name in pairs(self.task_name_map_running) do
        logger:section_line(f("[%2d] name: %-" .. max_name_str_len .. "s  id: %5d  cnt: %8d", idx, name, id,
            self.task_execution_count_map[id]), 74)
        idx = idx + 1
    end
    logger:section_end(74)
    print()
end

function Scheduler:get_running_tasks()
    local tasks = {}
    for id, name in pairs(self.task_name_map_running) do
        if not self.user_removal_tasks_set[id] then
            local is_pending_remove = false
            for _, pending_id in ipairs(self.pending_removal_tasks) do
                if pending_id == id then
                    is_pending_remove = true
                    break
                end
            end

            if not is_pending_remove then
                ---@type verilua.scheduler.TaskInfo
                local task_info = {
                    id = id,
                    name = name,
                }
                table_insert(tasks, task_info)
            end
        end
    end
    return tasks
end

function Scheduler:send_event(event_id)
    table_insert(self.pending_wakeup_event, event_id)
    self.has_wakeup_event = true
end

--
-- Example:
--      local scheduler = require "verilua.scheduler.LuaScheduler"
--      local test_ehdl = scheduler:new_event_hdl("test_1") -- event id will be randomly allocated
--      test_ehdl:wait()
--      test_ehdl:send()
--
--      local test_ehdl = scheduler:new_event_hdl("test_1", 1) -- manually set event_id
--
--      local test_ehdl = scheduler:new_event_hdl "test_1"
--
--
function Scheduler:new_event_hdl(name, user_event_id)
    if _G.SAFETY then
        safety_assert(type(name) == "string", "[Scheduler] new_event_hdl: name must be a string")
    end

    local event_id = user_event_id
    if not event_id then
        event_id = self:_alloc_event_id()
    else
        if not self:_is_valid_event_id(event_id) then
            assert(false, "[Scheduler] Invalid event id: " .. event_id)
        end
    end

    ---@cast event_id verilua.scheduler.EventID

    self.event_name_map[event_id] = name
    self.event_task_id_list_map[event_id] = {} -- task id comes from register_callback => (cb_type == Event)

    ---@type verilua.handles.EventHandle
    local ehdl = {
        __type = "EventHandle",
        _scheduler = self --[[@as verilua.scheduler.LuaScheduler]],
        name = name,
        event_id = event_id,
        has_pending_wait = function(this)
            return #self.event_task_id_list_map[this.event_id] > 0
        end,
        wait = function(this)
            coro_yield(Event, this.event_id)
        end,
        send = function(this)
            this._scheduler:send_event(this.event_id)
        end,
        remove = function(this)
            this._scheduler.event_name_map[this.event_id] = nil
        end
    }
    return ehdl
end

function Scheduler:get_event_hdl(name, user_event_id)
    return self:new_event_hdl(name, user_event_id)
end

return Scheduler()

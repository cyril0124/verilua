--[[luajit-pro, teal, pretty, {NORMAL = 1, STEP = 0, EDGE_STEP = 0, ACC_TIME = 0, SAFETY = 0, VERBOSE = 0}]]

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

local math = require "math"
local debug = require "debug"
local vpiml = require "vpiml"
local class = require "pl.class"
local coroutine = require "coroutine"
local table_clear = require "table.clear"

local f = string.format
local random = math.random
local table_remove = table.remove
local table_insert = table.insert
local coro_yield = coroutine.yield
local coro_resume = coroutine.resume
local coro_create = coroutine.create

local os_clock: function(): number
if _G.ACC_TIME then
    os_clock = os.clock
end

local Timer = 0
local Posedge = 1
local PosedgeHDL = 2
local Negedge = 3
local NegedgeHDL = 4
local PosedgeAlways = 5
local PosedgeAlwaysHDL = 6
local NegedgeAlways = 7
local NegedgeAlwaysHDL = 8
local Edge = 9
local EdgeHDL = 10
local EarlyExit = 11
local Event = 12
local NOOP = 44

local type TaskID = integer
local type TaskCallbackType = integer
local type EventID = integer
local type CoroutineTaskBody = function()
local type FunctionTaskBody = function(): boolean | nil
local type CoroutineYieldInfo = {integer, string, integer}

local record EventHandle
    __type: string
    _scheduler: SchedulerClass
    name: string
    event_id: EventID
    has_pending_wait: function(EventHandle): boolean
    wait: function(EventHandle)
    send: function(EventHandle)
    remove: function(EventHandle)
end

local record SchedulerClass
    -- Class member variables
    task_count: integer
    task_coroutine_map: {TaskID: thread} -- only for `coroutine` task
    task_body_map: {TaskID: CoroutineTaskBody}
    task_name_map_running: {TaskID: string} -- This map holds all the running task names
    task_name_map_archived: {TaskID: string} -- This map holds all the archived task names
    task_fired_status_map: {TaskID: boolean}
    task_execution_count_map:  {TaskID: integer}
    pending_removal_tasks: {TaskID}
    user_removal_tasks: {TaskID}
    posedge_tasks: {TaskID: boolean} -- Available only when `EDGE_STEP` is enabled
    negedge_tasks: {TaskID: boolean} -- Available only when `EDGE_STEP` is enabled
    curr_task_id: TaskID

    event_task_id_list_map: {EventID: {TaskID}}
    event_name_map: {EventID: string}
    has_wakeup_event: boolean
    pending_wakeup_event: {EventID}
    curr_wakeup_event_id: EventID

    acc_time_table: {string: number}

    -- Constructor
    _init: function(SchedulerClass)
    metamethod __call: function(SchedulerClass): SchedulerClass

    -- Private
    _is_coroutine_task: function(SchedulerClass, TaskID): boolean
    _alloc_coroutine_task_id: function(SchedulerClass): TaskID
    _remove_task: function(SchedulerClass, TaskID)
    _register_callback: function(SchedulerClass, TaskID, TaskCallbackType, string, integer)

    -- Public
    remove_task: function(SchedulerClass, TaskID)
    check_task_exists: function(SchedulerClass, TaskID): boolean
    append_task: function(SchedulerClass, TaskID, string, CoroutineTaskBody, boolean): TaskID -- Append/Register a new task
    wakeup_task: function(SchedulerClass, TaskID) -- Wakeup an registered task
    try_wakeup_task: function(SchedulerClass, TaskID) -- Try to wakeup an registered task, if the task is still running, do nothing, otherwise, wakeup it
    append_function_task: function(SchedulerClass, TaskID, string, FunctionTaskBody, CoroutineTaskBody, boolean): TaskID
    schedule_task: function(SchedulerClass, TaskID)
    schedule_tasks: function(SchedulerClass, TaskID)
    schedule_all_tasks: function(SchedulerClass)
    schedule_posedge_tasks: function(SchedulerClass) -- Available only when `EDGE_STEP` is enabled
    schedule_negedge_tasks: function(SchedulerClass) -- Available only when `EDGE_STEP` is enabled
    list_tasks: function(SchedulerClass)

    new_event_hdl: function(SchedulerClass, string, EventID): EventHandle
    get_event_hdl: function(SchedulerClass, string, EventID): EventHandle -- alias of `new_event_hdl`
    send_event: function(Scheduler, EventID)
end

local Scheduler: SchedulerClass = class()

-- TaskID from 0 to 99999 is reserved for coroutine task
local SCHEDULER_TASK_ID_MIN_COROUTINE = 0
local SCHEDULER_TASK_ID_MAX_COROUTINE = 99999

local SCHEDULER_TASK_MAX_COUNT = 100000
local SCHEDULER_MIN_EVENT_ID = 0
local SCHEDULER_MAX_EVENT_ID = 999

local SCHEDULER_ALLOC_TASK_ID_MAX_CNT = 99999
local SCHEDULER_ALLOC_EVENT_ID_MAX_CNT = 999

function Scheduler:_init()
    self.task_count = 0

    self.task_coroutine_map = {}
    self.task_body_map = {}
    self.task_name_map_running = {}
    self.task_name_map_archived = {}
    self.task_fired_status_map = {} -- Used to check if a task has been fired
    self.task_execution_count_map = {}
    self.pending_removal_tasks = {}
    self.user_removal_tasks = {}

    if _G.EDGE_STEP then
        self.posedge_tasks = {}
        self.negedge_tasks = {}
    end

    self.event_task_id_list_map = {}
    self.event_name_map = {}
    self.has_wakeup_event = false
    self.pending_wakeup_event = {}

    if _G.ACC_TIME then
        self.acc_time_table = {}
    end

    if _G.NORMAL then
        verilua_debug("[Scheduler]", "Using NORMAL scheduler")
    elseif _G.STEP then
        verilua_debug("[Scheduler]", "Using STEP scheduler")
    end
end

function Scheduler:_is_coroutine_task(id: TaskID): boolean
    return id <= SCHEDULER_TASK_ID_MAX_COROUTINE and id >= SCHEDULER_TASK_ID_MIN_COROUTINE
end

function Scheduler:check_task_exists(id: TaskID): boolean
    return self.task_name_map_running[id] ~= nil
end

function Scheduler:_alloc_coroutine_task_id(): TaskID
    local id = random(SCHEDULER_TASK_ID_MIN_COROUTINE, SCHEDULER_TASK_ID_MAX_COROUTINE)
    local cnt = 0
    while self.task_name_map_archived[id] ~= nil do
        id = random(SCHEDULER_TASK_ID_MIN_COROUTINE, SCHEDULER_TASK_ID_MAX_COROUTINE)
        cnt = cnt + 1
        if cnt >= SCHEDULER_ALLOC_TASK_ID_MAX_CNT then
            assert(false, "[Scheduler] Failed to allocate coroutine task id! too many attempts, maybe there are no available task id")
        end
    end
    return id
end

function Scheduler:_remove_task(id: TaskID)
    self.task_count = self.task_count - 1
    table_insert(self.pending_removal_tasks, id)

    if _G.EDGE_STEP then
        if self.posedge_tasks[id] then
            self.posedge_tasks[id] = nil
        elseif self.negedge_tasks[id] then
            self.negedge_tasks[id] = nil
        end
    end
end

function Scheduler:remove_task(id: TaskID)
    if not self.task_name_map_archived[id] then
        assert(false, "[Scheduler] Invalid task id! task_id: " .. id)
    end

    if self.task_name_map_running[id] then
        table_insert(self.user_removal_tasks, id)
    end
end

function Scheduler:_register_callback(id: TaskID, cb_type: TaskCallbackType, str_value: string, integer_value: integer)
    if _G.NORMAL then
        if cb_type == PosedgeHDL then
            vpiml.vpiml_register_posedge_callback(integer_value, id)
        elseif cb_type == Posedge then
			vpiml.vpiml_register_posedge_callback(vpiml.vpiml_handle_by_name_safe(str_value), id)
        elseif cb_type == PosedgeAlwaysHDL then
            vpiml.vpiml_register_posedge_callback_always(integer_value, id)
        elseif cb_type == NegedgeHDL then
            vpiml.vpiml_register_negedge_callback(integer_value, id)
        elseif cb_type == Negedge then
			vpiml.vpiml_register_negedge_callback(vpiml.vpiml_handle_by_name_safe(str_value), id)
        elseif cb_type == NegedgeAlwaysHDL then
            vpiml.vpiml_register_negedge_callback_always(integer_value, id)
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
        if cb_type == PosedgeHDL or cb_type == Posedge or cb_type == PosedgeAlwaysHDL or cb_type == Timer then
            self.posedge_tasks[id] = true
        elseif cb_type == NegedgeHDL or cb_type == Negedge or cb_type == NegedgeAlwaysHDL then
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
function Scheduler:append_task(id: TaskID, name: string, task_body: CoroutineTaskBody, start_now: boolean): TaskID
    if _G.NORMAL then
        assert(self.task_count <= SCHEDULER_TASK_MAX_COUNT, "[Normal Scheduler] Too many tasks!")
    elseif _G.STEP or _G.EDGE_STEP then
        assert(self.task_count <= SCHEDULER_TASK_MAX_COUNT, "[Step Scheduler] Too many tasks!")
    end

    if _G.SAFETY then
        safety_assert(id is TaskID or id is nil, "[Scheduler] append_tsak: `Task ID` must be a number! but got " .. type(id) .. "!")
        safety_assert(name is string, "[Scheduler] append_tsak: `Task name` must be a string! but got " .. type(name) .. "!")
        safety_assert(task_body is CoroutineTaskBody, "[Scheduler] append_tsak: `Task body` must be a function! but got " .. type(task_body) .. "!")
        safety_assert(start_now is boolean or start_now is nil, "[Scheduler] append_task: `start_now` must be a boolean! but got " .. type(start_now) .. "!")
    end

    local task_id: TaskID = id
    if id then
        if not self:_is_coroutine_task(id) then
            assert(false, "[Scheduler] Invalid coroutine task id!")
        end

        if self:check_task_exists(id) then
            local task_name = self.task_name_map_running[id]
            assert(false, "[Scheduler] Task already exists! task_id: " .. id .. ", task_name: " .. task_name )
        end
    else
        task_id = self:_alloc_coroutine_task_id()
    end

    self.task_name_map_running[task_id] = name
    self.task_name_map_archived[task_id] = name
    self.task_fired_status_map[task_id] = false
    self.task_coroutine_map[task_id] = coro_create(task_body as function)
    self.task_body_map[task_id] = task_body
    self.task_execution_count_map[task_id] = 0

    self.task_count = self.task_count + 1

    if (_G.NORMAL or _G.EDGE_STEP) then
        if start_now then
            self.task_fired_status_map[task_id] = true
            self:schedule_task(task_id)
        end
    end

    return task_id
end

function Scheduler:wakeup_task(id: TaskID)
    local task_name = self.task_name_map_archived[id]
    if task_name == nil then
        assert(false, "[Scheduler] Task not registered! task_id: " .. id)
    end

    if self.task_name_map_running[id] then
        assert(false, "[Scheduler] Task already running! task_id: " .. id .. ", task_name: " .. task_name)
    end
    
    self.task_name_map_running[id] = task_name
    self.task_fired_status_map[id] = true
    self.task_coroutine_map[id] = coro_create(self.task_body_map[id] as function)
    self:schedule_task(id)
end

function Scheduler:try_wakeup_task(id: TaskID)
    if self:check_task_exists(id) then
        return
    else
        local task_name = self.task_name_map_archived[id]
        if task_name == nil then
            assert(false, "[Scheduler] Task not registered! task_id: " .. id)
        end

        self.task_name_map_running[id] = task_name
        self.task_fired_status_map[id] = true
        self.task_coroutine_map[id] = coro_create(self.task_body_map[id] as function)
        self:schedule_task(id)
    end
end

function Scheduler:schedule_task(id: TaskID)
    for _, remove_id in ipairs(self.pending_removal_tasks) do
        self.task_name_map_running[remove_id] = nil
        self.task_execution_count_map[remove_id] = 0
        self.task_fired_status_map[remove_id] = false

        if _G.SAFETY then
            if remove_id == id then
                assert(false, "remove_id == id")
            end
        end
    end
    table_clear(self.pending_removal_tasks)

    for i, remove_id in ipairs(self.user_removal_tasks) do
		if remove_id == id then
			table_remove(self.user_removal_tasks, i)
			self.task_name_map_running[remove_id] = nil
			self.task_execution_count_map[remove_id] = 0
			self.task_fired_status_map[remove_id] = false
			return
		end
	end

    local task_cnt: integer = self.task_execution_count_map[id]
    self.task_execution_count_map[id] = task_cnt + 1

    local s, e: number, number
    if _G.ACC_TIME then
        s = os_clock()
    end

    local old_curr_task_id = self.curr_task_id
    self.curr_task_id = id
    local ok, cb_type_or_err, str_value, integer_value: boolean, TaskCallbackType, string, integer  = coro_resume(self.task_coroutine_map[id]) as (boolean, TaskCallbackType, string, integer)
    self.curr_task_id = old_curr_task_id
    if not ok then
        print(f("[Scheduler] Error while executing task(id: %d, name: %s)\n\t%s", id, self.task_name_map_running[id], debug.traceback(self.task_coroutine_map[id] as string, cb_type_or_err)))
        io.flush()

        _G.verilua_get_error = true
        assert(false)
    end

    if cb_type_or_err == nil or cb_type_or_err == EarlyExit then
        self:_remove_task(id)
    else
        self:_register_callback(id, cb_type_or_err, str_value, integer_value)
    end

    if _G.ACC_TIME then
        e = os_clock()
        local name = self.task_name_map_running[id]
        if _G.SAFETY then
            assert(name is string, "task name is not string => " .. tostring(name) .. " id: " .. tostring(id))
        end

        local key = tostring(id) .. "@" .. name
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

function Scheduler:schedule_tasks(id: TaskID)
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
	print("╔══════════════════════════════════════════════════════════════════════")
	print("║ [Scheduler] List Tasks:")
	print("╠══════════════════════════════════════════════════════════════════════")
    if _G.ACC_TIME then
        local total_time: number = 0
        local max_key_str_len: integer = 0

        local task_name_count: {string: integer} = {}
        for key, _time in pairs(self.acc_time_table) do
            local _task_id, task_name = key:match("([^@]+)@(.*)")
            task_name_count[task_name] = (task_name_count[task_name] or 0) + 1
        end

        -- Merge task names with more than 20 occurence into one key
        local filtered_acc_time_table: {string: number} = {}
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
        local sorted_keys: {string} = {}
        for key, _ in pairs(filtered_acc_time_table) do
            table.insert(sorted_keys, key)
        end
        table.sort(sorted_keys, function(a: string, b: string): boolean
            return filtered_acc_time_table[a] < filtered_acc_time_table[b]
        end)

        local max_str_len: integer = 0
        local print_str_vec: {string} = {}
        for _, key in ipairs(sorted_keys) do
            local time = self.acc_time_table[key]
            local percent = time / total_time * 100
            local s = f("║ [%" .. max_key_str_len .. "s]   %5.2f ms   percent: %5.2f%%", key, time * 1000, percent)
            local len = #s
            table_insert(print_str_vec, s)

            if len > max_str_len then
                max_str_len = len
            end
        end

        local get_progress_bar = function(progress: number, length: integer): string
            local completed: integer = math.floor(progress * length)
            local remaining: integer = length - completed
            local progressBar: string = "┃" .. string.rep("█", completed) .. "" .. string.rep("▒", remaining) .. "┃"
            return progressBar
        end
        
        local idx = 1
        for _, key in ipairs(sorted_keys) do
            local time = self.acc_time_table[key]
            local str = print_str_vec[idx]
            str = str .. string.rep(" ", max_str_len - #str)

            print(f("%-" .. max_str_len .. "s ", str) .. get_progress_bar(time / total_time, 30))
            idx = idx + 1
        end
        
        print(f("║ total_time: %.2f s / %.2f ms", total_time, total_time * 1000))
        print("╠══════════════════════════════════════════════════════════════════════")
    end

    local max_name_str_len: integer = 0
    for _, name in pairs(self.task_name_map_running) do
        local len = #name
        if len > max_name_str_len then
            max_name_str_len = len
        end
    end

    local idx = 0
    for id, name in pairs(self.task_name_map_running) do
        print(f("║ [%2d] name: %" .. max_name_str_len .. "s    id: %5d    cnt:%8d", idx, name, id, self.task_execution_count_map[id]))
        idx = idx + 1
    end
	print("╚══════════════════════════════════════════════════════════════════════")
    print()
end

function Scheduler:send_event(event_id: EventID)
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
function Scheduler:new_event_hdl(name: string, user_event_id: EventID): EventHandle
    if _G.SAFETY then
        safety_assert(name is string, "[Scheduler] new_event_hdl: name must be a string")
    end

    local event_id = user_event_id
    if not event_id then
        event_id = random(SCHEDULER_MIN_EVENT_ID, SCHEDULER_MAX_EVENT_ID)
        local cnt = 0
        while self.event_name_map[event_id] do
            event_id = random(SCHEDULER_MIN_EVENT_ID, SCHEDULER_MAX_EVENT_ID)
            cnt = cnt + 1
            if cnt >= SCHEDULER_ALLOC_EVENT_ID_MAX_CNT then
                assert(false, "[Scheduler] Failed to allocate event id! too many attempts, maybe there are no available event id")
            end
        end
    else
        assert(type(user_event_id) == "number" and user_event_id == math.floor(user_event_id), "user_event_id must be an integer")
    end

    self.event_name_map[event_id] = name
    self.event_task_id_list_map[event_id] = {} -- task id comes from register_callback => (cb_type == Event)

    return {
        __type = "EventHandle",
        _scheduler = self,
        name = name,
        event_id = event_id,
        has_pending_wait = function (this: EventHandle): boolean return #self.event_task_id_list_map[this.event_id] > 0 end,
        wait = function (this: EventHandle) coro_yield(Event, "", this.event_id) end,
        send = function (this: EventHandle) this._scheduler:send_event(this.event_id) end,
        remove = function (this: EventHandle)
            this._scheduler.event_name_map[this.event_id] = nil
        end
    }
end

function Scheduler:get_event_hdl(name: string, user_event_id: EventID): EventHandle
    return self:new_event_hdl(name, user_event_id)
end

return Scheduler()
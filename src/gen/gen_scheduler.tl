--[[luajit-pro, teal, pretty, {NORMAL = 1, STEP = 0, ACC_TIME = 0, ENABLE_FUNC_TASK = 0, SAFETY = 0}]]

if _G.NORMAL and _G.STEP then
    assert(false, "Should not have both NORMAL and STEP")
end

if not _G.NORMAL and not _G.STEP then
    assert(false, "Should have either NORMAL or STEP")
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

local ffi = require "ffi"
local math = require "math"
local debug = require "debug"
local class = require "pl.class"
local coroutine = require "coroutine"
local table_clear = require "table.clear"

local C = ffi.C
local f = string.format
local random = math.random
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
local PosedgeAlwaysHDL = 6
local Event = 12
local NOOP = 44
local EarlyExit = 11

ffi.cdef[[
    void verilua_time_callback(uint64_t time, int id);
    void verilua_posedge_callback(const char *path, int id);
    void verilua_posedge_callback_hdl(long long handle, int id);
    void verilua_negedge_callback(const char *path, int id);
    void verilua_negedge_callback_hdl(long long handle, int id);
    void verilua_edge_callback(const char *path, int id);
    void verilua_edge_callback_hdl(long long handle, int id);
    void verilua_posedge_callback_hdl_always(long long handle, int id);
    void verilua_negedge_callback_hdl_always(long long handle, int id);
]]

local type TaskID = integer
local type TaskCallbackType = integer
local type EventID = integer
local type CoroutineTaskBody = function()
local type FunctionTaskBody = function(): boolean | nil
local type CoroutineYieldInfo = {integer, string, integer}

local record EventHandle
    _scheduler: SchedulerClass
    name: string
    event_id: EventID
    wait: function(EventHandle)
    send: function(EventHandle)
end

local record SchedulerClass
    -- Class member variables
    task_count: integer
    task_function_map: {TaskID: FunctionTaskBody} -- only for `function` task
    task_yield_info_map: {TaskID: CoroutineYieldInfo} -- only for `function` task
    task_coroutine_map: {TaskID: thread} -- only for `coroutine` task
    task_name_map: {TaskID: string}
    task_fired_status_map: {TaskID: boolean}
    task_execution_count_map:  {TaskID: integer}
    pending_removal_tasks: {TaskID}

    event_task_id_list_map: {EventID: {TaskID}}
    event_name_map: {EventID: string}
    has_wakeup_event: boolean
    pending_wakeup_event: {EventID}

    acc_time_table: {string: number}

    -- Constructor
    _init: function(SchedulerClass)
    metamethod __call: function(SchedulerClass): SchedulerClass

    -- Private
    _is_coroutine_task: function(SchedulerClass, TaskID): boolean
    _alloc_coroutine_task_id: function(SchedulerClass): TaskID
    _alloc_function_task_id: function(SchedulerClass): TaskID
    _remove_task: function(SchedulerClass, TaskID)
    _register_callback: function(SchedulerClass, TaskID, TaskCallbackType, string, integer)

    -- Public
    check_task_exists: function(SchedulerClass, TaskID): boolean
    append_task: function(SchedulerClass, TaskID, string, CoroutineTaskBody, boolean): TaskID
    append_function_task: function(SchedulerClass, TaskID, string, FunctionTaskBody, CoroutineTaskBody, boolean): TaskID
    schedule_task: function(SchedulerClass, TaskID)
    schedule_tasks: function(SchedulerClass, TaskID)
    schedule_all_tasks: function(SchedulerClass)
    list_tasks: function(SchedulerClass)

    new_event_hdl: function(SchedulerClass, string, EventID): EventHandle
    get_event_hdl: function(SchedulerClass, string, EventID): EventHandle -- alias of `new_event_hdl`
    send_event: function(Scheduler, EventID)
end

local Scheduler: SchedulerClass = class()

-- TaskID from 0 to 99999 is reserved for coroutine task
local SCHEDULER_TASK_ID_MIN_COROUTINE = 0
local SCHEDULER_TASK_ID_MAX_COROUTINE = 99999

-- TaskID from 100000 to 199999 is reserved for function task
local SCHEDULER_TASK_ID_MIN_FUNCTION = 100000
local SCHEDULER_TASK_ID_MAX_FUNCTION = 199999

local SCHEDULER_TASK_MAX_COUNT = 100000
local SCHEDULER_MIN_EVENT_ID = 0
local SCHEDULER_MAX_EVENT_ID = 999

function Scheduler:_init()
    self.task_count = 0

    if _G.ENABLE_FUNC_TASK then
        self.task_function_map = {}
        self.task_yield_info_map = {}
    end

    self.task_coroutine_map = {}
    self.task_name_map = {}
    self.task_fired_status_map = {} -- Used to check if a task has been fired
    self.task_execution_count_map = {}
    self.pending_removal_tasks = {}

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
    return self.task_name_map[id] ~= nil
end

function Scheduler:_alloc_coroutine_task_id(): TaskID
    local id = random(SCHEDULER_TASK_ID_MIN_COROUTINE, SCHEDULER_TASK_ID_MAX_COROUTINE)
    while (self:check_task_exists(id)) do
        id = random(SCHEDULER_TASK_ID_MIN_COROUTINE, SCHEDULER_TASK_ID_MAX_COROUTINE)
    end
    return id
end

function Scheduler:_alloc_function_task_id(): TaskID
    local id = random(SCHEDULER_TASK_ID_MIN_FUNCTION, SCHEDULER_TASK_ID_MAX_FUNCTION)
    while (self:check_task_exists(id)) do
        id = random(SCHEDULER_TASK_ID_MIN_FUNCTION, SCHEDULER_TASK_ID_MAX_FUNCTION)
    end
    return id
end

function Scheduler:_remove_task(id: TaskID)
    self.task_count = self.task_count - 1
    table_insert(self.pending_removal_tasks, id)
end

function Scheduler:_register_callback(id: TaskID, cb_type: TaskCallbackType, str_value: string, integer_value: integer)
    if cb_type == PosedgeHDL then
        C.verilua_posedge_callback_hdl(integer_value, id)
    elseif cb_type == Posedge then
        C.verilua_posedge_callback(str_value, id)
    elseif cb_type == PosedgeAlwaysHDL then
        C.verilua_posedge_callback_hdl_always(integer_value, id)
    elseif cb_type == NegedgeHDL then
        C.verilua_negedge_callback_hdl(integer_value, id)
    elseif cb_type == Negedge then
        C.verilua_negedge_callback(str_value, id)
    elseif cb_type == Timer then
        C.verilua_time_callback(integer_value, id)
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
end

-- Used for creating a new coroutine task
function Scheduler:append_task(id: TaskID, name: string, task_body: CoroutineTaskBody, start_now: boolean): TaskID
    if _G.NORMAL then
        assert(self.task_count <= SCHEDULER_TASK_MAX_COUNT, "[Normal Scheduler] Too many tasks!")
    elseif _G.STEP then
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
            local task_name = self.task_name_map[id]
            assert(false, "[Scheduler] Task already exists! task_id: " .. id .. ", task_name: " .. task_name )
        end
    else
        task_id = self:_alloc_coroutine_task_id()
    end

    self.task_name_map[task_id] = name
    self.task_fired_status_map[task_id] = false
    self.task_coroutine_map[task_id] = coro_create(task_body as function)
    self.task_execution_count_map[task_id] = 0

    self.task_count = self.task_count + 1

    if _G.NORMAL and start_now then
        self.task_fired_status_map[task_id] = true
        self:schedule_task(task_id)
    end

    return task_id
end

if _G.ENABLE_FUNC_TASK then
    function Scheduler:append_function_task(id: TaskID, name: string, task_body: FunctionTaskBody, yield_task: CoroutineTaskBody, start_now: boolean): TaskID
        if _G.NORMAL then
            assert(self.task_count <= SCHEDULER_TASK_MAX_COUNT, "[Normal Scheduler] Too many tasks!")
        elseif _G.STEP then
            assert(self.task_count <= SCHEDULER_TASK_MAX_COUNT, "[Step Scheduler] Too many tasks!")
        end

        if _G.SAFETY then
            safety_assert(id is TaskID or id is nil, "[Scheduler] append_function_task: `Task ID` must be a number! but got " .. type(id) .. "!")
            safety_assert(name is string, "[Scheduler] append_function_task: `Task name` must be a string! but got " .. type(name) .. "!")
            safety_assert(task_body is FunctionTaskBody, "[Scheduler] append_function_task: `Task body` must be a function! but got " .. type(task_body) .. "!")
            safety_assert(yield_task is CoroutineTaskBody, "[Scheduler] append_function_task: `yield_task` must be a function! but got " .. type(yield_task) .. "!")
            safety_assert(start_now is boolean or start_now is nil, "[Scheduler] append_function_task: `start_now` must be a boolean! but got " .. type(start_now) .. "!")
        end

        local task_id: TaskID = id
        if id then
            if self:_is_coroutine_task(id) then
                assert(false, "[Scheduler] Invalid function task id!")
            end

            if self:check_task_exists(id) then
                local task_name = self.task_name_map[id]
                assert(false, "[Scheduler] Task already exists! task_id: " .. id .. ", task_name: " .. task_name )
            end
        else
            task_id = self:_alloc_function_task_id()
        end

        self.task_name_map[task_id] = name
        self.task_fired_status_map[task_id] = false
        self.task_function_map[task_id] = task_body
        self.task_execution_count_map[task_id] = 0

        local ok, yield_type, str_value, integer_value: boolean, integer, string, integer = coro_resume(coro_create(yield_task as function)) as (boolean, integer, string, integer)
        assert(ok, "[Scheduler] append_function_task: failed to resume `yield_task`: " .. name)

        self.task_yield_info_map[task_id] = {yield_type, str_value, integer_value}

        self.task_count = self.task_count + 1

        if _G.NORMAL and start_now then
            self.task_fired_status_map[task_id] = true
            self:schedule_task(task_id)
        end

        return task_id
    end
end

function Scheduler:schedule_task(id: TaskID)
    for _, remove_id in ipairs(self.pending_removal_tasks) do
        self.task_name_map[remove_id] = nil
        self.task_execution_count_map[remove_id] = 0
        self.task_fired_status_map[remove_id] = false

        if _G.SAFETY then
            if remove_id == id then
                assert(false, "remove_id == id")
            end
        end
    end
    table_clear(self.pending_removal_tasks)

    local task_cnt: integer = self.task_execution_count_map[id]
    self.task_execution_count_map[id] = task_cnt + 1

    local s, e: number, number
    if _G.ACC_TIME then
        s = os_clock()
    end

    local ok, cb_type_or_err, str_value, integer_value: boolean, TaskCallbackType, string, integer
    if _G.ENABLE_FUNC_TASK then
        if self:_is_coroutine_task(id) then
            ok, cb_type_or_err, str_value, integer_value = coro_resume(self.task_coroutine_map[id]) as (boolean, TaskCallbackType, string, integer)

            if not ok then
                print(f("[Scheduler] Error while executing task(id: %d, name: %s)\n\t%s", id, self.task_name_map[id], debug.traceback(self.task_coroutine_map[id] as string, cb_type_or_err)))
                
                _G.verilua_get_error = true
                assert(false)
            end
        else
            local delete_task = self.task_function_map[id]()
            
            if delete_task == true then
                cb_type_or_err = nil
            else
                local yield_info = self.task_yield_info_map[id]
                cb_type_or_err = yield_info[1]
                str_value = yield_info[2]
                integer_value = yield_info[3]
            end
        end
    else
        ok, cb_type_or_err, str_value, integer_value = coro_resume(self.task_coroutine_map[id]) as (boolean, TaskCallbackType, string, integer)

        if not ok then
            print(f("[Scheduler] Error while executing task(id: %d, name: %s)\n\t%s", id, self.task_name_map[id], debug.traceback(self.task_coroutine_map[id] as string, cb_type_or_err)))
            
            _G.verilua_get_error = true
            assert(false)
        end
    end

    if cb_type_or_err == nil or cb_type_or_err == EarlyExit then
        self:_remove_task(id)
    elseif _G.NORMAL then
        self:_register_callback(id, cb_type_or_err, str_value, integer_value)
    end

    if self.has_wakeup_event then
        self.has_wakeup_event = false
        for _, event_id in ipairs(self.pending_wakeup_event) do
            local wakeup_task_id_list = self.event_task_id_list_map[event_id]
            for _, wakeup_task_id in ipairs(wakeup_task_id_list) do
                self:schedule_task(wakeup_task_id)
            end
            table_clear(self.event_task_id_list_map[event_id])
        end
        table_clear(self.pending_wakeup_event)
    end

    if _G.ACC_TIME then
        e = os_clock()
        local name = self.task_name_map[id]
        local key = tostring(id) .. "_" .. name
        self.acc_time_table[key] = (self.acc_time_table[key] or 0) + (e - s)
    end
end

function Scheduler:schedule_tasks(id: TaskID)
    self:schedule_task(id)
end

function Scheduler:schedule_all_tasks()
    for id, _ in pairs(self.task_name_map) do
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

function Scheduler:list_tasks()
    print("[scheduler list tasks]:")
    print("-------------------------------------------------------------")
    if _G.ACC_TIME then
        local total_time: number = 0
        local max_key_str_len: integer = 0
        for key, time in pairs(self.acc_time_table) do
            total_time = total_time + time

            local len = #key
            if len > max_key_str_len then
                max_key_str_len = len
            end
        end

        local max_str_len: integer = 0
        local print_str_vec: {string} = {}
        for key, time in pairs(self.acc_time_table) do
            local s = f("[%" .. max_key_str_len .. "s]   %5.2f ms   percent: %5.2f%%", key, time * 1000, (time / total_time) * 100)
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
        for _, time in pairs(self.acc_time_table) do
            local str = print_str_vec[idx]
            str = str .. string.rep(" ", max_str_len - #str)

            print(f("%-" .. max_str_len .. "s ", str) .. get_progress_bar(time / total_time, 20))
            idx = idx + 1
        end
        
        print(f("total_time: %.2f s / %.2f ms", total_time, total_time * 1000))
        print("-------------------------------------------------------------")
    end

    local max_name_str_len: integer = 0
    for _, name in pairs(self.task_name_map) do
        local len = #name
        if len > max_name_str_len then
            max_name_str_len = len
        end
    end

    local idx = 0
    for id, name in pairs(self.task_name_map) do
        print(f("[%2d] name: %" .. max_name_str_len .. "s    id: %5d    cnt:%8d", idx, name, id, self.task_execution_count_map[id]))
        idx = idx + 1
    end
    print("-------------------------------------------------------------")
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
        while self.event_name_map[event_id] do
            event_id = random(SCHEDULER_MIN_EVENT_ID, SCHEDULER_MAX_EVENT_ID)
        end
    else
        assert(user_event_id is integer)
    end

    self.event_name_map[event_id] = name
    self.event_task_id_list_map[event_id] = {} -- task id comes from register_callback => (cb_type == Event)

    return {
        _scheduler = self,
        name = name,
        event_id = event_id,
        wait = function (this: EventHandle) coro_yield(Event, "", this.event_id) end,
        send = function (this: EventHandle) this._scheduler:send_event(this.event_id) end
    }
end

function Scheduler:get_event_hdl(name: string, user_event_id: EventID): EventHandle
    return self:new_event_hdl(name, user_event_id)
end

return Scheduler()
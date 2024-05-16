require("LuaSchedulerCommon")
require("LuaUtils")
local class = require "pl.class"
local coro_resume, coro_status = coroutine.resume, coroutine.status
local assert = assert

ffi.cdef[[
  void c_register_edge_callback(const char *path, int edge_type, int id);
  void c_register_read_write_synch_callback(int id);
  void c_register_time_callback(uint64_t time, int id);
  void c_register_clock_posedge_callback(int id, uint64_t count);
  void c_register_edge_callback_hdl(long long handle, int edge_type, int id);
  void c_register_edge_callback_hdl_always(long long handle, int edge_type, int id);
]]




--------------------------------
-- Scheduler
--------------------------------
local SchedulerTask = {}

function SchedulerTask:new(id, name, func, param)
    local obj = {}

    obj.id = id
    obj.name = name
    obj.func = func
    obj.param = param
    obj.fired = false
    obj.cnt = 0
    obj.time_taken = 0

    return obj
end

local CallbackInfo = {}

function CallbackInfo:new()
    local obj = {}

    obj.valid = false
    obj.types = 0
    obj.value = 0
    obj.signal = 0
    obj.signal_str = ""
    obj.signal_is_str = false
    obj.start_time = 0LL
    obj.is_posedge = false
    obj.is_negedge = false
    obj.is_clock_posedge = false
    obj.is_clock_negedge = false
    obj.is_timer = false
    obj.signal_value = 0LL

    return obj
end

local SchedulerClass = class()


function SchedulerClass:_init()
    self.id_max = 10000
    self.task_max = 50 -- Feel free to modified this value if the default value is not enough
    self.verbose = false
    self.task_table = {}
    self.callback_table = {}
    self.will_remove_tasks = {}

    verilua_info("[Scheduler]", "Using NORMAL scheduler")
end

function SchedulerClass:_log(...)
    if self.verbose then
        print("[Scheduler]", ...)

        -- local file, line, func = get_debug_info(3)
        -- print(("[%s:%s:%d]"):format(file, func, line), ...)
    end
end

function SchedulerClass:create_task_table(tasks) 
    for i = 1, #tasks do
        local id = i
        local task_name = tasks[i][1]
        local task_func = tasks[i][2]
        local task_param = tasks[i][3]
        task_param = task_param or {}
        if self:query_task_from_name(task_name) == nil then
            local _ = self.verbose and self:_log(string.format("create task_id:%d task_name:%s", id, task_name))
            table.insert(self.task_table, id, SchedulerTask:new(id, task_name, coroutine.create(task_func), task_param))
            table.insert(self.callback_table, id, CallbackInfo:new())
        end
    end
end

function SchedulerClass:remove_task(id) 
    table.insert(self.will_remove_tasks, id)
end

function SchedulerClass:alloc_task_id()
    for i = 1, self.id_max do
        local id = math.random(1, self.id_max)
        if self:query_task(id) == nil then return id end
    end
    assert(false, "not avaliable id!")
end

function SchedulerClass:append_task(id, name, task_func, param, schedule_task)
    assert(#self.task_table <= self.task_max, "Cannot append other tasks. task_max is " .. self.task_max)

    local task_id = id
    if id ~= nil then
        local t = self:query_task(id)
        assert(t == nil, "attempt to alloc an exist task id:" .. id .. " ==> exist task name:" .. (t and t.name or "Unknown"))
    else
        task_id = self:alloc_task_id()
    end

    local _ = self.verbose and self:_log(string.format("append task id:%d name:%s", task_id, name))
    table.insert(self.task_table, task_id, SchedulerTask:new(task_id, name, coroutine.create(task_func), param))
    table.insert(self.callback_table, task_id, CallbackInfo:new())
    -- TODO:
    -- if schedule_task or false then
    --     assert(false)
    --     self:schedule_tasks(task_id) -- start the task right away
    -- end

    return task_id
end

function SchedulerClass:query_task(id)
    return self.task_table[id]
end

function SchedulerClass:query_task_from_name(name)
    assert(type(name) == "string")

    for task_id, task in pairs(self.task_table) do
        local task_name = task.name
        if name == task_name then
            return task
        end
    end

    return nil
end

function SchedulerClass:schedule_all_tasks()
    -- for task_id, task in pairs(self.task_table) do
    --     self:schedule_tasks(task_id)
    -- end
    verilua_warning("[Scheduler] schedule_all_tasks will do nothing... (DOMINANT Mode)")
end

function SchedulerClass:list_tasks()
    print("--------------- Scheduler list task ---------------")
    if self.time_accumulate == true then
        local total_time = 0
        for task_id, task in pairs(self.task_table) do total_time = total_time + task.time_taken end
        for task_id, task in pairs(self.task_table) do
            local percent = task.time_taken * 100 / total_time
            print(("id: %5d\tcnt:%5d\tname: %.50s\ttime:%.2f\toverhead:%.2f"):format(task_id, task.cnt, task.name, task.time_taken, percent).."%")
        end
    else
        for task_id, task in pairs(self.task_table) do
            print(("id: %5d\tcnt:%5d\tname: %.50s"):format(task_id, task.cnt, task.name))
        end
    end
    print()
end

function SchedulerClass:register_callback(types, value, task_id, signal)
    assert(false, "Not used in DOMINANT scheduler")
end

function SchedulerClass:schedule_tasks(id)
    for i = 1, self.task_max do -- Better performance for LuaJIT
        local task_id = self.will_remove_tasks[i]
        if task_id ~= nil then
            if self.task_table[task_id] ~= nil then
                local _ = self.verbose and self:_log("remove task_id:" .. task_id .. " task_name:" .. self.task_table[task_id].name)
                self.task_table[task_id] = nil
            end
        end
    end
    self.will_remove_tasks = {}

    for task_id, task in pairs(self.task_table) do
        local task_name = task.name
        local task_func = task.func
        local task_param = task.param

        if id == task_id then
            task.cnt = task.cnt + 1
            local _ = self.verbose and self:_log("ENTER task_id:", task_id, "task_name:", task_name)

            local s = self.time_accumulate and os.clock()
            -- local types, value, signal = task_func(table.unpack(task_param))
            local ok, types, value, signal = coro_resume(task_func, table.unpack(task_param))
            if not ok then
                local err_msg = types
                print(debug.traceback(task_func, err_msg))
                assert(false)
            end
            
            local e = self.time_accumulate and os.clock()
            if self.time_accumulate == true then task.time_taken = task.time_taken + (e - s) end

            local _ = self.verbose and self:_log("LEAVE task_id:", task_id, "task_name:", task_name)
            -- if types == nil then
            if coro_status(task_func) == 'dead' then
                self:remove_task(id)
            else
                -- self:register_callback(types, value, task_id, signal)
            end
        end
    end
    -- TODO: Register Callback after all tasks is executed, this will reduce C function called cost.
    -- TODO: Merge tasks
end

function SchedulerClass:schedule_loop(id)

end

local scheduler = SchedulerClass()

return scheduler
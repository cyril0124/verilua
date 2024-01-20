require("LuaSchedulerCommon")
require("LuaUtils")
local class = require "pl.class"
local coro_resume, coro_status = coroutine.resume, coroutine.status


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
    setmetatable(obj, self)
    self.__index = self

    obj.id = id
    obj.name = name
    obj.func = func
    obj.param = param
    obj.fired = false
    obj.cnt = 0

    return obj
end


local SchedulerClass = class()


function SchedulerClass:_init()
    self.id_max = 10000
    self.task_max = 50 -- Feel free to modified this value if the default value is not enough
    self.verbose = false
    self.task_table = {}
    self.will_remove_tasks = {}
    self.cycles = 0

    verilua_info("[Scheduler]", "Using STEP scheduler")
end

function SchedulerClass:_log(...)
    if self.verbose then
        print("[Scheduler]", ...)
    end
end

function SchedulerClass:create_task_table(tasks) 
    for i = 1, #tasks do
        local id = i
        local task_name = tasks[i][1]
        local task_func = tasks[i][2]
        local task_param = tasks[i][3]
        task_param = task_param or {}
        local _ = self.verbose and self:_log(string.format("create task_id:%d task_name:%s", id, task_name))
        table.insert(self.task_table, id, SchedulerTask:new(id, task_name, coroutine.create(task_func), task_param))
    end
end

function SchedulerClass:remove_task(id) 
    -- self:list_tasks()
    -- assert(id ~= 1, "cannot remove main task! id:"..id)
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
    
    -- not support (STEP)
    -- if schedule_task or false then
    --     self:schedule_tasks(task_id) -- start the task right away
    -- end

    return task_id
end

function SchedulerClass:query_task(id)
    return self.task_table[id]
end

function SchedulerClass:schedule_all_tasks()
    for task_id, task in pairs(self.task_table) do
        self:schedule_tasks(task_id)
    end
    self.cycles = self.cycles + 1
end

function SchedulerClass:list_tasks()
    print("--------------- Scheduler list task ---------------")
    for task_id, task in pairs(self.task_table) do
        print(("id: %5d\tcnt:%5d\tname: %.50s"):format(task_id, task.cnt, task.name))
    end
    print("-----------------------------------------")
end

function SchedulerClass:register_callback(types, value, task_id, signal)
    assert(false, "Not used in STEP scheduler")
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
            local _ = self.verbose and self:_log("resume task_id:", task_id, "task_name:", task_name)

            -- local types, value, signal = task_func(table.unpack(task_param))
            local ok, types, value, signal = coro_resume(task_func, table.unpack(task_param))
            if not ok then
                local err_msg = types
                print(debug.traceback(task_func, err_msg))
                assert(false)
            end

            if coro_status(task_func) == 'dead' then
                self:remove_task(id)
            else
                -- self:register_callback(types, value, task_id, signal)
            end
            
            -- if types == nil then
            --     self:remove_task(id)
            -- end
        end
    end
end

local scheduler = SchedulerClass()

return scheduler
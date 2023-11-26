
local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
  void c_register_edge_callback(const char *path, int edge_type, int id);
  void c_register_read_write_synch_callback(int id);
  void c_register_time_callback(uint64_t time, int id);
  void c_register_clock_posedge_callback(int id, uint64_t count);
  void c_register_edge_callback_hdl(long long handle, int edge_type, int id);
  void c_register_edge_callback_hdl_always(long long handle, int edge_type, int id);
]]


SimCtrl = {
    STOP = 66,
    FINISH = 67,
    RESET = 68,
    SET_INTERATIVE_SCOPE = 69
}

--------------------------------
-- YieldEvent class
--------------------------------
local class = require("pl.class")
YieldEvent = class()
YieldType = {
    TIMER = 0,
    SIGNAL_EDGE = 1,
    SIGNAL_EDGE_HDL = 2,
    SIGNAL_EDGE_ALWAYS = 3,
    READ_WRITE_SYNCH = 4,
    CLOCK_POSEDGE = 5,
    CLOCK_POSEDGE_ALWAYS = 6,
    CLOCK_NEGEDGE = 7,
    CLOCK_NEGEDGE_ALWAYS = 8,
    NOOP = 44
}
EdgeType = { POSEDGE = 0, NEGEDGE = 1, EDGE = 2 }
function YieldEvent:_init(type, value, signal)
    -- Yield type:
    --     1) Timer:      0
    --     2) SignalEdge: 1
    self.type = type
    -- Yield value:
    --     1) for Timer type: value ==> delayed time
    --     2) for SignalEdge: 
    --          - Posedge:   0 
    --          - Negedge:   1
    --          - Both edge: 2
    self.value = value
    self.signal = signal -- signal path uesd by SignalEdge type
end

function YieldEvent:get_signal()
    return tostring(self.signal)
end


--------------------------------
-- Schedule events
--------------------------------
function await_time(time)
    coroutine.yield(YieldEvent(YieldType.TIMER, time))
end

function await_posedge(signal)
    coroutine.yield(YieldEvent(YieldType.SIGNAL_EDGE, EdgeType.POSEDGE, tostring(signal)))
end

function await_negedge(signal)
    coroutine.yield(YieldEvent(YieldType.SIGNAL_EDGE, EdgeType.NEGEDGE,  tostring(signal)))
end

function await_edge(signal)
    coroutine.yield(YieldEvent(YieldType.SIGNAL_EDGE, EdgeType.EDGE,  tostring(signal)))
end


function await_posedge_hdl(signal)
    coroutine.yield(YieldEvent(YieldType.SIGNAL_EDGE_HDL, EdgeType.POSEDGE, signal))
end

function await_negedge_hdl(signal)
    coroutine.yield(YieldEvent(YieldType.SIGNAL_EDGE_HDL, EdgeType.NEGEDGE,  signal))
end

function await_edge_hdl(signal)
    coroutine.yield(YieldEvent(YieldType.SIGNAL_EDGE_HDL, EdgeType.EDGE,  signal))
end

function await_read_write_synch()
    coroutine.yield(YieldEvent(YieldType.READ_WRITE_SYNCH, nil,  nil))
end


function register_always_await_posedge_hdl()
    local fired = false
    return function(signal)
        if not fired then
            fired = true
            coroutine.yield(YieldEvent(YieldType.SIGNAL_EDGE_ALWAYS, EdgeType.POSEDGE, signal))
        else
            coroutine.yield(YieldEvent(YieldType.NOOP, nil, nil))
        end
    end
end


--------------------------------
-- Scheduler
--------------------------------
local SchedulerTask = class()

function SchedulerTask:_init(id, name, func, param)
    self.id = id
    self.name = name
    self.func = func
    self.param = param
    self.fired = false
    self.cnt = 0
end


local SchedulerClass = class()


function SchedulerClass:_init()
    self.id_max = 10000
    self.task_max = 50 -- Feel free to modified this value if the default value is not enough
    self.verbose = false
    self.task_table = {}
    self.will_remove_tasks = {}
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
        self:_log(string.format("create task_id:%d task_name:%s", id, task_name))
        table.insert(self.task_table, id, SchedulerTask(id, task_name, coroutine.create(task_func), task_param))
    end
end

function SchedulerClass:remove_task(id) 
    assert(id ~= 1, "cannot remove main task!")
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

    self:_log(string.format("append task id:%d name:%s", task_id, name))
    table.insert(self.task_table, task_id, SchedulerTask(task_id, name, coroutine.create(task_func), param))
    if schedule_task or false then
        self:schedule_tasks(task_id) -- start the task right away
    end

    return task_id
end

function SchedulerClass:query_task(id)
    return self.task_table[id]
end

function SchedulerClass:schedule_all_tasks()
    for task_id, task in pairs(self.task_table) do
        self:schedule_tasks(task_id)
    end
end

function SchedulerClass:list_tasks()
    print("--------------- Scheduler list task ---------------")
    for task_id, task in pairs(self.task_table) do
        print(("id: %5d\tcnt:%5d\tname: %.50s"):format(task_id, task.cnt, task.name))
    end
    print("-----------------------------------------")
end

function SchedulerClass:schedule_tasks(id)
    -- for i = 1, #self.will_remove_tasks do
    for i = 1, self.task_max do -- Better performance for LuaJIT
        local task_id = self.will_remove_tasks[i]
        if task_id ~= nil then
            if self.task_table[task_id] ~= nil then
                self:_log("remove task_id:" .. task_id .. " task_name:" .. self.task_table[task_id].name)
                self.task_table[task_id] = nil
            end
        end
    end
    self.will_remove_tasks = {}

    local coro_resume = coroutine.resume
    local coro_status = coroutine.status
    for task_id, task in pairs(self.task_table) do
        local task_name = task.name
        local task_coro = task.func
        local task_param = task.param

        if id == task_id then
            task.cnt = task.cnt + 1
            self:_log("resume task_id:", task_id, "task_name:", task_name)

            local ok, yield_event = coro_resume(task_coro, table.unpack(task_param))
            if not ok then
                err_msg = yield_event -- if there is an error, yield_event is act as error message
                print(debug.traceback(task_coro, err_msg))
                assert(false)
                return -- Task finish
            end

            if coro_status(task_coro) ~= 'dead' then
                -------------------------
                -- timer callback
                -------------------------
                if yield_event.type == YieldType.TIMER then
                    -- vpi.register_time_callback(yield_event.value, 0, task_id) -- TODO: high time
                    -- C.c_register_time_callback(yield_event.value, 0, task_id)
                    C.c_register_time_callback(yield_event.value, task_id)

                -------------------------
                -- edge callback
                -------------------------
                elseif yield_event.type == YieldType.SIGNAL_EDGE then
                    -- vpi.register_edge_callback(yield_event.signal, yield_event.value, task_id)
                    C.c_register_edge_callback(yield_event.signal, yield_event.value, task_id)

                -------------------------
                -- edge callback hdl
                -------------------------
                elseif yield_event.type == YieldType.SIGNAL_EDGE_HDL then
                    -- vpi.register_edge_callback_hdl(yield_event.signal, yield_event.value, task_id)
                    -- ffi.C.register_edge_callback_hdl(yield_event.signal, yield_event.value, task_id)
                   C.c_register_edge_callback_hdl(yield_event.signal, yield_event.value, task_id)
                
                -------------------------
                -- edge callback hdl always
                -------------------------
                elseif yield_event.type == YieldType.SIGNAL_EDGE_ALWAYS then
                    -- vpi.register_edge_callback_hdl_always(yield_event.signal, yield_event.value, task_id)
                    -- ffi.C.register_edge_callback_hdl_always(yield_event.signal, yield_event.value, task_id)
                   C.c_register_edge_callback_hdl_always(yield_event.signal, yield_event.value, task_id)
                
                -------------------------
                -- read write synch callback
                -------------------------
                elseif yield_event.type == YieldType.READ_WRITE_SYNCH then
                    -- vpi.register_read_write_synch_callback(task_id)
                    C.c_register_read_write_synch_callback(task_id)

                -------------------------
                -- noop
                -------------------------
                elseif yield_event.type == YieldType.NOOP then
                    -- do nothing
                
                -------------------------
                -- others
                -------------------------
                else
                    assert(false, "Unknown yield_event! type:" .. yield_event.type .. " value:" .. yield_event.value)
                end
            else
                self:remove_task(id)
            end
        end
    end
end

scheduler = SchedulerClass()

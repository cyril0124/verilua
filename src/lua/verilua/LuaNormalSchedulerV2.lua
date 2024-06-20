local debug = require "debug"
local ffi = require "ffi"
local class = require "pl.class"
local C = ffi.C

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

local assert = assert
local pairs = pairs
local print = print
local random = math.random
local tinsert = table.insert
local tostring = tostring
local ipairs = ipairs
local type = type
local verilua_info = verilua_info
local coro_resume, coro_status, coro_create, coro_yield = coroutine.resume, coroutine.status, coroutine.create, coroutine.yield


local scommon = require("LuaSchedulerCommonV2")
local YieldType = scommon.YieldType

local Scheduler = class()

local TASK_MAX = 100

function Scheduler:_init()
    self.id_max = 10000
    self.verbose = false

    self.task_count  = 0
    self.id_task_tbl = {} -- {<key: task_id, value: coro>, ...}
    self.id_name_tbl = {} -- {<key: task_id, value: str>, ...}
    self.id_fired_tbl = {} -- {<key: task_id, vaue: boolean>, ...}
    self.id_cnt_tbl = {} -- {<key: task_id, value: cnt>, ...}
    self.will_remove_tasks = {} -- {<task_id>, ...}

    self.event_tbl = {} -- {<key: event, {<task_id>, ...}>, ...}
    self.event_name_tbl = {} -- {<key: event_id, value: str>, ...}
    self.has_wakeup_event = false
    self.will_wakeup_event = {} -- {<task_id>, ...}

    verilua_info("[Scheduler]", "Using NORMAL scheduler")

    self.create_task_table = function (this, tasks)
        -- 
        -- tasks = {
        --   {name, func},
        --   ...
        -- }
        -- 
        assert(type(tasks) == "table")
        for index, task in ipairs(tasks) do
            assert(type(task) == "table")
            -- assert(#task == 2)
            assert(type(task[1]) == "string")
            assert(type(task[2]) == "function")
            
            -- check duplicate tasks
            for i, name in pairs(this.id_name_tbl) do
                if name == task[1] then
                    goto skip
                end
            end

            print("[NormalScheduler] create_task_table =>", task[1])
            
            local id = index + #this.id_task_tbl
            local name = task[1]
            local func = task[2]
            assert(this.id_task_tbl[id] == nil)
            this.id_task_tbl[id] = coro_create(func)

            assert(this.id_name_tbl[id] == nil)
            this.id_name_tbl[id] = name

            assert(this.id_cnt_tbl[id] == nil)
            this.id_cnt_tbl[id] = 0

            assert(this.id_fired_tbl[id] == nil)
            this.id_fired_tbl[id] = false

            ::skip::
        end

        this.task_count = #tasks
    end

    self.remove_task = function (this, id)
        this.task_count = this.task_count - 1
        tinsert(this.will_remove_tasks, id)
    end

    self.query_task = function (this, id)
        return this.id_task_tbl[id]
    end

    self.alloc_task_id = function (this)
        for i = 1, this.id_max do
            local id = random(1, this.id_max)
            if this.id_task_tbl[id] == nil then
                return id
            end
        end

        assert(false, "not avaliable id!")
    end

    self.append_task = function (this, id, name, func, param, schedule_task)
        assert(this.task_count <= TASK_MAX)

        local task_id = id
        if id ~= nil then
            local t = this.id_task_tbl[task_id]
            if t ~= nil then
                local task_name = this.id_name_tbl[task_id]
                assert(false, "attempt to alloc an exist task id:" .. task_id .. " ==> exist task name:" .. task_name)
            end
        else
            task_id = self:alloc_task_id()
        end
    
        tinsert(self.id_task_tbl, task_id, coro_create(func))
        tinsert(self.id_name_tbl, task_id, name)
        tinsert(self.id_cnt_tbl, task_id, 0)
        tinsert(self.id_fired_tbl, task_id, false)
        this.task_count = this.task_count + 1

        if schedule_task or false then
            this.id_fired_tbl[task_id] = true
            self:schedule_tasks(task_id)
        end

        return task_id
    end

    local PosedgeHDL = YieldType.PosedgeHDL
    local Posedge = YieldType.Posedge
    local PosedgeAlwaysHDL = YieldType.PosedgeAlwaysHDL
    local NegedgeHDL = YieldType.NegedgeHDL
    local Negedge = YieldType.Negedge
    local Timer = YieldType.Timer
    local Event = YieldType.Event
    local NOOP = YieldType.NOOP
    local EarlyExit = YieldType.EarlyExit
    self.register_callback = function (this, task_id, types, str_value, integer_value)
        if types == PosedgeHDL then
            C.verilua_posedge_callback_hdl(integer_value, task_id)
        elseif types == Posedge then
            C.verilua_posedge_callback(str_value, task_id)
        elseif types == PosedgeAlwaysHDL then
            C.verilua_posedge_callback_hdl_always(integer_value, task_id)
        elseif types == NegedgeHDL then
            C.verilua_negedge_callback_hdl(integer_value, task_id)
        elseif types == Negedge then
            C.verilua_negedge_callback(str_value, task_id)
        elseif types == Timer then
            C.verilua_time_callback(integer_value, task_id)
        elseif types == Event then
            if this.event_name_tbl[integer_value] == nil then
                assert(false, "Unknown event => " .. integer_value)
            end
            tinsert(this.event_tbl[integer_value], task_id)
        elseif types == NOOP then
            -- do nothing
        else
            assert(false, "Unknown YieldType => " .. tostring(types))
        end
    end

    self.schedule_tasks = function (this, id)
        for _, remove_id in ipairs(this.will_remove_tasks) do
            this.id_task_tbl[remove_id] = nil
            this.id_name_tbl[remove_id] = nil
            this.id_cnt_tbl[remove_id] = nil
            this.id_fired_tbl[remove_id] = nil
        end
        this.will_remove_tasks = {}

        local task_cnt = this.id_cnt_tbl[id]
        this.id_cnt_tbl[id] = task_cnt + 1
        local func = this.id_task_tbl[id]
        local ok, types_or_err, str_value, integer_value = coro_resume(func)
        if not ok then
            local err_msg = types_or_err
            print("task_id: " .. id, debug.traceback(func, err_msg))
            assert(false)
        end

        -- if coro_status(func) == "dead" or types_or_err == EarlyExit then
        if types_or_err == nil or types_or_err == EarlyExit then
            this:remove_task(id)
        else
            this:register_callback(id, types_or_err, str_value, integer_value)
        end

        -- We should not wakeup even if task_cnt is 0, otherwise there will be assert false on resuming a running task
        if this.has_wakeup_event and task_cnt ~= 0 then
            for _, evnet_id in ipairs(this.will_wakeup_event) do
                local wakeup_list = this.event_tbl[evnet_id]
                for _, _id in ipairs(wakeup_list) do
                    this.id_cnt_tbl[_id] = this.id_cnt_tbl[_id] + 1
                    local _func = this.id_task_tbl[_id]
                    local _ok, _types_or_err, _str_value, _integer_value = coro_resume(_func)
                    if not _ok then
                        local _err_msg = _types_or_err
                        print("task_id: " .. _id, debug.traceback(_func, _err_msg))
                        assert(false)
                    end
            
                    -- if coro_status(func) == "dead" or types_or_err == EarlyExit then
                    if _types_or_err == nil or _types_or_err == EarlyExit then
                        this:remove_task(_id)
                    else
                        this:register_callback(_id, _types_or_err, _str_value, _integer_value)
                    end
                end
                this.event_tbl[evnet_id] = {}
            end
            this.will_wakeup_event = {}
            this.has_wakeup_event = false
        end
    end

    self.schedule_all_tasks = function (this)
        for id, _ in pairs(this.id_name_tbl) do
            local fired = this.id_fired_tbl[id]
            assert(fired ~= nil)
            if fired == false then
                fired = true
                this:schedule_tasks(id)
            end
        end
    end

    self.list_tasks = function (this)
        print("[scheduler list tasks]:")
        print("-------------------------------------------------------------")
        -- if self.time_accumulate == true then
        -- TODO:
        --     local total_time = 0
        --     for task_id, task in pairs(self.task_table) do total_time = total_time + task.time_taken end
        --     for task_id, task in pairs(self.task_table) do
        --         local percent = task.time_taken * 100 / total_time
        --         print(("id: %5d\tcnt:%5d\tname: %.50s\ttime:%.2f\toverhead:%.2f"):format(task_id, task.cnt, task.name, task.time_taken, percent).."%")
        --     end
        -- else
            local index = 0
            for id, name in pairs(this.id_name_tbl) do
                print(("|[%2d]\tid: %5d\tcnt:%5d\tname: %15s|"):format(index, id, this.id_cnt_tbl[id], name))
                index = index + 1
            end
        -- end
        print("-------------------------------------------------------------")
    end

    self.send_event = function (this, event_id_integer)
        tinsert(this.will_wakeup_event, event_id_integer)
        this.has_wakeup_event = true
    end

    -- 
    -- Example:
    --      local scheduler = require "LuaScheduler"
    --      scheduler:register_event("test event 1", 123)
    --      scheduler:register_event("test event 2", 455)
    -- 
    --      scheduler:register_evnet {
    --          test_1 = 1,
    --          test_2 = 2,
    --          test_3 = 3,
    --      }
    --      
    -- 
    --      In your tasks:
    --          --
    --          -- <task_2> wakeup <task_1> && <task_3>
    --          --
    --          verilua "appendTasks" {
    --              task_1 = function ()
    --                  await_event(1)
    --                  assert(dut.cycles() == 100)
    --              end,
    -- 
    --              task_2 = function ()
    --                  dut.clock:posedge(100)
    --                  send_event(1)
    --              end,
    -- 
    --              task_3 = function ()
    --                  await_event(1)
    --                  assert(dut.cycles() == 100)
    --              end,
    --          }    
    -- 
    -- 
    self.register_event = function (this, name_or_tbl, event_id_integer)
        local t = type(name_or_tbl)
        if t == "string" then
            local name = name_or_tbl
            assert(type(name) == "string")
            assert(event_id_integer ~= nil)
            assert(type(event_id_integer) == "number")

            this.event_tbl[event_id_integer] = {}
            this.event_name_tbl[event_id_integer] = name

            print(string.format("[NormalScheduler/register_event] name => %s  event_id => %d", name, event_id_integer))
        elseif t == "table" then
            local name_event_tbl = name_or_tbl
            assert(event_id_integer == nil)
            for name, event_id in pairs(name_event_tbl) do
                assert(type(name) == "string")
                assert(event_id ~= nil)
                assert(type(event_id) == "number")

                this.event_tbl[event_id] = {}
                this.event_name_tbl[event_id] = name
                print(string.format("[NormalScheduler/register_event] name => %s  event_id => %d", name, event_id))
            end
        end
    end

    -- 
    -- Example:
    --      local scheduler = require "LuaScheduler"
    --      local test_ehdl = scheduler:get_event_hdl("test_1") -- event id will be randomly allocated
    --      test_ehdl:wait()
    --      test_ehdl:send()
    --      
    --      local test_ehdl = scheduler:get_event_hdl("test_1", 1) -- manually set event_id
    --      
    --      local test_ehdl = scheduler:get_event_hdl "test_1"
    -- 
    -- 
    self.get_event_hdl = function (this, name, event_id_integer)
        assert(type(name) == "string")

        local event_id = event_id_integer
        if event_id_integer == nil then
            event_id = random(1, 1000)
            repeat
                event_id = random(1, 1000)
            until this.event_name_tbl[event_id] == nil

            this.event_tbl[event_id] = {}
            this.event_name_tbl[event_id] = name
        else
            assert(event_id_integer ~= nil)
            assert(type(event_id_integer) == "number")
            
            this.event_tbl[event_id_integer] = {}
            this.event_name_tbl[event_id_integer] = name
        end

        return {
            scheduler = this,

            name = name,
            event_id = event_id,

            wait = function (t)
                coro_yield(Event, "", t.event_id)
            end,

            send = function (t)
                t.scheduler:send_event(t.event_id)
            end
        }
    end
end


local scheduler = Scheduler()

_G.send_event = function (event_id_integer)
    scheduler:send_event(event_id_integer)
end

return scheduler
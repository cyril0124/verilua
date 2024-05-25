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
local ipairs = ipairs
local type = type
local verilua_info = verilua_info
local coro_resume, coro_status, coro_create = coroutine.resume, coroutine.status, coroutine.create


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
    self.id_cnt_tbl = {} -- {<key: task_id, value: cnt>, ...}
    self.will_remove_tasks = {} -- {<task_id>, ...}

    verilua_info("[Scheduler]", "Using STEP scheduler")

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

        -- not support (STEP)
        -- if schedule_task or false then
        --     self:schedule_tasks(task_id)
        -- end

        return task_id
    end

    local EarlyExit = YieldType.EarlyExit

    self.schedule_tasks = function (this, id)
        for _, remove_id in ipairs(this.will_remove_tasks) do
            this.id_task_tbl[remove_id] = nil
            this.id_name_tbl[remove_id] = nil
            this.id_cnt_tbl[remove_id] = nil
        end
        this.will_remove_tasks = {}

        this.id_cnt_tbl[id] = this.id_cnt_tbl[id] + 1
        local func = this.id_task_tbl[id]
        local ok, types_or_err, str_value, integer_value = coro_resume(func)
        if not ok then
            local err_msg = types_or_err
            print(debug.traceback(func, err_msg))
            assert(false)
        end

        -- if coro_status(func) == "dead" or types_or_err == EarlyExit then
        if types_or_err == nil or types_or_err == EarlyExit then
            this:remove_task(id)
        else
            -- this.register_callback(id, types_or_err, str_value, integer_value)
        end
    end

    self.schedule_all_tasks = function (this)
        for id, _ in pairs(this.id_name_tbl) do
            this:schedule_tasks(id)
        end
    end

    self.list_tasks = function (this)
        print("--------------- Scheduler list task ---------------")
        -- if self.time_accumulate == true then
        -- TODO:
        --     local total_time = 0
        --     for task_id, task in pairs(self.task_table) do total_time = total_time + task.time_taken end
        --     for task_id, task in pairs(self.task_table) do
        --         local percent = task.time_taken * 100 / total_time
        --         print(("id: %5d\tcnt:%5d\tname: %.50s\ttime:%.2f\toverhead:%.2f"):format(task_id, task.cnt, task.name, task.time_taken, percent).."%")
        --     end
        -- else
            for id, name  in pairs(this.id_name_tbl) do
                print(("id: %5d\tcnt:%5d\tname: %.50s"):format(id, this.id_cnt_tbl[id], name))
            end
        -- end
        print()
    end
end


local scheduler = Scheduler()

return scheduler
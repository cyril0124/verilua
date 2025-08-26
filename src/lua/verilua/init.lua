-- jit.opt.start(3)
-- jit.opt.start("loopunroll=100", "minstitch=0", "hotloop=1", "tryside=100")

local io = require "io"
local os = require "os"
local debug = require "debug"
local string = require "string"
local math = require "math"

local type = type
local print = print
local table = table
local pairs = pairs
local ipairs = ipairs
local assert = assert
local f = string.format
local tonumber = tonumber
local tostring = tostring
local math_random = math.random
local getmetatable = getmetatable

-- Strict mode, all global variables must be declared first
require "strict"

_G.inspect = require "inspect"

--- Print any lua object using `inspect.lua`
---@param ... any
_G.dbg     = function (...) print(inspect(...)) end
_G.pp      = _G.dbg -- Alias for dbg
_G.dump    = _G.pp -- Alias for dbg
_G.printf  = function (s, ...) io.write(f(s, ...)) end

-- Convert to hex for pretty printing
local convert_to_hex = function(item, path)
    if path[#path] ~= inspect.KEY and (type(item) == "number" or ffi.istype("uint64_t", item)) then
        return bit.tohex(item)
    end
    return item
end

--- Print any lua object using `inspect.lua` with hex conversion on `number` and `uint64_t`
---@param ... any
_G.pph = function (...)
    print(inspect(..., {process = convert_to_hex}))
end

-- 
-- #define vpiBinStrVal          1
-- #define vpiOctStrVal          2
-- #define vpiDecStrVal          3
-- #define vpiHexStrVal          4
-- 
_G.BinStr = 1
_G.OctStr = 2
_G.DecStr = 3
_G.HexStr = 4

do
    local PWD = os.getenv("PWD")
    local PRJ_TOP = os.getenv("PRJ_TOP")

    local function append_package_path(path)
        _G.package.path = _G.package.path .. ";" .. path
    end

    if PWD ~= nil then
        append_package_path(PWD .. "/?.lua")
        append_package_path(PWD .. "/src/?.lua")
        append_package_path(PWD .. "/src/lua/?.lua")
    end

    if PRJ_TOP ~= nil then
        append_package_path(PRJ_TOP .. "/?.lua")
        append_package_path(PRJ_TOP .. "/src/?.lua")
        append_package_path(PRJ_TOP .. "/src/lua/?.lua")
    end
end

-- 
-- debug info
-- 
_G.get_debug_info = function (level)
    local info = debug.getinfo(level or 2, "nSl") -- Level 2 because we're inside a function
    
    local file = info.short_src -- info.source
    local line = info.currentline
    local func = info.name or "<anonymous>"

    return file, line, func
end

_G.default_debug_level = 4
_G.debug_level = _G.default_debug_level
_G.debug_str = function(...)
    local file, line, func = _G.get_debug_info(_G.debug_level)
    local args = {...}
    local message = table.concat(args, "\t")
    return (("[%s:%s:%d]"):format(file, func, line) .. "\t" .. message)
end

---@class verilua.AnsiColors
---@field reset string
---@field black string
---@field red string
---@field green string
---@field yellow string
---@field blue string
---@field magenta string
---@field cyan string
---@field white string
_G.colors = {
    reset   = "\27[0m",
    black   = "\27[30m",
    red     = "\27[31m",
    green   = "\27[32m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    magenta = "\27[35m",
    cyan    = "\27[36m",
    white   = "\27[37m"
}

-- 
-- global debug log functions
-- 
local enable_verilua_debug = os.getenv("VL_DEBUG") == "1"
_G.enable_verilua_debug = enable_verilua_debug

if enable_verilua_debug == true then
    _G.verilua_debug = function (...)
        io.write("\27[31m") -- RED
        print(_G.debug_str(">> [VERILUA DEBUG]", ...), "\27[0m")
        io.flush()
    end
else
    _G.verilua_debug = function (...)
    end
end

_G.verilua_info = function (...)
    io.write("\27[36m") -- CYAN
    print(">> [VERILUA INFO]", ..., "\27[0m")
end

_G.verilua_warning = function (...)
    io.write("\27[33m") -- YELLOW
    print(">> [VERILUA WARNING]", ..., "\27[0m")
    io.flush()
end

_G.verilua_error = function (...)
    local error_print = function(...)
        io.write("\27[31m") -- RED
        print(">> [VERILUA ERROR]", ..., "\27[0m")
        io.flush()
    end
    assert(false, error_print(...))
end

_G.verilua_assert = function (cond, ...)
    if cond == nil or cond == false then
        _G.verilua_error(...)
    end
end

--- Load user configuration file
--- Verilua will read the environment variable `VERILUA_CFG` and ``VERILUA_CFG_PATH`` to load user configuration file.
--- If `VERILUA_CFG_PATH` is not set, Verilua will search the directory name of the configuration file(`VERILUA_CFG`).
--- So the user can set `VERILUA_CFG` to an absolute path of the configuration file, or set `VERILUA_CFG` to the file name and
--- set `VERILUA_CFG_PATH` to the directory name of the configuration file.
--- e.g.
--- ```shell
---   export VERILUA_CFG=mysim_config.lua
---   export VERILUA_CFG_PATH=../simulator
---   # or
---   export VERILUA_CFG=/home/user/simulator/mysim_config.lua
--- ```
--- If `VERILUA_CFG` is not set, Verilua will not load any user configuration file.
_G.cfg = require "LuaSimConfig"

local cfg_name, cfg_path
do
    local path = require "pl.path"
    local stringx = require "pl.stringx"

    cfg_name, cfg_path = cfg:get_user_cfg()
    
    if cfg_name then
        if cfg_path == nil then
            cfg_path = path.abspath(path.dirname(cfg_name)) -- get abs path name
        end
        
        assert(type(cfg_path) == "string")

        if string.len(cfg_path) ~= 0 then
            _G.package.path = _G.package.path .. ";" .. cfg_path .. "/?.lua" 
        end

        cfg_name = path.basename(cfg_name) -- strip basename

        if stringx.endswith(cfg_name, ".lua") then
            cfg_name = stringx.rstrip(cfg_name, ".lua") -- strip ".lua" suffix
        end

        local _cfg = require(cfg_name)
        assert(type(_cfg) == "table", f("`cfg` is not a `table`, maybe there is package conflict. cfg_name:%s cfg_path:%s", cfg_name, cfg_path))

        cfg:merge_config(_cfg)
    end
    cfg:post_config()
end

--- Set by the scheduler when there is an error while executing a task
--- e.g.
--- ```lua
---     fork {
---         function()
---             -- ...
---             assert(false, "Error occurred")
---             -- ...
---         end
---     }
--- 
---     final {
---         function(got_error)
---             assert(got_error == true)
---         end
---     }
--- ```
_G.VERILUA_GOT_ERROR = false --[[@as boolean]]

-- 
-- add source_file/dependencies package path
-- 
do
    for _, src in ipairs(cfg.srcs) do
        _G.package.path = _G.package.path .. ";" .. src
    end

    for _, dep in pairs(cfg.deps) do
        _G.package.path = package.path .. ";" .. dep
    end
end

-- 
-- we should load ffi setenv before setting up other environment variables
-- 
_G.ffi = require "ffi"
ffi.cdef[[
    int setenv(const char *name, const char *value, int overwrite);
]]

do
    ffi.cdef[[
        typedef struct timespec {
            long sec;
            long nsec;
        } timespec;
        int clock_gettime(int clk_id, struct timespec *tp);
    ]]

    -- High performance implementation of `os.clock()` using LuaJIT FFI
    local CLOCK_MONOTONIC = 1
    local t = ffi.new("timespec[1]")
    local C = ffi.C
    ---@diagnostic disable-next-line: inject-field
    os._clock = os.clock
    os.clock = function()
        C.clock_gettime(CLOCK_MONOTONIC, t)
        ---@diagnostic disable-next-line: need-check-nil, undefined-field
        return tonumber(t[0].sec) + tonumber(t[0].nsec) * 1e-9
    end
end

if cfg.simulator == "vcs" then
    ffi.cdef[[
        void *svGetScopeFromName(const char *str);
        void svSetScope(void *scope);
    ]]
end

-- 
-- setup breakpoint
-- 
_G.bp = function() print("[Breakpoint] Invalid breakpoint!") end
if os.getenv("VL_DEBUGGER") == "1" then
    _G.verilua_debug("VL_DEBUGGER is 1")
    _G.bp = function() 
        require("LuaPanda").start("localhost", 8818)
        ---@diagnostic disable-next-line: undefined-global
        local ret = LuaPanda and LuaPanda.BP and LuaPanda.BP()
    end
end

--
-- Setup some environment variables
-- 
do
    local function setenv_from_lua(name, value)
        assert(type(name) == "string")
        assert(value ~= nil)
        local ret = ffi.C.setenv(name, tostring(value), 1)
        if ret == 0 then
            _G.verilua_debug("Environment variable <%s> set successfully.", name)
        else
            _G.verilua_debug("Failed to set environment variable <%s>.", name)
        end
    end

    -- 
    -- setup LUA_SCRIPT inside init.lua, this can be overwrite by outer environment variable
    -- 
    local LUA_SCRIPT = cfg.script
    if LUA_SCRIPT ~= nil then
        setenv_from_lua("LUA_SCRIPT", LUA_SCRIPT)
    end

    -- 
    -- setup DUT_TOP inside init.lua, this can be overwrite by outer environment variable
    -- 
    local DUT_TOP = cfg.top
    if DUT_TOP ~= nil then
        setenv_from_lua("DUT_TOP", DUT_TOP)
    end

    setenv_from_lua("LUA_PATH", _G.package.path)

    ---@class oslib
    ---@field setenv fun(name: string, value: string|number)

    os.setenv = setenv_from_lua
end

-- 
-- Setup scheduler mode
-- 
_G.verilua_debug("SchedulerMode is " .. cfg.mode)

-- 
-- import scheduler functions
-- 
local scommon = require "verilua.scheduler.LuaSchedulerCommonV2"
for key, value in pairs(scommon) do
    _G[key] = value
end

-- Extend some Lua standard libraries
require "verilua.ext.tablex"
require "verilua.ext.stringx"

-- 
-- try-catch-finally(https://xmake.io/#/manual/builtin_modules?id=try-catch-finally)
-- Has the same functionality as the try-catch-finally in xmake
-- 
do
    local table_join = table.join
    local table_pack = table.pack
    local table_unpack = table.unpack
    local debug_traceback = debug.traceback
    local xpcall = xpcall

    ---@type fun(block: function[]): table<function>
    _G.catch = function (block)
        return {catch = block[1]}
    end

    ---@type fun(block: function[]): table<function>
    _G.finally = function (block)
        return {finally = block[1]}
    end

    --- Example:
    --- ```lua
    ---     try
    ---     {
    ---         -- try code block
    ---         function ()
    ---             error("error message")
    ---         end,
    ---
    ---         -- catch code block
    ---         catch
    ---         {
    ---             -- After an exception occurs, it is executed
    ---             function (errors)
    ---                 print(errors)
    ---             end
    ---         },
    ---
    ---         -- finally block
    ---         finally
    ---         {
    ---             -- Finally will be executed here
    ---             function (ok, errors)
    ---                 -- If there is an exception in try{}, ok is true, errors is the error message, otherwise it is false, and error is the return value in try
    ---             end
    ---         }
    ---     }
    --- ```
    ---@type fun(block: function[]): ...
    _G.try = function (block)

        -- get the try function
        local try = block[1]
        assert(try)

        -- get catch and finally functions
        local funcs = table_join(block[2] or {}, block[3] or {})

        -- try to call it
        local results = table_pack(xpcall(try, function (errors) return "[try-catch-finally] " .. debug_traceback(errors) end))
        local ok = results[1]
        if not ok then
            -- run the catch function
            if funcs and funcs.catch then
                funcs.catch(results[2])
            end
        end

        -- run the finally function
        if funcs and funcs.finally then
            funcs.finally(ok, table_unpack(results, 2, results.n))
        end

        if ok then
            return table_unpack(results, 2, results.n)
        end
    end
end

-- TODO: Optimize this
do
    local CoverGroup = require "verilua.coverage.CoverGroup"
    local CoverPoint = require "verilua.coverage.CoverPoint"
    local AccurateCoverPoint = require "verilua.coverage.AccurateCoverPoint"

    -- The verilua holds a default coverage group. 
    -- User can create a coverage point without manually creating a new coverage group for convenience.
    local default_cg = CoverGroup("default")
    _G.default_cg = default_cg

    -- 
    -- Example:
    --      Basic usage:
    --          (1) Create coverage handle
    --              local c1 = ("name of cover point"):cvhdl()     -- This cover point belongs to the `default_cg` if no extra parameters are provided.
    --          (2) Accumulate cover point value by <cvhdl>:inc()
    --              c1:inc()
    --          (3) Report current coverage status by <coverage group>:report()
    --              default_cg:report()
    --          (4) Reset cover point by <cvhdl>:reset()
    --              c1:reset()
    --          (5) Save coverage report into a `json` file
    --              default_cg:save()  -- The `default_cg` will be automatically saved if there are coverage points registered by the user.
    --                                 -- User does not required to manually call this function to save the `default_cg` into `json` file.
    --                                 -- For the user defined coverage groups, user should save it in some place and those coverage groups
    --                                 -- are not controlled by the verilua kernel.
    -- 
    --      Use user defined coverage group:
    --          local CoverGroup = require "coverage.CoverGroup"
    --          local user_defined_cg = CoverGroup("user_defined")
    --          local c2 = ("some cover point"):cvhdl { group = user_defined_cg }
    --          c2:inc()
    --          user_defined_cg:report()
    --          user_defined_cg:save()
    -- 
    --      Accurate cover point(The accurate cover point will save the cycle time when cover point accumulate the internel counter):
    --          local accurate_cp = ("some accurate cover point"):cvhdl { type = "accurate" }
    --          accurate_cp:inc_with_cyclce(<cycle value>)    -- Use inc_with_cycle() instead of inc() for the accurate cover point
    -- 
    getmetatable('').__index.cvhdl = function(name, params_table)
        local cover_group = default_cg
        local cover_point_type = "simple"

        if params_table then
            local params_table_type = type(params_table)
            assert(params_table_type == "table")

            for key, value in pairs(params_table) do
                -- User defined CoverGroup
                if key == "group" then
                    local value_type = type(value)
                    if value_type ~= "table" then
                        assert(false, "[cvhdl] invalid `group` type! you should provide a valid CoverGroup. invalid_type => " .. value_type)
                    else
                        assert(value.__type == "CoverGroup", "[cvhdl] the provided `group` did not contains `type` field! you should pass a valid CoverGroup")
                    end
                    cover_group = value
                
                -- Type of the CoverPoint
                elseif key == "type" then
                    if value ~= "simple" and value ~= "accurate" then
                        assert(false, "[cvhdl] invalid cover point type: " .. value .. ", available type: `simple`, `accurate`")
                    end
                    cover_point_type = value
                else
                    assert(false, "[cvhdl] invalid key: " .. key .. ", available keys: `group`") 
                end
            end 
        end
        
        local cover_point
        if cover_point_type == "simple" then
            cover_point = CoverPoint(name, cover_group)
            cover_group:add_cover_point(cover_point)
        elseif cover_point_type == "accurate" then
            cover_point = AccurateCoverPoint(name, cover_group)
            cover_group:add_cover_point(cover_point)
        else
            assert(false, "[cvhdl] invalid cover point type: " .. cover_point_type)
        end

        return cover_point
    end

    -- Alias of <string>:cvhdl()
    getmetatable('').__index.cover_point = function (name, params_table)
        name:cvhdl(params_table)
    end
end

local scheduler = require "verilua.scheduler.LuaScheduler"
local vl = require "Verilua"
local unnamed_task_count = 0
do
    local verilua_debug = _G.verilua_debug

    ---@deprecated Use seperate functions `fork`, `jfork`, `initial`, `final` instead
    ---@param cmd string
    ---@return fun(tbl: table)
    _G.verilua = function(cmd)
        if enable_verilua_debug then
            verilua_debug(f("[verilua/%s]", cmd), "execute => " .. cmd)
        end

        -- 
        -- Example
        --      verilua "appendTasks" {
        --          another_task = function ()
        --                 -- body
        --          end,
        --          some_task = function ()
        --                 -- body
        --          end
        --      }
        --      local function another_task()
        --           -- body
        --      end
        --      local function some_task()
        --          -- body
        --      end
        --      verilua "appendTasks" {
        --          another_task_name = another_task,
        --          some_task_name = some_task
        --      }
        -- 
        if cmd == "mainTask" or cmd == "appendTasks" then
            return function (task_table)
                assert(type(task_table) == "table")
                for name, func in pairs(task_table) do
                    if type(name) == "number" then
                        name = ("unnamed_task_%d"):format(unnamed_task_count)
                        unnamed_task_count = unnamed_task_count + 1   
                    end

                    if enable_verilua_debug then
                        verilua_debug(f("[verilua/%s]", cmd), "get task name => ", name)
                    end

                    scheduler:append_task(nil, name, func, true) -- (<task_id>, <task_name>, <task_func>, <start_now>)
                end
            end

        -- 
        -- Example:
        --      verilua "finishTask" { function ()
        --            -- body
        --      end }
        -- 
        --      local function some_finish_task()
        --          -- body
        --      end
        --      verilua "finishTask" {
        --          some_finish_task
        --      }
        -- 
        elseif cmd == "finishTask" then
            return function (task_table)
                assert(type(task_table) == "table")
                assert(#task_table == 1)
                local func = task_table[1]
                vl.register_finish_callback(func)
            end

        -- 
        -- Example:
        --      verilua "startTask" { function ()
        --            -- body
        --      end }
        -- 
        --      local function some_start_task()
        --          -- body
        --      end
        --      verilua "startTask" {
        --          some_finish_task
        --      }
        -- 
        elseif cmd == "startTask" then
            return function (task_table)
                assert(type(task_table) == "table")
                assert(#task_table == 1)
                local func = task_table[1]
                vl.register_start_callback(func)
            end

        elseif cmd == "appendFinishTasks" then
            return function (task_table)
                assert(type(task_table) == "table")
                for k, func in pairs(task_table) do
                    assert(type(func) == "function")
                    vl.append_finish_callback(func)
                end
            end

        elseif cmd == "appendStartTasks" then
            return function (task_table)
                assert(type(task_table) == "table")
                for k, func in pairs(task_table) do
                    assert(type(func) == "function")
                    vl.append_start_callback(func)
                end
            end

        elseif cmd == "showTasks" then
            scheduler:list_tasks()
        else
            local available_cmds = {
                "appendTasks",
                "startTask",
                "finishTask",
                "appendStartTasks",
                "appendFinishTasks",
                "showTasks",
            }
            assert(false, "Unknown cmd => " .. cmd .. ", available cmds: " .. _G.inspect(available_cmds))
            ---@diagnostic disable-next-line: missing-return
        end
    end

    --- Create multiple tasks run in parallel.
    --- e.g.
    --- ```lua
    ---      fork {
    ---          some_task = function ()
    ---              -- body
    ---          end,
    ---          another_task = function ()
    ---              -- body
    ---          end
    ---      }
    --- ```
    ---@param task_table table<TaskName|number, TaskFunction>
    _G.fork = function (task_table)
        assert(type(task_table) == "table")
        for name, func in pairs(task_table) do
            if type(name) == "number" then
                name = ("unnamed_fork_task_%d"):format(unnamed_task_count)
                unnamed_task_count = unnamed_task_count + 1   
            end

            if enable_verilua_debug then
                verilua_debug("[fork] get task name => ", name)
            end

            scheduler:append_task(nil, name, func, true) -- (<task_id>, <task_name>, <task_func>, <start_now>)
        end
    end

    --- Joinable fork, it can be used with `join` to wait until all tasks finished.
    --- Unlike `fork`, `jfork` allows user to wait for one or multiple tasks to finish.
    --- e.g.
    --- ```lua
    ---      -- (1) Create a joinable fork
    ---      local ehdl = jfork {
    ---          some_task = function ()
    ---              -- body
    ---          end
    ---      }
    ---      join(ehdl) -- Wait here until the task finished
    --- 
    ---      -- (2) Create multiple joinable forks
    ---      local ehdl1 = jfork {
    ---          some_task1 = function ()
    ---              -- body
    ---          end
    ---      }
    ---      local ehdl2 = jfork {
    ---          some_task2 = function ()
    ---              -- body
    ---          end
    ---      }
    ---      join(ehdl1, ehdl2) -- Wait here until both tasks finished
    --- ```
    ---@param one_task_table table<TaskName|number, TaskFunction>
    ---@return EventHandle, TaskID
    _G.jfork = function (one_task_table)
        ---@type EventHandle
        local ehdl
        ---@type TaskID
        local task_id
        local cnt = 0
        assert(type(one_task_table) == "table")
        for name, func in pairs(one_task_table) do
            cnt = cnt + 1
            assert(cnt == 1, "jfork only supports one task")

            if type(name) == "number" then
                name = ("unnamed_fork_task_%d"):format(unnamed_task_count)
                unnamed_task_count = unnamed_task_count + 1
            end

            if enable_verilua_debug then
                verilua_debug("[jfork] get task name => ", name)
            end

            ehdl = (name .. "__jfork_ehdl"):ehdl()
            ehdl.__type = "EventHandleForJFork"
            task_id = scheduler:append_task(nil, name, function()
                func()
                if ehdl:has_pending_wait() then
                    ehdl:send()
                else
                    verilua_debug("[jfork] ehdl has no pending wait, task_name: " .. name)
                end
                ehdl:remove()
            end, true) -- (<task_id>, <task_name>, <task_func>, <start_now>)
        end
        return ehdl, task_id
    end

    --- Join multiple `jfork` tasks(wait until all tasks finished).
    --- This function will block current task until all `jfork` tasks finished.
    --- e.g.
    --- ```lua
    ---      local ehdl1 = jfork {
    ---          some_task1 = function ()
    ---              -- body
    ---          end
    ---      }
    ---      local ehdl2 = jfork {
    ---          some_task2 = function ()
    ---              -- body
    ---          end
    ---      }
    ---      join({ ehdl1, ehdl2 }) -- Wait here until both tasks finished
    --- ```
    --- Or
    --- ```lua
    ---      local ehdl1 = jfork {
    ---          some_task1 = function ()
    ---              -- body
    ---          end
    ---      }
    ---      local ehdl2 = jfork {
    ---          some_task2 = function ()
    ---              -- body
    ---          end
    ---      }
    ---      join(ehdl1) -- Wait here until `ehdl1` finished
    ---      join(ehdl2) -- Wait here until `ehdl2` finished
    --- ```
    ---@param ehdl_or_ehdl_tbl EventHandle|table<integer, EventHandle>
    _G.join = function (ehdl_or_ehdl_tbl)
        assert(type(ehdl_or_ehdl_tbl) == "table")
        if ehdl_or_ehdl_tbl.event_id ~= nil then
            ---@cast ehdl_or_ehdl_tbl EventHandle
            ehdl_or_ehdl_tbl:wait()
        else
            ---@cast ehdl_or_ehdl_tbl EventHandle[]
            local expect_finished_cnt = 0
            local already_finished_cnt = 0
            local finished_ehdl_vec = {}
            for _, ehdl in ipairs(ehdl_or_ehdl_tbl) do
                local e_type = type(ehdl)
                if not(e_type == "table" and ehdl.__type == "EventHandleForJFork") then
                    assert(false, "`join` only supports EventHandle created by `jfork`, got " .. e_type)
                end

                finished_ehdl_vec[ehdl.event_id] = false
                table.insert(scheduler.event_task_id_list_map[ehdl.event_id], assert(scheduler.curr_task_id))

                if not scheduler.event_name_map[ehdl.event_id] then
                    already_finished_cnt = already_finished_cnt + 1
                end
            end
            expect_finished_cnt = #ehdl_or_ehdl_tbl

            -- Update expect_finished_cnt
            expect_finished_cnt = expect_finished_cnt - already_finished_cnt

            local finished_cnt = 0
            while true do
                -- If all ehdl are already finished, return
                if finished_cnt == expect_finished_cnt then
                    break
                end

                ---@diagnostic disable-next-line: undefined-global
                await_noop()

                finished_cnt = finished_cnt + 1

                local curr_wakeup_event_id = assert(scheduler.curr_wakeup_event_id)
                assert(not finished_ehdl_vec[curr_wakeup_event_id])
                finished_ehdl_vec[curr_wakeup_event_id] = true
            end
        end
    end

    --- Create initial tasks which will be executed at the start of simulation.
    --- These tasks are different from the tasks created by `verilua "appendTasks"` or `fork`,
    --- these tasks will be executed before all other tasks and only executed once.
    --- e.g.
    --- ```lua
    ---      initial {
    ---          task1 = function ()
    ---              -- body
    ---          end,
    ---          task2 = function ()
    ---              -- body    
    ---          end
    ---      }
    --- ```
    ---@param task_table table<TaskName|integer, TaskFunction>
    _G.initial = function (task_table)
        assert(type(task_table) == "table")
        for k, func in pairs(task_table) do
            assert(type(func) == "function")
            vl.append_start_callback(func)
        end
    end

    --- Create final tasks which will be executed at the end of simulation.
    --- These tasks are different from the tasks created by `verilua "appendFinishTasks"` or `finish`,
    --- these tasks will be executed after all other tasks and only executed once.
    --- e.g.
    --- ```lua
    ---      final {
    ---          task1 = function ()
    ---              -- body
    ---          end,
    ---          task2 = function ()
    ---              -- body    
    ---          end
    ---      }
    --- ```
    --- `final` is useful when user want to do any cleanup work for the simulation environment.
    ---@param task_table table<TaskName|integer, TaskFunction>
    _G.final = function (task_table)
        assert(type(task_table) == "table")
        for k, func in pairs(task_table) do
            assert(type(func) == "function")
            vl.append_finish_callback(func)
        end
    end
end

if os.getenv("VL_PREBUILD") == "1" then
    require "verilua.utils.PrebuildHelper"
else
    ---@diagnostic disable-next-line: duplicate-set-field
    _G.prebuild = function ()
        -- do nothing
    end
end

-- 
-- setup random seed
-- 
do
    _G.verilua_debug(f("random seed is %d", cfg.seed))
    math.randomseed(cfg.seed)
end

-- 
-- Implement sorts of SystemVerilog APIs
-- 
_G.urandom = function ()
    return math_random(0, 0xFFFFFFFF)
end

_G.urandom_range = function (min, max)
    if min > max then
        assert(false, "min should be less than or equal to max")
    end
    return math_random(min, max)
end

_G.sim = require "LuaSimulator"
_G.scheduler = scheduler

---@type ProxyTableHandle
_G.dut = (require "LuaDut").create_proxy(cfg.top)

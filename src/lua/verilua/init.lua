-- jit.opt.start(3)
-- jit.opt.start("loopunroll=100", "minstitch=0", "hotloop=1", "tryside=100")

do
    local PWD = os.getenv("PWD")
    local PRJ_TOP = os.getenv("PRJ_TOP")
    local VERILUA_HOME = os.getenv("VERILUA_HOME")

    local function append_package_path(path)
        package.path = package.path .. ";" .. path
    end

    local function append_package_cpath(path)
        package.cpath = package.cpath .. ";" .. path
    end

    append_package_path(PWD .. "/?.lua")
    append_package_path(PWD .. "/src/lua/?.lua")
    append_package_path(PWD .. "/src/lua/main/?.lua")
    append_package_path(PWD .. "/src/lua/configs/?.lua")
    append_package_path(VERILUA_HOME .. "/?.lua")
    append_package_path(VERILUA_HOME .. "/configs/?.lua")
    append_package_path(VERILUA_HOME .. "/src/lua/verilua/?.lua")
    append_package_path(VERILUA_HOME .. "/src/lua/?.lua")
    append_package_path(VERILUA_HOME .. "/src/lua/thirdparty_lib/?.lua")
    append_package_path(VERILUA_HOME .. "/extern/LuaPanda/Debugger/?.lua")
    append_package_path(VERILUA_HOME .. "/extern/luafun/?.lua")
    append_package_path(VERILUA_HOME .. "/extern/debugger.lua/?.lua")
    append_package_path(VERILUA_HOME .. "/luajit2.1/share/lua/5.1/?.lua")

    append_package_cpath(VERILUA_HOME .. "/extern/LuaPanda/Debugger/debugger_lib/?.so")

    if PRJ_TOP ~= nil then
        append_package_path(PRJ_TOP .. "/?.lua")
    end
end


-- 
-- used by c++
-- 
function lua_traceback()
    print(debug.traceback(""))
end


-- 
-- strict lua, any undeclared global variables will lead to failed
-- 
require "strict"


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

_G.debug_str = function(...)
    local file, line, func = get_debug_info(4)
    local args = {...}
    local message = table.concat(args, "\t")
    return (("[%s:%s:%d]"):format(file, func, line) .. "\t" .. message)
end

_G.debug_print = function (...)
    print(debug_str(...))
end


-- 
-- load configuration
-- 
local LuaSimConfig = require "LuaSimConfig"
local cfg_name, cfg_path
do
    local path = require "pl.path"
    local stringx = require "pl.stringx"

    cfg_name, cfg_path = LuaSimConfig.get_cfg()
    
    if cfg_path == nil then
        cfg_path = path.abspath(path.dirname(cfg_name)) -- get abs path name
    end
    
    assert(type(cfg_path) == "string")

    if string.len(cfg_path) ~= 0 then
        package.path = package.path .. ";" .. cfg_path .. "/?.lua" 
    end

    cfg_name = path.basename(cfg_name) -- strip basename

    if stringx.endswith(cfg_name, ".lua") then
        cfg_name = stringx.rstrip(cfg_name, ".lua") -- strip ".lua" suffix
    end
end
local cfg = require(cfg_name)

_G.CONNECT_CONFIG = LuaSimConfig.CONNECT_CONFIG
_G.VeriluaMode = LuaSimConfig.VeriluaMode


-- 
-- we should load ffi setenv before setting up other environment variables
-- 
_G.ffi = require "ffi"
ffi.cdef[[
    int setenv(const char *name, const char *value, int overwrite);
    long long c_handle_by_name_safe(const char* name);
    void c_set_value_by_name(const char *path, uint32_t value);
    uint64_t c_get_value_by_name(const char *path);
    void c_force_value_by_name(const char *path, long long value);
    void c_release_value_by_name(const char *path);
]]


-- 
-- setup LUA_SCRIPT inside init.lua, this can be overwrite by outer environment variable
-- 
do
    local LUA_SCRIPT = cfg.script
    if LUA_SCRIPT ~= nil then
        local ret = ffi.C.setenv("LUA_SCRIPT", tostring(LUA_SCRIPT), 1)
        if ret == 0 then
            debug_print("Environment variable <LUA_SCRIPT> set successfully.")
        else
            debug_print("Failed to set environment variable <LUA_SCRIPT>.")
        end
    end
end


-- 
-- setup VL_DEBUG inside init.lua, this can be overwrite by outer environment variable
-- 
do
    local VL_DEBUG = cfg.luapanda_debug
    if VL_DEBUG ~= nil then
        local ret = ffi.C.setenv("VL_DEBUG", tostring(VL_DEBUG), 1)
        if ret == 0 then
            debug_print("Environment variable <VL_DEBUG> set successfully.")
        else
            debug_print("Failed to set environment variable <VL_DEBUG>.")
        end
    end
end


-- 
-- setup VPI_LEARN inside init.lua, this can be overwrite by outer environment variable
-- 
do
    local VPI_LEARN = cfg.vpi_learn
    if VPI_LEARN ~= nil then
        local ret = ffi.C.setenv("VPI_LEARN", tostring(VPI_LEARN), 1)
        if ret == 0 then
            debug_print("Environment variable <VPI_LEARN> set successfully.")
        else
            debug_print("Failed to set environment variable <VPI_LEARN>.")
        end
    end
end


-- 
-- add source file package path
-- 
do
    local srcs = cfg.srcs
    assert(srcs ~= nil and type(srcs) == "table")
    for i, src in ipairs(srcs) do
        package.path = package.path .. ";" .. src
    end
end


-- 
-- add dependencies package path
-- 
do
    local deps = cfg.deps
    if deps ~= nil then
        assert(type(deps) == "table")
        for k, dep in pairs(deps) do
            package.path = package.path .. ";" .. dep
        end
    end
end


-- 
-- global debug log functions
-- 
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

_G.verilua_info = function (...)
    print(colors.cyan .. os.date() .. " [VERILUA INFO]", ...)
    io.write(colors.reset)
end

_G.verilua_warning = function (...)
    print(colors.yellow .. os.date() ..  "[VERILUA WARNING]", ...)
    io.write(colors.reset)
end

_G.verilua_error = function (...)
    local error_print = function(...)
        print(colors.red .. os.date() ..  "[VERILUA ERROR]", ...)
        io.write(colors.reset)
        io.flush()
    end
    assert(false, error_print(...))
end

_G.verilua_assert = function (cond, ...)
    if cond == nil or cond == false then
        verilua_error(...)
    end
end

_G.verilua_hello = function ()
    -- Generated by: http://www.patorjk.com/software/taag
    local hello = [[   
____   ____                .__ .__                  
\   \ /   /  ____  _______ |__||  |   __ __ _____   
 \   Y   / _/ __ \ \_  __ \|  ||  |  |  |  \\__  \  
  \     /  \  ___/  |  | \/|  ||  |__|  |  / / __ \_
   \___/    \___  > |__|   |__||____/|____/ (____  /
                \/                               \/ 
]]
    verilua_info(hello)
end





-- 
-- global package
-- 
_G.cfg     = cfg

local scommon = require "LuaSchedulerCommonV2"
for key, value in pairs(scommon) do
    _G[key] = value
end


_G.call    = nil -- syntax sugar for string literal calling
                 -- Example:
                 --     ("tb_top.cycles"):set(10)         --> this will cause syntax error or cannot reconize the <string literal>:set() metod  
                 --     call = ("tb_top".cycles):set(10)  --> this will work fine, here <call> act as a tempory store buffer for this empty return calling
_G.inspect = require "inspect"
_G.pp      = function (...) print(inspect(...)) end
_G.dbg     = function (...) print(inspect(...)) end
_G.TODO    = function(...) assert(false, debug_str("TODO:", ...)) end
_G.fatal   = function(...) assert(false, debug_str("FATAL:", ...)) end
_G.fassert = function(bool, ...)
    if bool == false then
        local args = {...}
        if #args == 0 then
            assert(false)
        else
            assert(false, string.format(...))
        end
    end
end
_G.dut     = (require "LuaDut").create_proxy(cfg.top)
local sim = require "LuaSimulator";
_G.sim     = sim


-- 
-- setup mode
-- 
do
    if cfg.simulator == "verilator" or cfg.simulator == "vcs" then
        if cfg.attach == false or cfg.attach == nil then
            cfg.mode = sim.get_mode()
        end
        verilua_info("VeriluaMode is "..VeriluaMode(cfg.mode))
    end
end


-- 
-- string operate extension
-- 
local CallableHDL = require "LuaCallableHDL"
local Bundle = require "LuaBundle"
local AliasBundle = require "LuaAliasBundle"
local stringx = require "pl.stringx"
do


    -- 
    -- Example: 
    --      (" "):join {1, 2, 3}    ==>  "1 2 3"
    --      ("-"):join {1, 2, 3}    ==>  "1-2-3"
    --      ("-"):join {1, 2, 3, "str"} ==> "1-2-3-str"
    -- 
    getmetatable('').__index.join = function(str, list)
        return stringx.join(str, list)
    end

    -- 
    -- Example: 
    --      ("0b11"):number()    ==> 3
    --      ("0x11"):number()    ==> 17
    --      ("123"):number()     ==> 123
    --      local hex_str = "0x11"
    --      hex_str:number()     ==> 17
    -- 
    getmetatable('').__index.number = function(str)
        if str:sub(1, 2) == "0b" then
            -- binary transform
            return tonumber(str:sub(3), 2)
        elseif str:sub(1, 2) == "0x" then
            -- hex transform
            return tonumber(str:sub(3), 16)
        else
            return tonumber(str)
        end
    end

    -- 
    -- get vpi handle using native stirng metatable
    -- Example: 
    --      local hdl_path = "tb_top.cycles"
    --      local hdl = hdl_path:hdl()
    --  
    --      local hdl = ("tb_top.clock"):hdl()
    -- 
    getmetatable('').__index.hdl = function(str)
        local hdl = ffi.C.c_handle_by_name_safe(str)

        if hdl == -1 then
            assert(false, string.format("No handle found => %s", str))
        end

        return hdl
    end

    -- 
    -- get CallableHDL using native stirng metatable
    -- Example:
    --      local cycles_chdl = ("tb_top.cycles"):chdl()
    --      print("value of cycles is " .. cycles_chdl:get())
    --      cycles_chdl:set(123)
    -- 
    getmetatable('').__index.chdl = function(str)
        return CallableHDL(str, "")
    end

    local function to_normal_table(org_tbl)
        local ret = {}
        for key, value in pairs(org_tbl) do
            table.insert(ret, value)
        end
        return ret
    end

    -- 
    -- get LuaBundle using native string metatable
    -- Example:
    --      local bdl = ("field1|field2|field3"):bundle {hier = "tb_top"} -- hier is the only one mandatory params to be passed into this constructor
    --      local bdl = ("valid | ready | opcode | data"):bundle {hier = "tb_top", is_decoupled = true}    
    --      local bdl = ("| valid | ready | opcode | data"): bundle {hier = "tb_top"}
    --      local bdl = ("| valid | ready | opcode | data |"): bundle {hier = "tb_top"}
    --      local strange_bdl = ([[
    --          field1 |
    --          field2     |
    --          field3 
    --      ]]):bundle {hier = "tb_top", name = "strange hdl name"}
    --      local beautiful_bdl = ([[
    --          field1  |
    --          field2  |
    --          field3  |
    --          field4  
    --      ]]):bundle {hier = "tb_top", prefix = "p_"}
    --      local beautiful_bdl_1 = ([[
    --          | field1 |
    --          | field2 |
    --          | field3 |
    --      ]]):bundle {hier = "tb_top", prefix = "p_"}
    --  
    --      local bdl_str = ("|"):join {"valid", "ready", "address", "opcode", "param", "source", "data"} -- bdl_str ==> "valid|ready|address|opcode|param|source|data"
    --      local bdl = bdl_str:bundle {hier = cfg.top .. ".u_TestTop_fullSys_1Core.l2", is_decoupled = true, name = "Channel A", prefix = "auto_in_a_"}
    -- 
    getmetatable('').__index.bundle = function(str, params_table)
        local signals_table = stringx.split(str, "|")
        local will_remove_idx = {}

        for i = 1, #signals_table do
            -- remove trivial characters
            signals_table[i] = stringx.replace(signals_table[i], " ", "")
            signals_table[i] = stringx.replace(signals_table[i], "\n", "")
            signals_table[i] = stringx.replace(signals_table[i], "\t", "")

            if signals_table[i] == "" then
                -- not a valid signal
                table.insert(will_remove_idx, i)
            end
        end

        -- remove invalid signal
        for index, value in ipairs(will_remove_idx) do
            signals_table[value] = nil
        end

        assert(type(params_table) == "table")

        -- turn into simple lua table
        local _signals_table = to_normal_table(signals_table)

        local hier = params_table.hier
        local hier_type = type(params_table.hier)
        
        assert(hier ~= nil, "<hierachy> is not set!")
        assert(hier_type == "string", "invalid <hierarchy> type => " .. hier_type)

        local prefix = ""
        local is_decoupled = true
        local name = "Unknown"
        for key, value in pairs(params_table) do
            if key == "prefix" then
                assert(type(value) == "string")
                prefix = value
            elseif key == "is_decoupled" then
                assert(type(value) == "boolean" )
                is_decoupled =  value
            elseif key == "name" then
                assert(type(value) == "string")
                name = value
            elseif key == "hier" then
                -- pass
            else
                assert(false, "Unkonwn params_table key => " .. tostring(key) .. " value => " .. tostring(value))
            end
        end

        return Bundle(_signals_table, prefix, hier, name, is_decoupled)
    end

    -- 
    -- Example:
    --      local cycles_str = "tb_top.cycles"
    --      cycles_str:set(0x123)
    --      cycles_str:set("0x123")
    --      cycles_str:set("0b111")
    --      call = ("tb_top.cycles"):set(100)
    -- 
    getmetatable('').__index.set = function (str, value)
        ffi.C.c_set_value_by_name(str, tonumber(value))
    end

    -- 
    -- Example: 
    --      local cycles_str = "tb_top.cycles"
    --      cycles_str:set_force(1)   -- force handle
    --      ...
    --      cycles_str:set_release()  -- release handle
    -- 
    getmetatable('').__index.set_force = function (str, value)
        ffi.C.c_force_value_by_name(str, tonumber(value))
    end
    getmetatable('').__index.set_release = function (str)
        ffi.C.c_release_value_by_name(str)
    end

    -- 
    -- Example:
    --      local cycles_hdl = "tb_top.cycles"
    --      local value_of_cycles = cycles_str:get()
    --      local value_of_cycles = ("tb_top.cycles"):get()
    -- 
    getmetatable('').__index.get = function (str)
        return tonumber(ffi.C.c_get_value_by_name(str))
    end

    -- 
    -- Example:
    --      local hex_str = ("tb_top.cycles"):get_hex()
    --      assert(hex_str == "0x123")
    -- 
    getmetatable('').__index.get_hex = function (str)
        return string.format("0x%x", tonumber(ffi.C.c_get_value_by_name(str)))
    end
    
    -- 
    -- Example:
    --      call = ("tb_top.clock"):posedge()
    --      local str = "tb_top.clock"
    --      str:posedge()
    -- 
    -- 
    getmetatable('').__index.posedge = function (str)
        await_posedge(str)
    end
    getmetatable('').__index.negedge = function (str)
        await_negedge(str)
    end

    -- 
    -- Examplel:
    --      local clock_str = "tb_top.clock"
    --      local ok = clock_str:posedge_until(1000, function ()
    --          return dut.cycles() >= 100
    --      end)
    --      
    --      local ok = ("tb_top".clock):posedge_until(1000, function ()
    --          return dut.cycles() >= 100
    --      end)
    -- 
    getmetatable('').__index.posedge_until = function (this, max_limit, func)
        assert(max_limit ~= nil)
        assert(type(max_limit) == "number")
        assert(max_limit >= 1)

        assert(func ~= nil)
        assert(type(func) == "function") 

        local condition_meet = false
        for i = 1, max_limit do
            condition_meet = func(i)
            assert(condition_meet ~= nil and type(condition_meet) == "boolean")

            if not condition_meet then
                await_posedge(this)
            else
                break
            end
        end

        return condition_meet
    end
    getmetatable('').__index.negedge_until = function (this, max_limit, func)
        assert(max_limit ~= nil)
        assert(type(max_limit) == "number")
        assert(max_limit >= 1)

        assert(func ~= nil)
        assert(type(func) == "function") 

        local condition_meet = false
        for i = 1, max_limit do
            condition_meet = func(i)
            assert(condition_meet ~= nil and type(condition_meet) == "boolean")
            
            if not condition_meet then
                await_negedge(this)
            else
                break 
            end
        end

        return condition_meet
    end

    -- 
    -- Example:
    --      local test_ehdl = ("test_1"):ehdl() -- event_id will be randomly allocated
    --      test_ehdl:wait()
    --      test_ehdl:send()
    --      
    --      local test_ehdl = ("test_1"):ehdl(1) -- manually set event_id
    -- 
    local scheduler = require "LuaScheduler"
    assert(scheduler ~= nil)
    getmetatable('').__index.ehdl = function (this, event_id_integer)
        return scheduler:get_event_hdl(this, event_id_integer)
    end


    -- 
    --  Example:
    --      local abdl = ([[
    --          | origin_signal_name => alias_name
    --          | origin_signal_name_1 => alias_name_1
    --      ]]):abdl {hier = "path.to.hier", perfix = "some_prefix_", name = "name of alias bundle"}
    --      local value = abdl.alias_name:get()    -- real signal is <path.to.hier.some_prefix_origin_signal_name>
    --      abdl.alias_name_1:set(123) 
    --
    --      local abdl = ([[
    --          | origin_signal_name
    --          | origin_signal_name_1 => alias_name_1
    --      ]]):abdl {hier = "top", prefix = "prefix"}
    --      local value = abdl.origin_signal_name:get()
    --      abdl.alias_name_1:set(123)
    --      
    --      local abdl = ([[
    --          | {p}_value => val_{b}
    --          | {b}_opcode => opcode
    --      ]]):abdl {hier ="hier", prefix = "prefix_", p = "hello", b = 123}
    --      local value = abdl.val_123:get()     -- real signal is <hier.prefix_hello_value>
    -- 
    getmetatable('').__index.abdl = function (str, params_table)
        local signals_table = stringx.split(str, "|")
        local will_remove_idx = {}

        for i = 1, #signals_table do
            -- remove trivial characters
            signals_table[i] = stringx.replace(signals_table[i], " ", "")
            signals_table[i] = stringx.replace(signals_table[i], "\n", "")
            signals_table[i] = stringx.replace(signals_table[i], "\t", "")

            if signals_table[i] == "" then
                -- not a valid signal
                table.insert(will_remove_idx, i)
            end
        end

        -- remove invalid signal
        for index, value in ipairs(will_remove_idx) do
            signals_table[value] = nil
        end

        assert(type(params_table) == "table")

        -- turn into simple lua table
        local _signals_table = to_normal_table(signals_table)

        -- replace some string literal with other <value>
        local pattern = "{[^%{%}%(%)]*}"
        for i = 1, #_signals_table do
            local matchs = string.gmatch(_signals_table[i], pattern)
            for match in matchs do
                local repl_key = string.gsub(string.gsub(match, "{", ""), "}", "")
                local repl_value = params_table[repl_key]
                local repl_value_str = tostring(repl_value)
                assert(repl_value ~= nil, string.format("repl_key: <%s> not found in <params_table>!", repl_key))

                _signals_table[i] = string.gsub(_signals_table[i], match, repl_value_str)
            end
        end

        local alias_tbl = {}
        for i = 1, #_signals_table do
            local tmp = stringx.split(_signals_table[i], "=>")
            assert(tmp[1] ~= nil)
            assert(type(tmp[1]) == "string")
            if tmp[2] ~= nil then
                assert(type(tmp[2]) == "string")
                table.insert(alias_tbl, {tmp[1], tmp[2]})
            else
                table.insert(alias_tbl, {tmp[1]})
            end
        end

        local hier = params_table.hier
        local hier_type = type(params_table.hier)
        
        assert(hier ~= nil, "<hierachy> is not set!")
        assert(hier_type == "string", "invalid <hierarchy> type => " .. hier_type)

        local prefix = ""
        local name = "Unknown"
        for key, value in pairs(params_table) do
            if key == "prefix" then
                assert(type(value) == "string")
                prefix = value
            elseif key == "name" then
                assert(type(value) == "string")
                name = value
            end
        end

        return AliasBundle(alias_tbl, prefix, hier, name)
    end

end

_G.verilua = function(cmd)
    local vl = require "Verilua"

    local print = function(...)
        print(string.format("[verilua/%s]", cmd), ...)
    end
    
    print("execute => " .. cmd)

    -- 
    -- Example:
    --      verilua "mainTask" { function ()
    --          -- body.
    --      end }

    --      local function lua_main()
    --          -- body
    --      end
    --      verilua "mainTask" {
    --          lua_main
    --      }

    --      verilua("mainTask")({function ()
    --          -- body
    --      end})

    --      local function lua_main()
    --          -- body
    --      end
    --      verilua("mainTask")({
    --          lua_main
    --      })
    -- 
    if cmd == "mainTask" then
        return function (task_table)
            assert(type(task_table) == "table")
            assert(#task_table == 1)
            print("register mainTask")
            vl.register_main_task(task_table[1])
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
    elseif cmd == "appendTasks" then
        return function (task_table)
            assert(type(task_table) == "table")
            local final_task_table = {}
            for name, func in pairs(task_table) do
                print("get task name => ", name)
                table.insert(final_task_table, {name, func, {}})
            end
            vl.register_tasks(final_task_table)
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
    elseif cmd == "showTasks" then
        local scheduler = require "LuaScheduler"
        assert(scheduler ~= nil)

        scheduler:list_tasks()
    elseif cmd == "test" then
        return function (str)
            print(str)
            TODO("Only for test...")
        end
    else
        assert(false, "Unknoen cmd => " .. cmd)
    end
end


-- 
-- initialize simulator
-- 
sim.print_hierarchy()
sim.init()


-- 
-- setup random seed
-- 
do
    local ENV_SEED = os.getenv("SEED")
    verilua_info("ENV_SEED is " .. tostring(ENV_SEED))
    verilua_info("cfg.seed is " .. tostring(cfg.seed))

    local final_seed = ENV_SEED ~= nil and tonumber(ENV_SEED) or cfg.seed
    verilua_info("final_seed is "..final_seed)

    verilua_info(("overwrite cfg.seed from %d to %d"):format(cfg.seed, final_seed))
    cfg.seed = final_seed

    verilua_info(("random seed is %d"):format(cfg.seed))
    math.randomseed(cfg.seed)
end


-- only used to test the ffi function invoke overhead
function test_func()
    
end
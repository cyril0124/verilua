-- jit.opt.start(3)
-- jit.opt.start("loopunroll=100", "minstitch=0", "hotloop=1", "tryside=100")

_G.inspect = require "inspect"
_G.pp      = function (...) print(inspect(...)) end

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

    local LUA_PATH = os.getenv("LUA_PATH") or ""
    local LUA_CPATH = os.getenv("LUA_CPATH") or ""
    package.path = package.path .. ";" .. LUA_PATH
    package.cpath = package.cpath .. ";" .. LUA_CPATH

    append_package_path(PWD .. "?.lua")
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
    append_package_path(VERILUA_HOME .. "/luajit-pro/luajit2.1/share/lua/5.1/?.lua")

    append_package_cpath(VERILUA_HOME .. "/luajit-pro/luajit2.1/lib/lua/5.1/?.so")
    append_package_cpath(VERILUA_HOME .. "/luajit-pro/luajit2.1/lib/lua/5.1/?/?.so")
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

_G.default_debug_level = 4
_G.debug_level = _G.default_debug_level
_G.debug_str = function(...)
    local file, line, func = get_debug_info(_G.debug_level)
    local args = {...}
    local message = table.concat(args, "\t")
    return (("[%s:%s:%d]"):format(file, func, line) .. "\t" .. message)
end

local enable_debug_print = os.getenv("VL_DEBUG") == "1"
if enable_debug_print then
    _G.debug_print = function (...)
        print(debug_str(...))
    end

    _G.debug_printf = function (...)
        print(debug_str(string.format(...)))
    end
else
    _G.debug_print = function (...)
    end

    _G.debug_printf = function (...)
    end
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
assert(type(cfg) == "table", string.format("`cfg` is not a `table`, maybe there is package conflict. cfg_name:%s cfg_path:%s", cfg_name, cfg_path))

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
    int verilator_get_mode(void);
]]

if cfg.simulator == "vcs" then
    ffi.cdef[[
        void dpi_set_scope(char *str);
        int vcs_get_mode(void);
    ]]
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

local enable_verilua_debug = os.getenv("VL_DEBUG") == "1"
if enable_verilua_debug == true then
    _G.verilua_debug = function (...)
        print(debug_str(colors.red .. os.date() .. " [VERILUA DEBUG]", ...))
        io.write(colors.reset)
    end
else
    _G.verilua_debug = function (...)
    end
end

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
    print(colors.cyan .. hello .. colors.reset)
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
            verilua_debug("Environment variable <%s> set successfully.", name)
        else
            verilua_debug("Failed to set environment variable <%s>.", name)
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
    -- setup VL_DEBUG inside init.lua, this can be overwrite by outer environment variable
    -- 
    local VL_DEBUG = cfg.luapanda_debug
    if VL_DEBUG ~= nil then
        setenv_from_lua("VL_DEBUG", VL_DEBUG)
    end

    -- 
    -- setup VL_DEF_VPI_LEARN inside init.lua, this can be overwrite by outer environment variable
    -- 
    local VL_DEF_VPI_LEARN = cfg.vpi_learn
    if VL_DEF_VPI_LEARN ~= nil then
        setenv_from_lua("VL_DEF_VPI_LEARN", VL_DEF_VPI_LEARN)
    end

    -- 
    -- setup DUT_TOP inside init.lua, this can be overwrite by outer environment variable
    -- 
    local DUT_TOP = cfg.top
    if DUT_TOP ~= nil then
        setenv_from_lua("DUT_TOP", DUT_TOP)
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
-- #define vpiBinStrVal          1
-- #define vpiOctStrVal          2
-- #define vpiDecStrVal          3
-- #define vpiHexStrVal          4
-- 
_G.BinStr = 1
_G.OctStr = 2
_G.DecStr = 3
_G.HexStr = 4



-- 
-- global package
-- 
_G.cfg     = cfg

-- 
-- setup mode
-- 
do
    if cfg.simulator == "verilator" or cfg.simulator == "vcs" then
        if cfg.attach == false or cfg.attach == nil then
            -- cfg.mode = sim.get_mode()
            if cfg.simulator == "vcs" then
                ffi.C.dpi_set_scope(ffi.cast("char *", cfg.top))
                local success, mode = pcall(function () return ffi.C.vcs_get_mode() end)
                if not success then
                    mode = VeriluaMode.NORMAL
                    verilua_warning("cannot found ffi.C.vcs_get_mode(), using default mode NORMAL")
                end
                cfg.mode = tonumber(mode)
            else
                assert(cfg.simulator == "verilator", "For now, only support Verilator")
                local mode = ffi.C.verilator_get_mode()
                cfg.mode = tonumber(mode)
            end
        end
        verilua_debug("VeriluaMode is " .. VeriluaMode(cfg.mode))
    end
end

-- 
-- import scheduler functions
-- 
local scommon = require "verilua.scheduler.LuaSchedulerCommonV2"
for key, value in pairs(scommon) do
    _G[key] = value
end


_G.dbg     = function (...) print(inspect(...)) end
_G.TODO    = function (...) error(debug_str("TODO:", ...)) end
_G.fatal   = function (...) error(debug_str("FATAL:", ...)) end
_G.fassert = function (bool, ...)
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

local f = string.format
_G.printf = function (s, ...) io.write(f(s, ...)) end

-- 
-- Table extension
-- 
table.join = function (...)
    local result = {}
    for _, t in ipairs({...}) do
        if type(t) == "table" then
            for k, v in pairs(t) do
                if type(k) == "number" then table.insert(result, v)
                else result[k] = v end
            end
        else
            table.insert(result, t)
        end
    end
    return result
end

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

    _G.catch = function (block)
        return {catch = block[1]}
    end

    _G.finally = function (block)
        return {finally = block[1]}
    end

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

-- 
-- string operate extension
-- 
local CallableHDL = require "verilua.handles.LuaCallableHDL"
local Bundle = require "verilua.handles.LuaBundle"
local AliasBundle = require "verilua.handles.LuaAliasBundle"
local CoverGroup = require "verilua.coverage.CoverGroup"
local CoverPoint = require "verilua.coverage.CoverPoint"
local AccurateCoverPoint = require "verilua.coverage.AccurateCoverPoint"

local stringx = require "pl.stringx"
do

----------------------------------------------------------------------
-- Basic string extension, for enhancing string operation
----------------------------------------------------------------------
    -- 
    -- Example:
    --      local template = "Hello {{name}}!"
    --      local rendered_template = template:render({name = "Bob"})
    --      assert(rendered_template == "Hello Bob!")
    -- 
    getmetatable('').__index.render = function(template, vars)
        assert(type(template) == "string", "[render] template must be a `string`")
        assert(type(vars) == "table", "[render] vars must be a `table`")
        return (template:gsub("{{(.-)}}", function(key)
            if vars[key] == nil then
                assert(false, f("[render] key not found: %s\n\ttemplate_str is: %s\n" , key, template))
            end
            return tostring(vars[key] or "")
        end))
    end

    -- 
    -- Example:
    --      ("hello world!"):print()
    --      ("hello {{name}}"):render({name = "Bob"}):print()
    --      ("hello %d"):format(123):print()
    -- 
    getmetatable('').__index.print = function(str)
        io.write(str .. "\n")
    end

    -- 
    -- Example:
    --      assert(("hello.lua"):strip(".lua") == "hello")
    --      assert(("hello"):strip(".lua") == "hello")
    -- 
    getmetatable('').__index.strip = function(str, suffix)
        assert(type(suffix) == "string", "suffix must be a string")
        if str:sub(-#suffix) == suffix then
            return str:sub(1, -#suffix - 1)
        else
            return str
        end
    end

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
    -- Example:
    --      ("hello world"):contains("hello") ==> true
    --      ("hello world"):contains("hell")  ==> false
    -- 
    getmetatable('').__index.contains = function(str, target)
        local startIdx, _ = str:find(target)
        if startIdx then
            return true
        else
            return false
        end
    end


----------------------------------------------------------------------
-- Hardware related string extension, including handles used for 
-- accessing internal hardware signals
----------------------------------------------------------------------
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
            assert(false, f("[hdl] no handle found => %s", str))
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
    getmetatable('').__index.chdl = function(str, hdl)
        return CallableHDL(str, "", hdl)
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
    local process_bundle = function(str, params_table)
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
        
        assert(hier ~= nil, "[bundle] hierachy is not set! please set by `hier` field ")
        assert(hier_type == "string", "[bundle] invalid hierarchy type => " .. hier_type)

        local prefix = ""
        local is_decoupled = true
        local name = "Unknown"
        local optional_signals = nil
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
            elseif key == "optional_signals" then
                assert(type(value) == "table")
                if #value > 0 then
                    assert(type(value[1]) == "string")
                end
                optional_signals = value
            elseif key == "hier" then
                -- pass
            else
                assert(false, "[bundle] unkonwn key => " .. tostring(key) .. " value => " .. tostring(value) .. ", available keys: `prefix`, `is_decoupled`, `name`, `optional_signals`, `hier`")
            end
        end

        return Bundle(_signals_table, prefix, hier, name, is_decoupled, optional_signals)
    end
    getmetatable('').__index.bundle = process_bundle
    getmetatable('').__index.bdl = process_bundle

    -- 
    -- Example:
    --      local cycles_str = "tb_top.cycles"
    --      cycles_str:set(0x123)
    --      cycles_str:set("0x123")
    --      cycles_str:set("0b111")
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
        return f("0x%x", tonumber(ffi.C.c_get_value_by_name(str)))
    end
    
    -- 
    -- Example:
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
    local scheduler = require "verilua.scheduler.LuaScheduler"
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
                assert(repl_value ~= nil, f("[abdl] replace key: <%s> not found in <params_table>!", repl_key))

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
        
        assert(hier ~= nil, "[abdl] hierachy is not set! please set by `hier` field ")
        assert(hier_type == "string", "[abdl] invalid hierarchy type => " .. hier_type)

        local prefix = ""
        local name = "Unknown"
        for key, value in pairs(params_table) do
            if key == "prefix" then
                assert(type(value) == "string", "[abdl] invalid type for the `prefix` field, valid type: `string`")
                prefix = value
            elseif key == "name" then
                assert(type(value) == "string", "[abdl] invalid type for the `name` field, valid type: `string`")
                name = value
            end
        end

        return AliasBundle(alias_tbl, prefix, hier, name)
    end


----------------------------------------------------------------------
-- Functional coverage related string extension
----------------------------------------------------------------------
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


----------------------------------------------------------------------
-- Other miscellaneous string extension
----------------------------------------------------------------------
    -- 
    --  Example:
    --    local lib = ([[
    --        #include "stdio.h"
    --
    --        int count = 0;
    --
    --        // $sym<hello> $ptr<void (*)(void)>
    --        void hello() {
    --            printf("hello %d\n", count);
    --            count++;
    --        }
    --
    --        // $sym<get_count> $ptr<int (*)(void)>
    --        int get_count() {
    --            return count;
    --        }
    --    ]]):tcc_compile()
    --    
    ------- OR -------
    --
    --    local lib = ([[
    --        #include "stdio.h"
    --
    --        int count = 0;
    --
    --        void hello() {
    --            printf("hello %d\n", count);
    --            count++;
    --        }
    --
    --        int get_count() {
    --            return count;
    --        }
    --    ]]):tcc_compile({ {sym = "hello", ptr = "void (*)(void)"}, {sym = "get_count", ptr = "int (*)(void)"} })
    --
    --     lib.hello()
    --     assert(lib.get_count() == 1)
    -- 
    
    local tcc = require "vl-tcc"
    getmetatable('').__index.tcc_compile = function(str, sym_ptr_tbls)
        local state = tcc.new()
        assert(state:set_output_type(tcc.OUTPUT.MEMORY))
        assert(state:compile_string(str))
        assert(state:relocate(tcc.RELOCATE.AUTO))

        local count = 0
        local lib = {_state = state} -- keep `state` alive to prevent GC

        for line in string.gmatch(str, "[^\r\n]+") do
            local symbol_name = line:match("%$sym<%s*([^>]+)%s*>")
            local symbol_ptr_pattern = line:match("%$ptr%s*<%s*([^>]+)%s*>")
            if symbol_name or symbol_ptr_pattern then
                count = count + 1
                print("[tcc_compile] [" .. count .. "] find symbol_name => \"" .. (symbol_name or "nil") .. "\"")
                print("[tcc_compile] [" .. count .. "] find symbol_ptr_pattern = \"" .. (symbol_ptr_pattern or "nil") .. "\"")
                local sym = assert(state:get_symbol(symbol_name))
                lib[symbol_name] = ffi.cast(symbol_ptr_pattern, sym)
            end
        end

        if sym_ptr_tbls ~= nil then
            assert(type(sym_ptr_tbls) == "table")
            assert(type(sym_ptr_tbls[1]) == "table")
            for _, sym_ptr_tbl in ipairs(sym_ptr_tbls) do
                local symbol_name = assert(sym_ptr_tbl.sym)
                local symbol_ptr_pattern = assert(sym_ptr_tbl.ptr)
                count = count + 1
                print("[tcc_compile] [" .. count .. "] [sym_ptr_tbls] find symbol_name => \"" .. (symbol_name or "nil") .. "\"")
                print("[tcc_compile] [" .. count .. "] [sym_ptr_tbls] find symbol_ptr_pattern = \"" .. (symbol_ptr_pattern or "nil") .. "\"")
                local sym = assert(state:get_symbol(symbol_name))
                lib[symbol_name] = ffi.cast(symbol_ptr_pattern, sym)
            end
        end

        assert(count > 0, f("\n[tcc_compile] Did not find any symbols! Please specify symbol_name or symbol_ptr_pattern in tcc code by a custom C comment: \"// $sym<SymbolName> $ptr<SymbolPtrPattern>\"! Or you could specify this info by the input table \"<string>:tcc_compile({{sym = <symbol_name>, ptr = <symbol_ptr_pattern>}, <other...>})\"\nThe tcc code is:\n%s", str))
        
        return lib
    end
end

local scheduler = require "verilua.scheduler.LuaScheduler"
assert(scheduler ~= nil)

local vl = require "Verilua"
local unnamed_task_count = 0
do
    local function is_number_str(str)
        return str:match("^%d+$") ~= nil
    end

    _G.verilua = function(cmd)

        local print = function(...)
            print(f("[verilua/%s]", cmd), ...)
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
                for name, func in pairs(task_table) do
                    if type(name) == "number" then
                        name = ("unnamed_task_%d"):format(unnamed_task_count)
                        unnamed_task_count = unnamed_task_count + 1   
                    end
                    print("get task name => ", name)
                    scheduler:append_task(nil, name, func, {}, true)
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
        elseif cmd == "test" then
            return function (str)
                print(str)
                TODO("Only for test...")
            end
        else
            local available_cmds = {
                "mainTask",
                "appendTasks",
                "startTask",
                "finishTask",
                "appendStartTasks",
                "appendFinishTasks",
                "showTasks",
            }
            assert(false, "Unknown cmd => " .. cmd .. ", available cmds: " .. inspect(available_cmds))
        end
    end

    _G.fork = function (task_table)
        assert(type(task_table) == "table")
        for name, func in pairs(task_table) do
            if type(name) == "number" then
                name = ("unnamed_fork_task_%d"):format(unnamed_task_count)
                unnamed_task_count = unnamed_task_count + 1   
            end
            print("[fork] get task name => ", name)
            scheduler:append_task(nil, name, func, {}, true)
        end
    end
    -- TODO: join?
end


-- 
-- initialize simulator
-- 
-- sim.print_hierarchy()
sim.init()


-- 
-- setup random seed
-- 
do
    local ENV_SEED = os.getenv("SEED")
    verilua_debug("ENV_SEED is " .. tostring(ENV_SEED))
    verilua_debug("cfg.seed is " .. tostring(cfg.seed))

    local final_seed = ENV_SEED ~= nil and tonumber(ENV_SEED) or cfg.seed
    verilua_debug("final_seed is "..final_seed)

    verilua_debug(("overwrite cfg.seed from %d to %d"):format(cfg.seed, final_seed))
    cfg.seed = final_seed

    verilua_debug(("random seed is %d"):format(cfg.seed))
    math.randomseed(cfg.seed)
end

-- 
-- Implement sorts of SystemVerilog APIs
-- 
_G.urandom = function ()
    return math.random(0, 0xFFFFFFFF)
end

_G.urandom_range = function (min, max)
    if(min > max) then
        error("min should be less than or equal to max")
    end
    return math.random(min, max)
end

----------------------------------------------------------------------------
-- These functions are only used to test the ffi function invoke overhead
----------------------------------------------------------- ----------------
function test_func()
    return 0;
end

function test_func_with_1arg(arg)
    return arg
end

function test_func_with_2arg(arg1, arg2)
    assert(arg1 == arg2)
    return arg1
end

function test_func_with_4arg(arg1, arg2, arg3, arg4)
    assert(arg1 == arg4)
    return arg1
end

function test_func_with_8arg(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    assert(arg1 == arg8)
    return arg1
end

function test_func_with_vec_arg(vec)
    return vec[1]
end
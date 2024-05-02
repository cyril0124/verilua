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
    return (("[%s:%s:%d]"):format(file, func, line) .. "\t" .. ...)
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
_G.inspect = require "inspect"
_G.pp      = function (...) print(inspect(...)) end
_G.dbg     = function (...) print(inspect(...)) end
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
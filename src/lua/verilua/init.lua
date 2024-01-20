local PWD = os.getenv("PWD")
local PRJ_TOP = os.getenv("PRJ_TOP")
local VERILUA_HOME = os.getenv("VERILUA_HOME")

local function append_package_path(path)
    package.path = package.path .. ";" .. path
end

local function append_package_cpath(path)
    package.cpath = package.cpath .. ";" .. path
end

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
append_package_path(VERILUA_HOME .. "/luajit2.1/share/lua/5.1/?.lua")

append_package_cpath(VERILUA_HOME .. "/extern/LuaPanda/Debugger/debugger_lib/?.so")

if PRJ_TOP ~= nil then
    append_package_path(PRJ_TOP .. "/?.lua")
end


-- load configuration
require "LuaSimConfig"
local VERILUA_CFG, _ = LuaSimConfig.get_cfg()
local cfg = require(VERILUA_CFG)


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


-- global package
_G.cfg     = cfg
_G.ffi     = require "ffi"
_G.inspect = require "inspect"
_G.dut     = (require "LuaDut").create_proxy(cfg.top)
local sim = require "LuaSimulator"; sim.init()
_G.sim     = sim

-- setup mode
if cfg.simulator == "verilator" or cfg.simulator == "vcs" then
    if cfg.attach == false then
        cfg.mode = sim.get_mode()
    end
    verilua_info("VeriluaMode is "..VeriluaMode(cfg.mode))
end

-- setup random seed
local ENV_SEED = os.getenv("SEED")
verilua_info("ENV_SEED is " .. tostring(ENV_SEED))
verilua_info("cfg.seed is " .. tostring(cfg.seed))

local final_seed = ENV_SEED ~= nil and tonumber(ENV_SEED) or cfg.seed
verilua_info("final_seed is "..final_seed)

verilua_info(("overwrite cfg.seed from %d to %d"):format(cfg.seed, final_seed))
cfg.seed = final_seed

verilua_info(("random seed is %d"):format(cfg.seed))
math.randomseed(cfg.seed)



return {
    append_package_path = append_package_path,
    append_package_cpath = append_package_cpath
}
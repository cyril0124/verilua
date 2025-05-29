local os = require "os"
local io = require "io"
local ffi = require "ffi"
local debug = require "debug"

local type = type
local print = print
local pairs = pairs
local error = error
local assert = assert
local rawget = rawget
local f = string.format
local tonumber = tonumber
local tostring = tostring
local setmetatable = setmetatable

---@class LuaSimConfig
---@field script string
---@field mode number
---@field top string Top module name of the DUT
---@field srcs table<string>
---@field deps table<string>
---@field is_hse boolean
---@field period number
---@field unit string
---@field luapanda_debug boolean
---@field vpi_learn boolean
---@field prj_dir string
---@field seed number
---@field colors AnsiColors
---@field get_or_else fun(self: LuaSimConfig, cfg_str: string, default: any): any
---@field get_or_else_log fun(self: LuaSimConfig, cfg_str: string, default: any, log_str: string): any
---@field dump_str fun(self: LuaSimConfig): string
---@field dump fun(self: LuaSimConfig)
---@field [string] any This represents any other fields that may be added to the configuration table
local cfg = {}

---@class AnsiColors
---@field reset string
---@field black string
---@field red string
---@field green string
---@field yellow string
---@field blue string
---@field magenta string
---@field cyan string
---@field white string
local colors = {
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
cfg.colors = colors

cfg.SchedulerMode = setmetatable({    
    NORMAL    = 1,
    STEP      = 2,
    DOMINANT  = 3,
    EDGE_STEP = 4,
    N         = 1, -- alias of NORMAL
    S         = 2, -- alias of STEP
    D         = 3, -- alias of DOMINANT
    E         = 4  -- alias of EDGE_STEP
}, { 
    __call = function (t, v)
        for name, value in pairs(t) do
            if value == v then
                return name
            end
        end
        assert(false, "[SchedulerMode] Key no found: " .. v)
    end
})

local function get_debug_info(level)
    local _level = level or 2 -- Level 2 because we're inside a function
    local info

    -- Get valid debug info. If not found(i.e. info.currentline == -1), then try to get the debug info from the previous level.
    repeat
        info = debug.getinfo(_level, "nSl")
        _level = _level - 1
    until info.currentline ~= -1

    local file = info.short_src -- info.source
    local line = info.currentline
    local func = info.name or "<anonymous>"

    return file, line, func
end

local function config_info(...)
    if _G.enable_verilua_debug then
        local file, line, _ = get_debug_info(4)
        io.write(colors.cyan)
        print(f("[%s:%d] [CONFIG INFO]", file, line), ...)
        io.write(colors.reset)
        io.flush()
    end
end

local function config_warn(...)
    if _G.enable_verilua_debug then
        local file, line, _ = get_debug_info(4)
        io.write(colors.yellow)
        print(f("[%s:%d] [CONFIG WARNING]", file, line), ...)
        io.write(colors.reset)
        io.flush()
    end
end

local function config_error(cond, ...)
    if cond == nil or cond == false then
        local file, line, _ = get_debug_info(4)
        io.write(colors.red)
        print(f("[%s:%d] [CONFIG ERROR]", file, line), ...)
        io.write(colors.reset)
        io.flush()
        assert(false, "config_error")
    end
end

local function type_check(value, name, expect_type)
    if type(value) ~= expect_type then
        error(f("Expected argument `%s` to be a `%s` value, but received a `%s` value instead, value => %s", name, expect_type, type(value), tostring(value)), 0)
    end
end

function cfg:config_info(...)
    if _G.enable_verilua_debug then
        local file, line, _ = get_debug_info(4)
        io.write(colors.cyan)
        print(f("[%s:%d] [CONFIG INFO]", file, line), ...)
        io.write(colors.reset)
        io.flush()
    end
end

function cfg:config_warn(...)
    if _G.enable_verilua_debug then
        local file, line, _ = get_debug_info(4)
        io.write(colors.yellow)
        print(f("[%s:%d] [CONFIG WARNING]", file, line), ...)
        io.write(colors.reset)
        io.flush()
    end
end

function cfg:config_error(cond, ...)
    if cond == nil or cond == false then
        local file, line, _ = get_debug_info(4)
        io.write(colors.red)
        print(f("[%s:%d] [CONFIG ERROR]", file, line), ...)
        io.write(colors.reset)
        io.flush()
        assert(false, "config_error")
    end
end

function cfg:get_or_else(cfg_str, default)
    local _cfg = rawget(self, cfg_str)
    if _cfg == nil then
        self:config_warn(f("[cfg:get_or_else] `cfg.%s` is `nil`! use default config => `%s`", cfg_str, tostring(default)))
        return default
    end
    return _cfg
end

function cfg:get_or_else_log(cfg_str, default, log_str)
    local _cfg = rawget(self, cfg_str)
    if _cfg == nil then
        local _log_str = log_str or ""
        self:config_warn(f("[cfg:get_or_else] %s `cfg.%s` is `nil`! use default config => `%s`", _log_str, cfg_str, tostring(default)))
        return default
    end
    return _cfg
end

-- Dumps the content of the configuration table as a string.
function cfg:dump_str()
    local inspect = require "inspect"
    return inspect(self, {
        process = function(item, path)
            local t = type(item)
            if t ~= "function" and t ~= "thread" and path[#path] ~= inspect.METATABLE and item ~= self.colors and item ~= self.SchedulerMode then
                return item
            end
        end
    })
end

-- Prints the content of the configuration table.
function cfg:dump()
    print("----------------------- cfg:dump --------------------------------")
    print(self:dump_str())
    print("----------------------------------------------------------------")
end

-- 
-- Provide a lazy way for accessing some configuration key while loading `<user cfg>.lua`.
-- You can access the following key in `<user_cfg>.lua` using `_G.cfg.<xxx>`.
-- Example:
--      ```user_cfg.lua
--          local cfg = {}
--          
--          cfg.simulator = _G.cfg.simulator
-- 
--          return cfg
--      ```
--
setmetatable(cfg, {
    __index = function (t, k)
        if k == "simulator" then
            ffi.cdef[[
                const char *vpiml_get_simulator_auto();
            ]]
            local simulator = ffi.string(ffi.C.vpiml_get_simulator_auto())
            if simulator ~= "unknown" then
                cfg.simulator = simulator
                config_info(f("[LazyAccess] Automatically detected simulator: %s", simulator), get_debug_info(3))
            end
            return simulator
        end
    end
})

function cfg:get_cfg()
    local VERILUA_CFG_PATH = os.getenv("VERILUA_CFG_PATH")
    local VERILUA_CFG = os.getenv("VERILUA_CFG")

    if VERILUA_CFG_PATH ~= nil then
        -- Add package path for the config file
        _G.package.path = _G.package.path .. ";" .. VERILUA_CFG_PATH .. "/?.lua"
    end

    return VERILUA_CFG, VERILUA_CFG_PATH
end

-- Alias of `cfg:get_cfg()`
function cfg:get_user_cfg()
    return self:get_cfg()
end

function cfg:merge_config(other_cfg, info_str)
    local info_str = info_str or ""
    assert(type(other_cfg) == "table")
    setmetatable(self, nil)

    for k, v in pairs(other_cfg) do
        if self[k] ~= nil then
            self:config_warn(f("[merge_config] %s duplicate key: %s value: %s", info_str, k, v))
        else
            self:config_info(f("[merge_config] %s new key: %s value: %s", info_str, k, v))
        end
        self[k] = v
    end
end

-- Special version of `cfg:merge_config`, which is used by `rules/xmake.lua`
function cfg.merge_config_1(src_cfg, other_cfg, info_str)
    local info_str = info_str or ""
    assert(type(other_cfg) == "table")

    for k, v in pairs(other_cfg) do
        if src_cfg[k] ~= nil then
            config_warn(f("[merge_config_1] %s duplicate key: %s value: %s", info_str, k, v))
        else
            config_info(f("[merge_config_1] %s new key: %s value: %s", info_str, k, v))
        end
        src_cfg[k] = v
    end
end

function cfg:post_config()
    -- Check necessary configs
    local cfg = self

    cfg.simulator = rawget(cfg, "simulator") or os.getenv("SIM")
    if not cfg.simulator then
        -- Try get simulator automatically
        ffi.cdef[[
            const char *vpiml_get_simulator_auto();
        ]]
        local simulator = ffi.string(ffi.C.vpiml_get_simulator_auto())
        if simulator ~= "unknown" then
            config_info(f("[cfg:post_config] Automatically detected simulator: %s", simulator))
            cfg.simulator = simulator
        end
    end
    assert(cfg.simulator, "[cfg:post_config] <cfg.simulator>(simulator) is not set! You should set <cfg.simulator> via enviroment variable <SIM> or <cfg.simulator>")

    cfg.script = cfg.script or os.getenv("LUA_SCRIPT")
    assert(cfg.script, "[cfg:post_config] <cfg.script>(script) is not set! You should set <cfg.script> via enviroment variable <LUA_SCRIPT> or <cfg.script>")

    if cfg.mode ~= nil then
        if type(cfg.mode) == "string" then
            ---@diagnostic disable-next-line: undefined-field
            local mode_str = cfg.mode:upper()
            if mode_str == "N" or mode_str == "NORMAL" then
                cfg.mode = cfg.SchedulerMode.NORMAL
            elseif mode_str == "S" or mode_str == "STEP" then
                cfg.mode = cfg.SchedulerMode.STEP
            elseif mode_str == "D" or mode_str == "DOMINANT" then
                cfg.mode = cfg.SchedulerMode.DOMINANT
            elseif mode_str == "E" or mode_str == "EDGE_STEP" then
                cfg.mode = cfg.SchedulerMode.EDGE_STEP
            else
                assert(false, "Invalid SchedulerMode: " .. cfg.mode)
            end
        else
            assert(type(cfg.mode) == "number")
            assert(cfg.mode == cfg.SchedulerMode.NORMAL or cfg.mode == cfg.SchedulerMode.STEP or cfg.mode == cfg.SchedulerMode.DOMINANT, "Invalid SchedulerMode: " .. cfg.mode)
        end
    else
        ---@diagnostic disable-next-line: assign-type-mismatch
        cfg.mode = "nil"
    end

    -- Make `cfg` available globally since it is used by `SignalDB` which provides the `vpiml_get_top_module()` function
    _G.cfg = cfg
    cfg.top = cfg.top or os.getenv("DUT_TOP")
    if not cfg.top then
        local vpiml = require "vpiml"
        config_warn(f("[cfg:post_config] <cfg.top>(top-level name) is not set! Try to get it from `vpiml.vpiml_get_top_module()`..."))
        cfg.top = ffi.string(vpiml.vpiml_get_top_module())
    end
    assert(cfg.top, "[cfg:post_config] <cfg.top>(top-level name) is not set! You should set <cfg.top> via enviroment variable <DUT_TOP> or <cfg.top>")

    -- Setup configs with default values
    cfg.srcs            = cfg:get_or_else("srcs", {"./?.lua"})
    cfg.deps            = cfg:get_or_else("deps", {}) -- Dependencies
    cfg.is_hse          = cfg:get_or_else("is_hse", false) or cfg:get_or_else("attach", false) -- Whether use verilua as HSE(Hardware Script Engine)
    cfg.period          = cfg:get_or_else("period", 10)
    cfg.unit            = cfg:get_or_else("unit", "ns")
    cfg.luapanda_debug  = cfg:get_or_else("luapanda_debug", false)
    cfg.vpi_learn       = cfg:get_or_else("vpi_learn", false)
    cfg.prj_dir         = cfg:get_or_else("prj_dir", os.getenv("PRJ_DIR") or ".")

    -- Setup seed, <SEED> set by environment variable has higher priority
    cfg.seed = cfg:get_or_else("seed", 1234)
    local env_seed = os.getenv("SEED")
    if env_seed then
        assert(env_seed:match("^%d+$") ~= nil, "[LuaSimConfig] Invalid <SEED>: " .. env_seed .. ", it should be a number!")
        _G.verilua_debug(f("Enviroment varibale <SEED> is set, overwrite cfg.seed from %s to %d", tostring(cfg.seed), env_seed))
        cfg.seed = tonumber(env_seed) --[[@as number]]
    end

    type_check(cfg.is_hse, "cfg.is_hse", "boolean")
    type_check(cfg.seed, "cfg.seed", "number")

    setmetatable(cfg, {
        __index = function (t, k)
            -- Any non-existent key will raise error
            config_error(false, f("[cfg] Attempt to access non-existent key '%s'", k))
        end
    })
end

return cfg
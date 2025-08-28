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

local colors = _G.colors

---@class verilua.LuaSimConfig
---@field script string
---@field mode "normal"|"step"|"edge_step"|"unknown"
---@field simulator "verilator"|"vcs"|"iverilog"|"wave_vpi"|"unknown"
---@field top string Top module name of testbench
---@field srcs string[]
---@field deps string[]
---@field is_hse boolean Whether use verilua as HSE(Hardware Script Engine)
---@field is_wal boolean Whether use verilua as WAL(Waveform Analysis Language)
---@field period integer
---@field unit string
---@field luapanda_debug boolean
---@field prj_dir string Project directory
---@field seed integer
---
--- Enable dpi_exporter optimization. The value getter function
--- will bypass vpiml and obtain the value from underlying DPI-C
--- functions. Increase the performance of the value getter functions.
--- i.e.
--- ```text
---  (origin) <chdl>:get() --> [vpiml]vpi_get_value() --> [dummy_vpi]complexHandle.getValue32() --> VERILUA_DPI_EXPORTER_xxx_GET() --> RTL Signals
---  (opt)    <chdl>:get() --> VERILUA_DPI_EXPORTER_xxx_GET() --> RTL Signals
--- ```
---@field enable_dpi_exporter boolean
---
---@field get_or_else fun(self: verilua.LuaSimConfig, cfg_str: string, default: any): any
---@field get_or_else_log fun(self: verilua.LuaSimConfig, cfg_str: string, default: any, log_str: string): any
---@field dump_str fun(self: verilua.LuaSimConfig): string
---@field dump fun(self: verilua.LuaSimConfig)
---@field [string] any This represents any other fields that may be added to the configuration table
local cfg = {}

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
        error(f(
                "Expected argument `%s` to be a `%s` value, but received a `%s` value instead, value => %s",
                name,
                expect_type,
                type(value),
                tostring(value)
            ),
            0
        )
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
        self:config_warn(f(
            "[cfg:get_or_else] %s `cfg.%s` is `nil`! use default config => `%s`",
            _log_str,
            cfg_str,
            tostring(default)
        ))
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
            if t ~= "function" and t ~= "thread" and path[#path] ~= inspect.METATABLE and item ~= self.colors then
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

--- Provide a lazy way for accessing some configuration key while loading `<user cfg>.lua`.
--- You can access the following key in `<user_cfg>.lua` using `_G.cfg.<xxx>`.
--- e.g. (in your <user_cfg>.lua)
--- ```lua
---     local cfg = {}
---     cfg.simulator = _G.cfg.simulator
---     return cfg
--- ```
setmetatable(cfg, {
    __index = function(t, k)
        if k == "simulator" then
            ffi.cdef [[
                const char *vpiml_get_simulator_auto();
            ]]
            local simulator = ffi.string(ffi.C.vpiml_get_simulator_auto())
            if simulator ~= "unknown" then
                ---@diagnostic disable-next-line: assign-type-mismatch
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
        ffi.cdef [[
            const char *vpiml_get_simulator_auto();
        ]]
        local simulator = ffi.string(ffi.C.vpiml_get_simulator_auto())
        if simulator ~= "unknown" then
            config_info(f("[cfg:post_config] Automatically detected simulator: %s", simulator))
            ---@diagnostic disable-next-line: assign-type-mismatch
            cfg.simulator = simulator
        end
    end
    assert(
        cfg.simulator ~= nil,
        "[cfg:post_config] <cfg.simulator>(simulator) is not set! You should set <cfg.simulator> via enviroment variable <SIM> or <cfg.simulator>"
    )

    cfg.script = cfg.script or os.getenv("LUA_SCRIPT")
    assert(
        cfg.script,
        "[cfg:post_config] <cfg.script>(script) is not set! You should set <cfg.script> via enviroment variable <LUA_SCRIPT> or <cfg.script>"
    )

    cfg.is_hse = cfg:get_or_else("is_hse", false)
    cfg.is_wal = cfg.simulator == "wave_vpi"

    if cfg.mode ~= nil then
        local scheduler_mode = cfg.mode
        if cfg.is_hse then
            local err_info = f([[
                `cfg.mode` only support the following options when `cfg.is_hse` is true:
                    - cfg.mode = "step"
                    - cfg.mode = "edge_step"
                But currently `cfg.mode` is `%s`
            ]], tostring(scheduler_mode))
            assert(scheduler_mode == "step" or scheduler_mode == "edge_step", err_info)
        else
            assert(
                scheduler_mode == "normal",
                [[[cfg:post_config] `cfg.mode` should be "normal" when using verilua as HVL or WAL]]
            )
        end
    else
        if cfg.is_hse then
            -- When using verilua as HSE(Hardware Script Engine), set the scheduler mode to "step"
            cfg.mode = "step"
        else
            -- When using verilua as HVL(Hardware Verification Language) or WAL(Waveform Analysis Language), set the scheduler mode to "normal"
            cfg.mode = "normal"
        end
    end

    -- Make `cfg` available globally since it is used by `SignalDB` which provides the `vpiml_get_top_module()` function
    _G.cfg = cfg
    cfg.top = cfg.top or os.getenv("DUT_TOP")
    if not cfg.top then
        local vpiml = require "vpiml"
        config_warn(f(
            "[cfg:post_config] <cfg.top>(top-level name) is not set! Try to get it from `vpiml.vpiml_get_top_module()`..."
        ))
        cfg.top = ffi.string(vpiml.vpiml_get_top_module())
    end
    assert(
        cfg.top,
        "[cfg:post_config] <cfg.top>(top-level name) is not set! You should set <cfg.top> via enviroment variable <DUT_TOP> or <cfg.top>"
    )

    -- Setup configs with default values
    cfg.srcs                = cfg:get_or_else("srcs", { "./?.lua" })
    cfg.deps                = cfg:get_or_else("deps", {}) -- Dependencies
    cfg.period              = cfg:get_or_else("period", 10)
    cfg.unit                = cfg:get_or_else("unit", "ns")
    cfg.luapanda_debug      = cfg:get_or_else("luapanda_debug", false)
    cfg.prj_dir             = cfg:get_or_else("prj_dir", os.getenv("PRJ_DIR") or ".")

    --- This flag is enabled by calling:
    --- ```lua
    ---      local DpiExporter = require "DpiExporter"
    ---      DpiExporter:init(<meta_info_file or nil>) -- cfg.enable_dpi_exporter will be set at the end of this function
    --- ```
    cfg.enable_dpi_exporter = false

    -- Setup seed, <SEED> set by environment variable `SEED` has higher priority
    cfg.seed                = cfg:get_or_else("seed", 1234)
    local env_seed          = os.getenv("SEED")
    if env_seed then
        assert(
            env_seed:match("^%d+$") ~= nil,
            "[verilua.LuaSimConfig] Invalid <SEED>: " .. env_seed .. ", it should be a number!"
        )
        _G.verilua_debug(f(
            "Enviroment varibale <SEED> is set, overwrite cfg.seed from %s to %d",
            tostring(cfg.seed),
            env_seed
        ))
        cfg.seed = tonumber(env_seed) --[[@as integer]]
    end

    type_check(cfg.is_hse, "cfg.is_hse", "boolean")
    type_check(cfg.seed, "cfg.seed", "number")

    setmetatable(cfg, {
        __index = function(t, k)
            -- Any non-existent key will raise error
            config_error(false, f("[cfg] Attempt to access non-existent key '%s'", k))
        end
    })
end

return cfg

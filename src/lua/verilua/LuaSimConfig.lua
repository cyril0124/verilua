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

---@class (partial) verilua.LuaSimConfig
---@field script string
---@field mode "normal"|"step"|"edge_step"|"unknown"
---@field simulator "verilator"|"vcs"|"xcelium"|"iverilog"|"wave_vpi"|"nosim"|"unknown"
---@field top string Top module name of testbench
---@field srcs string[]
---@field deps string[]
---@field is_hse boolean Whether use verilua as HSE(Hardware Script Engine)
---@field is_wal boolean Whether use verilua as WAL(Waveform Analysis Language)
---@field period integer
---@field unit string
---@field prj_dir string Project directory
---@field time_precision integer Time precision as exponent (e.g., -9 for ns, -12 for ps)
---@field time_unit string Time unit corresponding to time precision ("fs", "ps", "ns", "us", "ms", "s")
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
---@field resolve_seed fun(self: verilua.LuaSimConfig): integer
---@field setup_random_seed fun(self: verilua.LuaSimConfig)
---@field dump_str fun(self: verilua.LuaSimConfig): string
---@field dump fun(self: verilua.LuaSimConfig)
---@field [string] any This represents any other fields that may be added to the configuration table
local cfg = {}

local function get_debug_info(level)
    local _level = level or 2 -- Level 2 because we're inside a function
    ---@type debuglib.DebugInfo
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

---@diagnostic disable-next-line
function cfg:config_info(...)
    if _G.enable_verilua_debug then
        local file, line, _ = get_debug_info(4)
        io.write(colors.cyan)
        print(f("[%s:%d] [CONFIG INFO]", file, line), ...)
        io.write(colors.reset)
        io.flush()
    end
end

---@diagnostic disable-next-line
function cfg:config_warn(...)
    if _G.enable_verilua_debug then
        local file, line, _ = get_debug_info(4)
        io.write(colors.yellow)
        print(f("[%s:%d] [CONFIG WARNING]", file, line), ...)
        io.write(colors.reset)
        io.flush()
    end
end

---@diagnostic disable-next-line
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

---@diagnostic disable-next-line
function cfg:get_or_else(cfg_str, default)
    local _cfg = rawget(self, cfg_str)
    if _cfg == nil then
        self:config_warn(f("[cfg:get_or_else] `cfg.%s` is `nil`! use default config => `%s`", cfg_str, tostring(default)))
        return default
    end
    return _cfg
end

---@diagnostic disable-next-line
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

---@nodiscard Return value should not be discarded
---@return integer seed The resolved random seed
function cfg:resolve_seed()
    local seed = rawget(self, "seed")
    if seed == nil then
        seed = 1234
    end
    local env_seed = os.getenv("SEED")
    if env_seed then
        assert(
            env_seed:match("^%d+$") ~= nil,
            "[verilua.LuaSimConfig] Invalid <SEED>: " .. env_seed .. ", it should be a number!"
        )
        local parsed_seed = tonumber(env_seed) --[[@as integer]]
        _G.verilua_debug(f(
            "Enviroment varibale <SEED> is set, overwrite cfg.seed from %s to %d",
            tostring(seed),
            parsed_seed
        ))
        seed = parsed_seed
    end

    type_check(seed, "cfg.seed", "number")
    return seed
end

function cfg:setup_random_seed()
    local seed = self:resolve_seed()
    _G.verilua_debug(f("random seed is %d", seed))
    ---@diagnostic disable-next-line: access-invisible
    math.randomseed(seed)
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
    __index = function(_t, k)
        if k == "simulator" then
            ffi.cdef [[
                const char *vpiml_get_simulator_auto();
            ]]

            -- Enviroment variable `SIM` has higher priority than `vpiml_get_simulator_auto()`
            local simulator = os.getenv("SIM") or ffi.string(ffi.C.vpiml_get_simulator_auto())
            if simulator ~= "unknown" then
                ---@diagnostic disable-next-line: assign-type-mismatch
                cfg.simulator = simulator
                config_info(f("[LazyAccess] Automatically detected simulator: %s", simulator), get_debug_info(3))
            end
            return simulator
        end
    end
})

function cfg.get_cfg()
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
    info_str = info_str or ""
    assert(type(other_cfg) == "table")
    setmetatable(self, nil)

    for k, v in pairs(other_cfg) do
        if self[k] ~= nil then
            self:config_warn(f("[merge_config] %s duplicate key: %s value: %s", info_str, k, v))
        else
            self:config_info(f("[merge_config] %s new key: %s value: %s", info_str, k, v))
        end

        if k == "srcs" or k == "deps" then
            for _, p in ipairs(v) do
                if not self[k] then
                    self[k] = {}
                end
                table.insert(self[k], p)
            end
        else
            self[k] = v
        end
    end
end

-- Special version of `cfg:merge_config`, which is used by `rules/xmake.lua`
function cfg.merge_config_1(src_cfg, other_cfg, info_str)
    info_str = info_str or ""
    assert(type(other_cfg) == "table")

    for k, v in pairs(other_cfg) do
        if src_cfg[k] ~= nil then
            config_warn(f("[merge_config_1] %s duplicate key: %s value: %s", info_str, k, v))
        else
            config_info(f("[merge_config_1] %s new key: %s value: %s", info_str, k, v))
        end

        if k == "srcs" or k == "deps" then
            for _, p in ipairs(v) do
                if not src_cfg[k] then
                    src_cfg[k] = {}
                end
                table.insert(src_cfg[k], p)
            end
        else
            src_cfg[k] = v
        end
    end
end

function cfg:post_config()
    -- Check necessary configs
    local _cfg = self

    _cfg.simulator = rawget(_cfg, "simulator") or os.getenv("SIM")
    if not _cfg.simulator then
        -- Try get simulator automatically
        ffi.cdef [[
            const char *vpiml_get_simulator_auto();
        ]]
        local simulator = ffi.string(ffi.C.vpiml_get_simulator_auto())
        if simulator ~= "unknown" then
            config_info(f("[cfg:post_config] Automatically detected simulator: %s", simulator))
            ---@diagnostic disable-next-line: assign-type-mismatch
            _cfg.simulator = simulator
        end
    end
    assert(
        _cfg.simulator ~= nil,
        "[cfg:post_config] <cfg.simulator>(simulator) is not set! You should set <cfg.simulator> via enviroment variable <SIM> or <cfg.simulator>"
    )

    _cfg.script = _cfg.script or os.getenv("LUA_SCRIPT")
    assert(
        _cfg.script,
        "[cfg:post_config] <cfg.script>(script) is not set! You should set <cfg.script> via enviroment variable <LUA_SCRIPT> or <cfg.script>"
    )

    _cfg.is_hse = _cfg:get_or_else("is_hse", false)
    _cfg.is_wal = _cfg.simulator == "wave_vpi"
    assert(
        not (_cfg.is_hse and _cfg.is_wal),
        "[cfg:post_config] `cfg.is_hse` and `cfg.is_wal` cannot be true at the same time"
    )

    if _cfg.mode ~= nil then
        local scheduler_mode = _cfg.mode
        if _cfg.is_hse then
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
        if _cfg.is_hse then
            -- When using verilua as HSE(Hardware Script Engine), set the scheduler mode to "step"
            _cfg.mode = "step"
        else
            -- When using verilua as HVL(Hardware Verification Language) or WAL(Waveform Analysis Language), set the scheduler mode to "normal"
            _cfg.mode = "normal"
        end
    end

    -- Make `cfg` available globally since it is used by `SignalDB` which provides the `vpiml_get_top_module()` function
    _G.cfg = _cfg
    _cfg.top = _cfg.top or os.getenv("DUT_TOP")
    if not _cfg.top then
        local vpiml = require "verilua.vpiml.vpiml"
        config_warn(f(
            "[cfg:post_config] <cfg.top>(top-level name) is not set! Try to get it from `vpiml.vpiml_get_top_module()`..."
        ))
        _cfg.top = ffi.string(vpiml.vpiml_get_top_module())
    end
    assert(
        _cfg.top,
        "[cfg:post_config] <cfg.top>(top-level name) is not set! You should set <cfg.top> via enviroment variable <DUT_TOP> or <cfg.top>"
    )

    -- Setup configs with default values
    _cfg.srcs                = _cfg:get_or_else("srcs", { "./?.lua" })
    _cfg.deps                = _cfg:get_or_else("deps", {}) -- Dependencies
    _cfg.period              = _cfg:get_or_else("period", 10)
    _cfg.unit                = _cfg:get_or_else("unit", "ns")
    _cfg.prj_dir             = _cfg:get_or_else("prj_dir", os.getenv("PRJ_DIR") or ".")

    --- This flag is enabled by calling:
    --- ```lua
    ---      local DpiExporter = require "DpiExporter"
    ---      DpiExporter:init(<meta_info_file or nil>) -- cfg.enable_dpi_exporter will be set at the end of this function
    --- ```
    _cfg.enable_dpi_exporter = false

    -- Setup seed, <SEED> set by environment variable `SEED` has higher priority
    _cfg.seed                = _cfg:resolve_seed()

    type_check(_cfg.is_hse, "cfg.is_hse", "boolean")
    type_check(_cfg.seed, "cfg.seed", "number")

    -- Setup time precision and time unit
    do
        local vpiml = require "verilua.vpiml.vpiml"
        _cfg.time_precision = vpiml.vpiml_get_time_precision()

        local EXPONENT_TO_UNIT = {
            [-15] = "fs",
            [-12] = "ps",
            [-9] = "ns",
            [-6] = "us",
            [-3] = "ms",
            [0] = "s",
        }
        _cfg.time_unit = EXPONENT_TO_UNIT[_cfg.time_precision] or "unknown"

        config_info(f("[cfg:post_config] Time precision: 10^%d seconds (%s)", _cfg.time_precision, _cfg.time_unit))
    end

    setmetatable(_cfg, {
        __index = function(_t, k)
            -- Any non-existent key will raise error
            config_error(false, f("[cfg] Attempt to access non-existent key '%s'", k))
        end
    })
end

return cfg

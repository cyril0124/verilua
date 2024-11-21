local os = os
local io = io
local type = type
local debug = debug
local print = print
local pairs = pairs
local assert = assert
local rawget = rawget
local f = string.format
local tostring = tostring
local setmetatable = setmetatable

local cfg = {}

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

cfg.VeriluaMode = setmetatable({    
    NORMAL   = 1,
    STEP     = 2,
    DOMINANT = 3,
    N        = 1, -- alias of NORMAL
    S        = 2, -- alias of STEP
    D        = 3  -- alias of DOMINANT
}, { 
    __call = function (t, v)
        for name, value in pairs(t) do
            if value == v then
                return name
            end
        end
        assert(false, "[VeriluaMode] Key no found: " .. v)
    end
})

local function get_debug_info(level)
    local info = debug.getinfo(level or 2, "nSl") -- Level 2 because we're inside a function
    
    local file = info.short_src -- info.source
    local line = info.currentline
    local func = info.name or "<anonymous>"

    return file, line, func
end

local function config_info(...)
    local file, line, _ = get_debug_info(4)
    io.write(colors.cyan)
    print(f("[%s:%d] [CONFIG INFO]", file, line), ...)
    io.write(colors.reset)
    io.flush()
end

local function config_warn(...)
    local file, line, _ = get_debug_info(4)
    io.write(colors.yellow)
    print(f("[%s:%d] [CONFIG WARNING]", file, line), ...)
    io.write(colors.reset)
    io.flush()
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

function cfg:config_info(...)
    local file, line, _ = get_debug_info(4)
    io.write(colors.cyan)
    print(f("[%s:%d] [CONFIG INFO]", file, line), ...)
    io.write(colors.reset)
    io.flush()
end

function cfg:config_warn(...)
    local file, line, _ = get_debug_info(4)
    io.write(colors.yellow)
    print(f("[%s:%d] [CONFIG WARNING]", file, line), ...)
    io.write(colors.reset)
    io.flush()
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
    local cfg = rawget(self, cfg_str)
    if cfg == nil then
        self:config_warn(f("[cfg:get_or_else] `cfg.%s` is `nil`! use default config => `%s`", cfg_str, tostring(default)))
        return default
    end
    return cfg
end

function cfg:get_or_else_log(cfg_str, default, log_str)
    local cfg = rawget(self, cfg_str)
    if cfg == nil then
        local log_str = log_str or ""
        self:config_warn(f("[cfg:get_or_else] %s `cfg.%s` is `nil`! use default config => `%s`", log_str, cfg_str, tostring(default)))
        return default
    end
    return cfg
end

--- Dumps the content of the configuration table as a string.
function cfg:dump_str()
    local inspect = require "inspect"
    return inspect(self, {
        process = function(item, path)
            local t = type(item)
            if t ~= "function" and t ~= "thread" and path[#path] ~= inspect.METATABLE and item ~= self.colors and item ~= self.VeriluaMode then
                return item
            end
        end
    })
end

--- Prints the content of the configuration table.
function cfg:dump()
    print("----------------------- cfg:dump --------------------------------")
    print(self:dump_str())
    print("----------------------------------------------------------------")
end

function cfg:get_cfg()
    local VERILUA_CFG_PATH = os.getenv("VERILUA_CFG_PATH")
    local VERILUA_CFG = os.getenv("VERILUA_CFG")
    assert(VERILUA_CFG, "`VERILUA_CFG` is not set! You should set configuration file via enviroment variable <VERILUA_CFG>")

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
    cfg.top = cfg.top or os.getenv("DUT_TOP")
    assert(cfg.top, "[cfg:post_config] <cfg.top>(top-level name) is not set! You should set <cfg.top> via enviroment variable <DUT_TOP> or <cfg.top>")

    cfg.simulator = cfg.simulator or os.getenv("SIM")
    assert(cfg.simulator, "[cfg:post_config] <cfg.simulator>(simulator) is not set! You should set <cfg.simulator> via enviroment variable <SIM> or <cfg.simulator>")

    cfg.script = cfg.script or os.getenv("LUA_SCRIPT")
    assert(cfg.script, "[cfg:post_config] <cfg.script>(script) is not set! You should set <cfg.script> via enviroment variable <LUA_SCRIPT> or <cfg.script>")

    if cfg.mode ~= nil then
        if type(cfg.mode) == "string" then
            local mode_str = cfg.mode:upper()
            if mode_str == "N" or mode_str == "NORMAL" then
                cfg.mode = cfg.VeriluaMode.NORMAL
            elseif mode_str == "S" or mode_str == "STEP" then
                cfg.mode = cfg.VeriluaMode.STEP
            elseif mode_str == "D" or mode_str == "DOMINANT" then
                cfg.mode = cfg.VeriluaMode.DOMINANT
            else
                assert(false, "Invalid VeriluaMode: " .. cfg.mode)
            end
        else
            assert(type(cfg.mode) == "number")
            assert(cfg.mode == cfg.VeriluaMode.NORMAL or cfg.mode == cfg.VeriluaMode.STEP or cfg.mode == cfg.VeriluaMode.DOMINANT, "Invalid VeriluaMode: " .. cfg.mode)
        end
    end
    
    -- Setup configs with default values
    cfg.srcs            = cfg:get_or_else("srcs", {"./?.lua"})
    cfg.deps            = cfg:get_or_else("deps", {}) -- Dependencies
    cfg.attach          = cfg:get_or_else("attach", false) -- Attach verilua to simulator
    cfg.clock           = cfg:get_or_else("clock", cfg.top .. ".clock")
    cfg.reset           = cfg:get_or_else("reset", cfg.top .. ".reset")
    cfg.period          = cfg:get_or_else("period", 10)
    cfg.unit            = cfg:get_or_else("unit", "ns")
    cfg.luapanda_debug  = cfg:get_or_else("luapanda_debug", false)
    cfg.vpi_learn       = cfg:get_or_else("vpi_learn", false)
    cfg.seed            = cfg:get_or_else("seed", 1234)
    cfg.prj_dir         = cfg:get_or_else("prj_dir", os.getenv("PRJ_DIR") or ".")

    setmetatable(cfg, {
        __index = function (t, k)
            -- Any non-existent key will raise error
            config_error(false, f("[cfg] Attempt to access non-existent key '%s'", k))
        end
    })
end

return cfg
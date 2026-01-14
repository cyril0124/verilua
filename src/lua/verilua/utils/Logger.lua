---@diagnostic disable: need-check-nil
--- Verilua Logger Module
--- Provides beautiful and consistent logging output with ZERO runtime overhead
--- when log levels are disabled.
---
--- Key Performance Features:
--- - Compile-time function generation based on log level
--- - No runtime branch checks for disabled log levels
--- - Pre-computed color strings and format templates
--- - Minimal allocations in hot paths
---
--- Environment Variables:
--- - VL_LOG_LEVEL: debug|info|warn|error (default: info)
--- - NO_COLOR or VL_NO_COLOR: Disable colors
--- - VL_NO_ICONS: Disable Unicode icons
--- - VL_NO_UNICODE: Disable Unicode box characters
---
--- Usage:
--- ```lua
---     local Logger = require "verilua.utils.Logger"
---     local log = Logger.new("MyModule")
---     log:info("This is an info message")
---     log:success("Operation completed!")
---     log:warning("This is a warning")
---     log:error("This is an error")
--- ```

local os = require "os"
local string = require "string"
local table = require "table"
local math = require "math"

local tostring = tostring
local setmetatable = setmetatable
local ipairs = ipairs
local f = string.format
local rep = string.rep
local concat = table.concat
local floor = math.floor
local max = math.max
local min = math.min

local quiet = os.getenv("VL_QUIET") == "1"
local old_print = print
local print = quiet and function() end or old_print

--------------------------------------------------------------------------------
-- ANSI Color Codes (cached as upvalues for performance)
--------------------------------------------------------------------------------
local RESET = "\27[0m"
local BOLD = "\27[1m"
local DIM = "\27[2m"

local FG_BLACK = "\27[30m"
local FG_RED = "\27[31m"
local FG_GREEN = "\27[32m"
local FG_YELLOW = "\27[33m"
local FG_BLUE = "\27[34m"
local FG_MAGENTA = "\27[35m"
local FG_CYAN = "\27[36m"
local FG_WHITE = "\27[37m"

local FG_BRIGHT_BLACK = "\27[90m"
local FG_BRIGHT_RED = "\27[91m"
local FG_BRIGHT_GREEN = "\27[92m"
local FG_BRIGHT_YELLOW = "\27[93m"
local FG_BRIGHT_BLUE = "\27[94m"
local FG_BRIGHT_MAGENTA = "\27[95m"
local FG_BRIGHT_CYAN = "\27[96m"
local FG_BRIGHT_WHITE = "\27[97m"

--------------------------------------------------------------------------------
-- Box Drawing Characters
--------------------------------------------------------------------------------
local BOX = {
    TL = "┌",
    TR = "┐",
    BL = "└",
    BR = "┘",
    H = "─",
    V = "│",
    LT = "├",
    RT = "┤",
    TT = "┬",
    BT = "┴",
    CROSS = "┼",
    D_TL = "╔",
    D_TR = "╗",
    D_BL = "╚",
    D_BR = "╝",
    D_H = "═",
    D_V = "║",
    D_LT = "╠",
    D_RT = "╣",
    FULL = "█",
    LIGHT = "░",
    MEDIUM = "▒",
    DARK = "▓",
}

local BOX_ASCII = {
    TL = "+",
    TR = "+",
    BL = "+",
    BR = "+",
    H = "-",
    V = "|",
    LT = "+",
    RT = "+",
    TT = "+",
    BT = "+",
    CROSS = "+",
    D_TL = "+",
    D_TR = "+",
    D_BL = "+",
    D_BR = "+",
    D_H = "=",
    D_V = "|",
    D_LT = "+",
    D_RT = "+",
    FULL = "#",
    LIGHT = "-",
    MEDIUM = "=",
    DARK = "#",
}

local ICONS = {
    DEBUG = "🔍",
    INFO = "ℹ️ ",
    SUCCESS = "✅",
    WARNING = "⚠️ ",
    ERROR = "❌",
}

--------------------------------------------------------------------------------
-- Configuration (read once at module load time)
--------------------------------------------------------------------------------
---@class verilua.utils.Logger.log_levels
local LOG_LEVELS = { debug = 0, info = 1, warn = 2, warning = 2, error = 3 }

local function get_env_bool(name, default)
    local v = os.getenv(name)
    if v == "1" or v == "true" then return true end
    if v == "0" or v == "false" then return false end
    return default
end

local function supports_colors()
    local term = os.getenv("TERM") or ""
    local colorterm = os.getenv("COLORTERM") or ""
    if colorterm:find("truecolor") or colorterm:find("24bit") then return true end
    if term:find("xterm") or term:find("256color") or term:find("screen") or term:find("tmux") then return true end
    return term ~= "" and term ~= "dumb"
end

-- Global configuration (computed once at load time)
local CFG_USE_COLORS = not get_env_bool("NO_COLOR", false)
    and not get_env_bool("VL_NO_COLOR", false)
    and supports_colors()
local CFG_USE_ICONS = not get_env_bool("VL_NO_ICONS", false)
local CFG_USE_UNICODE = not get_env_bool("VL_NO_UNICODE", false)
local CFG_MIN_LEVEL = LOG_LEVELS[string.lower(os.getenv("VL_LOG_LEVEL") or "debug")] or 0
local CFG_BOX_WIDTH = 70

-- Select box characters based on unicode setting
local BOX_CHARS = CFG_USE_UNICODE and BOX or BOX_ASCII

--------------------------------------------------------------------------------
-- Compile-time generated helper functions
--------------------------------------------------------------------------------

-- Color function: either applies color or returns text as-is
local colorize
if CFG_USE_COLORS then
    colorize = function(text, color)
        return color .. text .. RESET
    end
else
    colorize = function(text, _)
        return text
    end
end

-- Icon function: either returns icon or empty string
local get_icon
if CFG_USE_ICONS then
    get_icon = function(key)
        return ICONS[key] or ""
    end
else
    get_icon = function(_)
        return ""
    end
end

-- Box character accessor
local get_box = function(key)
    return BOX_CHARS[key] or ""
end

--------------------------------------------------------------------------------
-- No-op function for disabled log levels (zero overhead)
--------------------------------------------------------------------------------
local function noop() end

--------------------------------------------------------------------------------
-- Logger Class
--------------------------------------------------------------------------------

---@class verilua.utils.Logger.config
---@field use_colors boolean? Whether to use ANSI colors
---@field min_level verilua.utils.Logger.log_levels? Minimum log level to display (0=debug, 1=info, 2=warn, 3=error)

---@class verilua.utils.Logger
---@field private module_name string
---@field private prefix string Pre-computed prefix string
---@field default verilua.utils.Logger Default logger instance
---@field debug fun(self: verilua.utils.Logger, ...)
---@field info fun(self: verilua.utils.Logger, ...)
---@field success fun(self: verilua.utils.Logger, ...)
---@field warning fun(self: verilua.utils.Logger, ...)
---@field error fun(self: verilua.utils.Logger, ...)
---@field new fun(module_name: string?, config: verilua.utils.Logger.config?): verilua.utils.Logger
local Logger = {}
Logger.__index = Logger

--- Create log function for a specific level
---@param self verilua.utils.Logger
---@param level number
---@param min_level number
---@param use_colors boolean
---@param color string
---@param icon_key string
---@return function
local function make_log_func(self, level, min_level, use_colors, color, icon_key)
    -- If level is below minimum, return no-op (zero runtime cost)
    if level < min_level then
        return noop
    end

    -- Pre-compute static parts
    ---@diagnostic disable-next-line: access-invisible
    local prefix = self.prefix
    local icon = get_icon(icon_key)
    local icon_str = icon ~= "" and (icon .. " ") or ""

    -- Return optimized log function
    if use_colors then
        local arrow = FG_BRIGHT_BLACK .. ">>" .. RESET .. " "
        return function(_, ...)
            local args = { ... }
            local msg = #args == 1 and tostring(args[1]) or concat(args, " ")
            print(arrow .. prefix .. icon_str .. color .. msg .. RESET)
        end
    else
        return function(_, ...)
            local args = { ... }
            local msg = #args == 1 and tostring(args[1]) or concat(args, " ")
            print(">> " .. prefix .. icon_str .. msg)
        end
    end
end

--- Create a new Logger instance with compile-time optimized methods
function Logger.new(module_name, config)
    local self = setmetatable({}, Logger)
    self.module_name = module_name or "VERILUA"

    -- Handle per-instance config overrides
    local use_colors = CFG_USE_COLORS
    local min_level = CFG_MIN_LEVEL

    if config then
        if config.use_colors ~= nil then use_colors = config.use_colors end
        if config.min_level ~= nil then min_level = config.min_level end
    end

    -- Pre-compute prefix string
    if use_colors then
        self.prefix = FG_BRIGHT_BLACK .. "[" .. self.module_name .. "]" .. RESET .. " "
    else
        self.prefix = "[" .. self.module_name .. "] "
    end

    -- Generate optimized log functions at creation time
    -- These functions have zero branching overhead for disabled levels
    self.debug = make_log_func(self, 0, min_level, use_colors, FG_BRIGHT_BLACK, "DEBUG")
    self.info = make_log_func(self, 1, min_level, use_colors, FG_CYAN, "")
    self.success = make_log_func(self, 1, min_level, use_colors, FG_GREEN, "SUCCESS")
    self.warning = make_log_func(self, 2, min_level, use_colors, FG_YELLOW, "WARNING")
    self.error = make_log_func(self, 3, min_level, use_colors, FG_RED, "ERROR")

    return self
end

--------------------------------------------------------------------------------
-- Formatting Methods (used less frequently, normal implementation)
--------------------------------------------------------------------------------

--- Print a horizontal line
function Logger:line(width, _, double)
    width = width or CFG_BOX_WIDTH
    local c = double and get_box("D_H") or get_box("H")
    print(colorize(rep(c, width), FG_CYAN))
end

--- Print a header box with title
function Logger:header(title, width)
    width = width or CFG_BOX_WIDTH
    local tl, tr = get_box("D_TL"), get_box("D_TR")
    local bl, br = get_box("D_BL"), get_box("D_BR")
    local h, v = get_box("D_H"), get_box("D_V")

    local inner = width - 2
    local title_len = #title
    local pad_l = floor((inner - title_len) / 2)
    local pad_r = inner - title_len - pad_l

    print(colorize(tl .. rep(h, inner) .. tr, FG_CYAN))
    print(colorize(v .. rep(" ", pad_l) .. title .. rep(" ", pad_r) .. v, FG_CYAN))
    print(colorize(bl .. rep(h, inner) .. br, FG_CYAN))
end

--- Start a section with title
function Logger:section_start(title, width)
    width = width or CFG_BOX_WIDTH
    local tl, h = get_box("TL"), get_box("H")
    local inner = width - 2 - #title - 2
    print(colorize(tl .. rep(h, 2) .. " " .. title .. " " .. rep(h, inner), FG_CYAN))
end

--- Print a section line
function Logger:section_line(content, width)
    width = width or CFG_BOX_WIDTH
    local v = get_box("V")
    local inner = width - 4
    local padded = #content < inner and (content .. rep(" ", inner - #content)) or content
    print(colorize(v, FG_CYAN) .. " " .. padded)
end

--- End a section
function Logger:section_end(width)
    width = width or CFG_BOX_WIDTH
    local bl, h = get_box("BL"), get_box("H")
    print(colorize(bl .. rep(h, width - 1), FG_CYAN))
end

--- Print a simple table
function Logger:table(headers, rows, col_widths)
    local num_cols = #headers

    if not col_widths then
        col_widths = {}
        for i = 1, num_cols do
            col_widths[i] = #tostring(headers[i])
        end
        for _, row in ipairs(rows) do
            for i = 1, num_cols do
                local len = #tostring(row[i] or "")
                if len > col_widths[i] then col_widths[i] = len end
            end
        end
        for i = 1, num_cols do col_widths[i] = col_widths[i] + 2 end
    end

    local h, v = get_box("H"), get_box("V")
    local tl, tr, bl, br = get_box("TL"), get_box("TR"), get_box("BL"), get_box("BR")
    local tt, bt, lt, rt, cross = get_box("TT"), get_box("BT"), get_box("LT"), get_box("RT"), get_box("CROSS")

    local function build_sep(left, mid, right)
        local parts = { left }
        for i, w in ipairs(col_widths) do
            parts[#parts + 1] = rep(h, w)
            if i < num_cols then parts[#parts + 1] = mid end
        end
        parts[#parts + 1] = right
        return concat(parts)
    end

    local function build_row(cells)
        local parts = { v }
        for i, w in ipairs(col_widths) do
            local cell = tostring(cells[i] or "")
            local pad = w - #cell
            local pad_l = floor(pad / 2)
            parts[#parts + 1] = rep(" ", pad_l) .. cell .. rep(" ", pad - pad_l)
            parts[#parts + 1] = v
        end
        return concat(parts)
    end

    print(colorize(build_sep(tl, tt, tr), FG_CYAN))
    print(colorize(build_row(headers), FG_CYAN))
    print(colorize(build_sep(lt, cross, rt), FG_CYAN))
    for _, row in ipairs(rows) do
        print(colorize(build_row(row), FG_CYAN))
    end
    print(colorize(build_sep(bl, bt, br), FG_CYAN))
end

--- Generate a progress bar string
function Logger:progress_bar(progress, width, show_percent)
    width = width or 30
    show_percent = show_percent == nil and true or show_percent
    progress = max(0, min(1, progress))

    local full, empty = get_box("FULL"), get_box("LIGHT")
    local filled = floor(progress * width)
    local bar = rep(full, filled) .. rep(empty, width - filled)
    local result = get_box("V") .. bar .. get_box("V")

    if show_percent then
        result = result .. f(" %5.1f%%", progress * 100)
    end

    local color = progress > 0.75 and FG_GREEN or
        (progress > 0.5 and FG_YELLOW or (progress > 0.25 and FG_BRIGHT_YELLOW or FG_RED))
    return colorize(result, color)
end

--- Print Verilua banner
function Logger:banner()
    local banner = [[
____   ____                .__ .__
\   \ /   /  ____  _______ |__||  |   __ __ _____
 \   Y   / _/ __ \ \_  __ \|  ||  |  |  |  \\__  \
  \     /  \  ___/  |  | \/|  ||  |__|  |  / / __ \_
   \___/    \___  > |__|   |__||____/|____/ (____  /
                \/                               \/]]
    print(colorize(banner, FG_CYAN))
end

--- Print simulation summary
function Logger:sim_summary(elapsed_time)
    self:line(56, nil, true)
    print(colorize(f("   Simulation Finished! Elapsed time: %.4f sec", elapsed_time), FG_CYAN))
    self:line(56, nil, true)
    print()
end

--- Print key-value pair
function Logger:kv(key, value, key_width)
    key_width = key_width or 25
    local key_str = f("%-" .. key_width .. "s", key .. ":")
    print(colorize(key_str, FG_BRIGHT_BLACK) .. " " .. tostring(value))
end

--------------------------------------------------------------------------------
-- Module Exports
--------------------------------------------------------------------------------

Logger.COLORS = {
    RESET = RESET,
    BOLD = BOLD,
    DIM = DIM,
    RED = FG_RED,
    GREEN = FG_GREEN,
    YELLOW = FG_YELLOW,
    BLUE = FG_BLUE,
    MAGENTA = FG_MAGENTA,
    CYAN = FG_CYAN,
    WHITE = FG_WHITE,
    BRIGHT_RED = FG_BRIGHT_RED,
    BRIGHT_GREEN = FG_BRIGHT_GREEN,
    BRIGHT_YELLOW = FG_BRIGHT_YELLOW,
    BRIGHT_BLUE = FG_BRIGHT_BLUE,
    BRIGHT_CYAN = FG_BRIGHT_CYAN,
    BRIGHT_BLACK = FG_BRIGHT_BLACK,
}

Logger.BOX = BOX
Logger.ICONS = ICONS

-- Configuration accessors
Logger.CFG = {
    USE_COLORS = CFG_USE_COLORS,
    USE_ICONS = CFG_USE_ICONS,
    USE_UNICODE = CFG_USE_UNICODE,
    MIN_LEVEL = CFG_MIN_LEVEL,
}

-- Utility functions for external use
Logger.colorize = colorize
Logger.get_box = get_box
Logger.get_icon = get_icon

-- Default logger instance (created once)
local default_logger = Logger.new("VERILUA")
Logger.default = default_logger

return Logger

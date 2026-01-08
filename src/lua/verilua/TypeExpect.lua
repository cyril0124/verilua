---@diagnostic disable: unnecessary-if, global-in-non-module

local ffi = require "ffi"
local inspect = require "inspect"
local Logger = require "verilua.utils.Logger"

local type = type
local pairs = pairs
local assert = assert
local tostring = tostring
local colors = Logger.COLORS

local FAKE_CHDL_NAME_PREFIX = "fake_chdl::"

local function smart_inspect(value)
    local s = inspect(value):gsub("\n", " ")
    if #s > 100 then
        s = s:sub(1, 100) .. "..."
    end
    return s
end

---@class verilua.TypeExpect
local texpect = {}

local function get_caller_info()
    local level = 1
    local type_expect_func = nil
    while true do
        local info = debug.getinfo(level, "fnSl")
        if not info then break end

        if info.short_src:match("TypeExpect%.lua$") then
            if info.name and info.name:match("^expect_") then
                type_expect_func = info.name
            elseif info.func then
                for name, f in pairs(texpect) do
                    if f == info.func then
                        type_expect_func = name
                        break
                    end
                end
            end
        elseif info.what ~= "C" then
            return info, type_expect_func
        end
        level = level + 1
    end
    return nil, type_expect_func
end

local function texpect_error(msg)
    local info, func_name = get_caller_info()
    local loc = ""
    if info then
        loc = Logger.colorize(string.format("@ %s:%d", info.short_src, info.currentline), colors.CYAN)
    end

    local func_tag = ""
    if func_name then
        func_tag = string.format("[%s] ", Logger.colorize(func_name, colors.YELLOW))
    end

    local header = Logger.colorize("[TypeExpect Error]", colors.RED)
    local traceback = debug.traceback("", 2)
    local full_msg = string.format("\n%s %s%s\n%s%s\n", header, func_tag, loc, msg, traceback)

    _G.error(full_msg, 0)
end

---@param value string
---@param name string
function texpect.expect_string(value, name)
    if type(value) ~= "string" then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("string", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end
end

---@param value number
---@param name string
function texpect.expect_number(value, name)
    if type(value) ~= "number" then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("number", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end
end

---@param value integer|ffi.ct* Also supports LuaJIT LL/ULL literals
---@param name string
function texpect.expect_integer(value, name)
    local is_valid = false

    if type(value) == "number" then
        is_valid = true
    elseif type(value) == "cdata" then
        if ffi.istype("int64_t", value) or ffi.istype("uint64_t", value) then
            is_valid = true
        end
    end

    if not is_valid then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("integer (number, LL, or ULL)", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end
end

---@param value boolean
---@param name string
function texpect.expect_boolean(value, name)
    if type(value) ~= "boolean" then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("boolean", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end
end

---@param value table
---@param name string
---@param table_keys table<integer, string>? Optional whitelist of allowed table keys
function texpect.expect_table(value, name, table_keys)
    if type(value) ~= "table" then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("table", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end

    -- Validate table keys against whitelist if provided
    if table_keys then
        local keys_set = {}
        for _, k in ipairs(table_keys) do
            keys_set[k] = true
        end

        local invalid_keys = {}
        for key, _ in pairs(value) do
            if not keys_set[key] then
                table.insert(invalid_keys, key)
            end
        end

        if #invalid_keys > 0 then
            texpect_error(
                string.format(
                    "  Argument: %s\n  Expected: table with keys %s\n  Received: table with unexpected keys: %s\n  Allowed keys: %s\n  Value: %s",
                    Logger.colorize("`" .. name .. "`", colors.YELLOW),
                    Logger.colorize(inspect(table_keys), colors.GREEN),
                    Logger.colorize(inspect(invalid_keys), colors.RED),
                    Logger.colorize(inspect(table_keys), colors.CYAN),
                    smart_inspect(value)
                )
            )
        end
    end
end

---@param value function
---@param name string
function texpect.expect_function(value, name)
    if type(value) ~= "function" then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("function", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end
end

---@param value thread
---@param name string
function texpect.expect_thread(value, name)
    if type(value) ~= "thread" then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("thread", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end
end

---@param value userdata
---@param name string
function texpect.expect_userdata(value, name)
    if type(value) ~= "userdata" then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("userdata", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end
end

---@param value ffi.cdata*
---@param name string
function texpect.expect_struct(value, name)
    if type(value) ~= "cdata" then
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("cdata", colors.GREEN),
                Logger.colorize(type(value), colors.RED),
                smart_inspect(value)
            )
        )
    end
end

---@param value verilua.handles.CallableHDL
---@param name string
---@param width_or_width_min number?
---@param width_max number?
function texpect.expect_chdl(value, name, width_or_width_min, width_max)
    if type(value) ~= "table" or value.__type ~= "CallableHDL" then
        local received_type = type(value) --[[@as string]]
        if received_type == "table" and value.__type then
            received_type = tostring(value.__type)
        end
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("CallableHDL", colors.GREEN),
                Logger.colorize(received_type, colors.RED),
                smart_inspect(value)
            )
        )
    else
        if width_or_width_min ~= nil and width_max == nil then
            local is_fake_chdl = value.name:find(FAKE_CHDL_NAME_PREFIX) ~= nil
            if is_fake_chdl and type(rawget(value, "get_width")) ~= "function" then
                local error_msg = string.format(
                    [[
  Argument: %s
  Error: fake_chdl `%s` does not have a `get_width()` method
  Expected width: %s

  Please implement `get_width()` method for this fake_chdl.

  Example of creating a fake_chdl with get_width():

    local fake_signal = ("your.hierpath"):fake_chdl {
        --
        -- Other methods ...
        --

        get_width = function(self)
            return %d  -- Must return %d
        end
    }

  Note: The `get_width()` method is required when calling expect_chdl() with a width parameter.
]],
                    Logger.colorize("`" .. name .. "`", colors.YELLOW),
                    Logger.colorize(value.name, colors.RED),
                    Logger.colorize(tostring(width_or_width_min), colors.CYAN),
                    width_or_width_min,
                    width_or_width_min
                )
                texpect_error(error_msg)
            end

            if value:get_width() ~= width_or_width_min then
                texpect_error(
                    string.format(
                        "  Argument: %s\n  Expected: %s\n  Received: %s",
                        Logger.colorize("`" .. name .. "`", colors.YELLOW),
                        Logger.colorize("CallableHDL with width " .. width_or_width_min, colors.GREEN),
                        Logger.colorize("CallableHDL with width " .. value:get_width(), colors.RED)
                    )
                )
            end
        elseif width_or_width_min ~= nil and width_max ~= nil then
            if value:get_width() < width_or_width_min or value:get_width() > width_max then
                texpect_error(
                    string.format(
                        "  Argument: %s\n  Expected: %s\n  Received: %s",
                        Logger.colorize("`" .. name .. "`", colors.YELLOW),
                        Logger.colorize(
                            string.format("CallableHDL with width in [%d, %d]", width_or_width_min, width_max),
                            colors.GREEN),
                        Logger.colorize("CallableHDL with width " .. value:get_width(), colors.RED)
                    )
                )
            end
        end
    end
end

---@param value verilua.handles.Bundle
---@param name string
function texpect.expect_bdl(value, name)
    if type(value) ~= "table" or value.__type ~= "Bundle" then
        local received_type = type(value) --[[@as string]]
        if received_type == "table" and value.__type then
            received_type = tostring(value.__type)
        end
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("Bundle", colors.GREEN),
                Logger.colorize(received_type, colors.RED),
                smart_inspect(value)
            )
        )
    end
end

--[[

Expect a value to be a `AliasBundle` (an instance of `AliasBundle` class).

Params:
- `value`: value to be checked
- `name`: name of argument to be checked
- `params`: optional, a `table` or a `string` that contains the information of the
            expected signals in `AliasBundle`, each item in `params` should be a
            `table` or a `string`:
            - If item is a `table`, it should have a `name` field, and optionally
              `width`, `width_min`, `width_max` fields, which specify the width
              constraints of the signal with the given name.
            - If item is a `string`, it is considered as the name of a signal.
            - For example:
              {
                  { name = "signal",  width = 10 },   -- or { name = "signal", width_min = 10, width_max = 100 }
                  { name = "another", width = 32 },
                  { name = "abc" },
                  "cde",
                  "clock",
                  "reset"
              }

Returns:
- Nothing

Throws:
- An error if `value` is not a `AliasBundle`, or if any of the items in `params`
  does not match the corresponding signal in `value`.

--]]
---@class (exact) verilua.TypeExpect.expect_abdl.params
---@field name? string
---@field names? table<integer, string> If `names`(can be used to specify multiple alias names) is provided, then `name` is ignored
---@field width? integer
---@field width_min? integer
---@field width_max? integer

---@param value verilua.handles.AliasBundle
---@param name string
---@param params table<integer, string|verilua.TypeExpect.expect_abdl.params>
function texpect.expect_abdl(value, name, params)
    if type(value) ~= "table" or value.__type ~= "AliasBundle" then
        local received_type = type(value) --[[@as string]]
        if received_type == "table" and value.__type then
            received_type = tostring(value.__type)
        end
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("AliasBundle", colors.GREEN),
                Logger.colorize(received_type, colors.RED),
                smart_inspect(value)
            )
        )
    else
        --
        -- params = {
        --      { name = "signal",  width = 10 },   -- or { name = "signal", width_min = 10, width_max = 100 }
        --      { name = "another", width = 32 },
        --      { name = "abc" },
        --      { names = { "abc", "def" } }, -- abc and def are alias names of the same signal
        --      "cde",
        --      "clock",
        --      "reset"
        --      ...
        -- }
        --
        -- Here we need to check for signal width of the elements of AliasBundle
        if type(params) == "table" then
            for _, sig_info in pairs(params) do
                if type(sig_info) == "table" then
                    ---@cast sig_info verilua.TypeExpect.expect_abdl.params
                    if not sig_info.name and not sig_info.names then
                        texpect_error(string.format("  params item must have `name` or `names` field"))
                    end

                    ---@type verilua.handles.CallableHDL
                    local first_sig
                    ---@type string
                    local first_sig_name

                    local sig_names = sig_info.names or { sig_info.name }
                    for _, sig_name in ipairs(sig_names) do
                        local sig = value[sig_name]
                        if not first_sig then
                            first_sig = sig
                            first_sig_name = sig_name
                        end

                        texpect.expect_chdl(sig, sig_name) -- Each element of AliasBundle must be a CallableHDL

                        ---@diagnostic disable-next-line: access-invisible
                        if first_sig.hdl ~= sig.hdl then
                            -- Check if signals are fake_chdl
                            local first_is_fake = first_sig.name:find(FAKE_CHDL_NAME_PREFIX) ~= nil
                            local sig_is_fake = sig.name:find(FAKE_CHDL_NAME_PREFIX) ~= nil

                            local fake_info = ""
                            if first_is_fake or sig_is_fake then
                                local parts = {}
                                if first_is_fake then
                                    table.insert(parts, string.format("(1) is fake_chdl"))
                                end
                                if sig_is_fake then
                                    table.insert(parts, string.format("(2) is fake_chdl"))
                                end
                                fake_info = "\n  " .. table.concat(parts, ", ")
                            end

                            texpect_error(
                                string.format(
                                    "  signal `%s`(1) and `%s`(2) are not the same signal\n  (1).hierarchy: %s\n  (2).hierarchy: %s\n  names: {%s}%s",
                                    first_sig_name,
                                    sig_name,
                                    first_sig.fullpath,
                                    sig.fullpath,
                                    table.concat(sig_names, ", "),
                                    fake_info
                                )
                            )
                        end

                        if sig_info.width then
                            -- Check if fake_chdl has get_width() method before accessing width constraints
                            local is_fake_chdl = sig.name:find(FAKE_CHDL_NAME_PREFIX) ~= nil
                            if is_fake_chdl and type(rawget(sig, "get_width")) ~= "function" then
                                local error_msg = string.format(
                                    [[
  Argument: %s
  Error: fake_chdl `%s` does not have a `get_width()` method
  Width constraints were specified for this signal in expect_abdl()

  Please implement `get_width()` method for this fake_chdl.

  Example of creating a fake_chdl with get_width():

    local fake_signal = ("your.hierpath"):fake_chdl {
        --
        -- Other methods ...
        --

        get_width = function(self)
            return %d  -- Must match the expected width
        end
    }

  Note: The `get_width()` method is required when calling expect_abdl() with width constraints.
]],
                                    Logger.colorize("`" .. sig_name .. "`", colors.YELLOW),
                                    Logger.colorize(sig.name, colors.RED),
                                    sig_info.width
                                )
                                texpect_error(error_msg)
                            end

                            if sig:get_width() ~= sig_info.width then
                                texpect_error(
                                    string.format(
                                        "  signal `%s`'s width is %d, but expected %d",
                                        sig_name,
                                        sig:get_width(),
                                        sig_info.width
                                    )
                                )
                            end
                        elseif sig_info.width_min and sig_info.width_max then
                            -- Check if fake_chdl has get_width() method before accessing width constraints
                            local is_fake_chdl = sig.name:find(FAKE_CHDL_NAME_PREFIX) ~= nil
                            if is_fake_chdl and type(rawget(sig, "get_width")) ~= "function" then
                                local error_msg = string.format(
                                    [[
  Argument: %s
  Error: fake_chdl `%s` does not have a `get_width()` method
  Width constraints were specified for this signal in expect_abdl()

  Please implement `get_width()` method for this fake_chdl.

  Example of creating a fake_chdl with get_width():

    local fake_signal = ("your.hierpath"):fake_chdl {
        --
        -- Other methods ...
        --

        get_width = function(self)
            return %d  -- Must match the expected width
        end
    }

  Note: The `get_width()` method is required when calling expect_abdl() with width constraints.
]],
                                    Logger.colorize("`" .. sig_name .. "`", colors.YELLOW),
                                    Logger.colorize(sig.name, colors.RED),
                                    sig_info.width_min
                                )
                                texpect_error(error_msg)
                            end

                            local width = sig:get_width()
                            if not (width >= sig_info.width_min and width <= sig_info.width_max) then
                                texpect_error(
                                    string.format(
                                        "  signal `%s`'s width is %d, but expected in range [%d, %d]",
                                        sig_name,
                                        width,
                                        sig_info.width_min,
                                        sig_info.width_max
                                    )
                                )
                            end
                        elseif sig_info.width_min then
                            -- Check if fake_chdl has get_width() method before accessing width constraints
                            local is_fake_chdl = sig.name:find(FAKE_CHDL_NAME_PREFIX) ~= nil
                            if is_fake_chdl and type(rawget(sig, "get_width")) ~= "function" then
                                local error_msg = string.format(
                                    [[
  Argument: %s
  Error: fake_chdl `%s` does not have a `get_width()` method
  Width constraints were specified for this signal in expect_abdl()

  Please implement `get_width()` method for this fake_chdl.

  Example of creating a fake_chdl with get_width():

    local fake_signal = ("your.hierpath"):fake_chdl {
        --
        -- Other methods ...
        --

        get_width = function(self)
            return %d  -- Must match the expected width
        end
    }

  Note: The `get_width()` method is required when calling expect_abdl() with width constraints.
]],
                                    Logger.colorize("`" .. sig_name .. "`", colors.YELLOW),
                                    Logger.colorize(sig.name, colors.RED),
                                    sig_info.width_min
                                )
                                texpect_error(error_msg)
                            end

                            if sig:get_width() < sig_info.width_min then
                                texpect_error(
                                    string.format(
                                        "  signal `%s`'s width is %d, but expected >= %d",
                                        sig_name,
                                        sig:get_width(),
                                        sig_info.width_min
                                    )
                                )
                            end
                        elseif sig_info.width_max then
                            -- Check if fake_chdl has get_width() method before accessing width constraints
                            local is_fake_chdl = sig.name:find(FAKE_CHDL_NAME_PREFIX) ~= nil
                            if is_fake_chdl and type(rawget(sig, "get_width")) ~= "function" then
                                local error_msg = string.format(
                                    [[
  Argument: %s
  Error: fake_chdl `%s` does not have a `get_width()` method
  Width constraints were specified for this signal in expect_abdl()

  Please implement `get_width()` method for this fake_chdl.

  Example of creating a fake_chdl with get_width():

    local fake_signal = ("your.hierpath"):fake_chdl {
        --
        -- Other methods ...
        --

        get_width = function(self)
            return %d  -- Must match the expected width
        end
    }

  Note: The `get_width()` method is required when calling expect_abdl() with width constraints.
]],
                                    Logger.colorize("`" .. sig_name .. "`", colors.YELLOW),
                                    Logger.colorize(sig.name, colors.RED),
                                    sig_info.width_max
                                )
                                texpect_error(error_msg)
                            end

                            if sig:get_width() > sig_info.width_max then
                                texpect_error(
                                    string.format(
                                        "  signal `%s`'s width is %d, but expected <= %d",
                                        sig_name,
                                        sig:get_width(),
                                        sig_info.width_max
                                    )
                                )
                            end
                        end
                    end
                elseif type(sig_info) == "string" then
                    ---@cast sig_info string
                    texpect.expect_chdl(value[sig_info], sig_info) -- Each element of AliasBundle must be a CallableHDL
                else
                    texpect_error(
                        string.format(
                            "  every item in `params` must be a `table` or a `string`, but got a %s",
                            type(sig_info)
                        )
                    )
                end
            end
        end
    end
end

---@param value verilua.utils.LuaDataBase|verilua.utils.LuaDataBase
---@param name string
---@param elements_table string[]
function texpect.expect_database(value, name, elements_table)
    if type(value) ~= "table" or value.__type ~= "LuaDataBase" then
        local received_type = type(value) --[[@as string]]
        if received_type == "table" and value.__type then
            received_type = tostring(value.__type)
        end
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("LuaDataBase", colors.GREEN),
                Logger.colorize(received_type, colors.RED),
                smart_inspect(value)
            )
        )
    else
        assert(type(elements_table) == "table", "[expect_database] elements_table must be a table")

        local elements_table_processed = {}
        for i, s in ipairs(elements_table) do
            elements_table_processed[i] = s:gsub(" ", "")
        end

        ---@diagnostic disable-next-line: access-invisible
        if value.backend and value.backend == "duckdb" then
            for i, s in ipairs(elements_table_processed) do
                elements_table_processed[i] = s:gsub("INTEGER", "BIGINT"):gsub("TEXT", "VARCHAR")
            end
        end

        local value_elements_processed = {}
        for i, s in ipairs(value.elements) do
            value_elements_processed[i] = s:gsub(" ", "")
        end

        local expect = inspect(elements_table_processed)
        local got = inspect(value_elements_processed)
        if got ~= expect then
            texpect_error(
                string.format(
                    "  elements_table is not equal to %s.elements\n  expect => %s\n  got => %s",
                    name,
                    expect,
                    got
                )
            )
        end
    end
end

function texpect.expect_covergroup(value, name)
    if type(value) ~= "table" or value.__type ~= "CoverGroup" then
        local received_type = type(value) --[[@as string]]
        if received_type == "table" and value.__type then
            received_type = tostring(value.__type)
        end
        texpect_error(
            string.format(
                "  Argument: %s\n  Expected: %s\n  Received: %s (value: %s)",
                Logger.colorize("`" .. name .. "`", colors.YELLOW),
                Logger.colorize("CoverGroup", colors.GREEN),
                Logger.colorize(received_type, colors.RED),
                smart_inspect(value)
            )
        )
    end
end

return texpect

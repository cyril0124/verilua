---@diagnostic disable: unnecessary-if, global-in-non-module

local inspect = require "inspect"

local type = type
local pairs = pairs
local assert = assert
local tostring = tostring

local debug_str = _G.debug_str -- provided by init.lua
local f = function(...) return debug_str(string.format(...)) end
local error = function(...)
    print("\n[TypeExpect] " .. debug.traceback())
    error(...)
end

---@class verilua.TypeExpect
local texpect = {}

---@param value string
---@param name string
function texpect.expect_string(value, name)
    if type(value) ~= "string" then
        error(
            f(
                "[expect_string] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "string",
                type(value)
            ),
            0
        )
    end
end

---@param value number
---@param name string
function texpect.expect_number(value, name)
    if type(value) ~= "number" then
        error(
            f(
                "[expect_number] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "number",
                type(value)
            ),
            0
        )
    end
end

---@param value integer
---@param name string
function texpect.expect_integer(value, name)
    if type(value) ~= "number" then
        error(
            f(
                "[expect_integer] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "number",
                type(value)
            ),
            0
        )
    end
end

---@param value boolean
---@param name string
function texpect.expect_boolean(value, name)
    if type(value) ~= "boolean" then
        error(
            f(
                "[expect_boolean] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "boolean",
                type(value)
            ),
            0
        )
    end
end

---@param value table
---@param name string
function texpect.expect_table(value, name)
    if type(value) ~= "table" then
        error(
            f(
                "[expect_table] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "table",
                type(value)
            ),
            0
        )
    end
end

---@param value function
---@param name string
function texpect.expect_function(value, name)
    if type(value) ~= "function" then
        error(
            f(
                "[expect_function] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "function",
                type(value)
            ),
            0
        )
    end
end

---@param value thread
---@param name string
function texpect.expect_thread(value, name)
    if type(value) ~= "thread" then
        error(
            f(
                "[expect_thread] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "thread",
                type(value)
            ),
            0
        )
    end
end

---@param value userdata
---@param name string
function texpect.expect_userdata(value, name)
    if type(value) ~= "userdata" then
        error(
            f(
                "[expect_userdata] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "userdata",
                type(value)
            ),
            0
        )
    end
end

---@param value ffi.cdata*
---@param name string
function texpect.expect_struct(value, name)
    if type(value) ~= "cdata" then
        error(
            f(
                "[expect_struct] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "cdata",
                type(value)
            ),
            0
        )
    end
end

---@param value verilua.handles.CallableHDL
---@param name string
---@param width_or_width_min number?
---@param width_max number?
function texpect.expect_chdl(value, name, width_or_width_min, width_max)
    if type(value) ~= "table" then
        error(
            f(
                "[expect_chdl] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "CallableHDL",
                type(value)
            ),
            0
        )
    else
        if value.__type == nil or value.__type ~= "CallableHDL" then
            error(
                f(
                    "[expect_chdl] Expected argument `%s` to be a `%s` value, but received a `%s` value instead, and it is not a `CallableHDL`, __type => %s",
                    name,
                    "CallableHDL",
                    type(value),
                    tostring(value.__type)
                ),
                0
            )
        end

        if value.__type == "CallableHDL" then
            if width_or_width_min ~= nil and width_max == nil then
                if value:get_width() ~= width_or_width_min then
                    error(
                        f(
                            "[expect_chdl] Expected argument `%s` to be a `%s` value with width %d, but received a `%s` value with width %d instead",
                            name,
                            "CallableHDL",
                            width_or_width_min,
                            type(value),
                            value:get_width()
                        ),
                        0
                    )
                end
            elseif width_or_width_min ~= nil and width_max ~= nil then
                if value:get_width() < width_or_width_min or value:get_width() > width_max then
                    error(
                        f(
                            "[expect_chdl] Expected argument `%s` to be a `%s` value with width >= %d and <= %d, but received a `%s` value with width %d instead",
                            name,
                            "CallableHDL",
                            width_or_width_min,
                            width_max,
                            type(value),
                            value:get_width()
                        ),
                        0
                    )
                end
            end
        end
    end
end

---@param value verilua.handles.Bundle
---@param name string
function texpect.expect_bdl(value, name)
    if type(value) ~= "table" then
        error(
            f(
                "[expect_bdl] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "Bundle",
                type(value)
            ),
            0
        )
    else
        if value.__type == nil or value.__type ~= "Bundle" then
            error(
                f(
                    "[expect_bdl] Expected argument `%s` to be a `%s` value, but received a `%s` value instead, and it is not a `Bundle`, __type => %s",
                    name,
                    "Bundle",
                    type(value),
                    tostring(value.__type)
                ),
                0
            )
        end
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
    if type(value) ~= "table" then
        error(
            f(
                "[expect_abdl] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "AliasBundle",
                type(value)
            ),
            0
        )
    else
        if value.__type == nil or value.__type ~= "AliasBundle" then
            error(
                f(
                    "[expect_abdl] Expected argument `%s` to be a `%s` value, but received a `%s` value instead, and it is not a `AliasBundle`, __type => %s",
                    name,
                    "AliasBundle",
                    type(value),
                    tostring(value.__type)
                ),
                0
            )
        end

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
        if value.__type == "AliasBundle" then
            if type(params) == "table" then
                for _, sig_info in pairs(params) do
                    if type(sig_info) == "table" then
                        ---@cast sig_info verilua.TypeExpect.expect_abdl.params
                        if not sig_info.name and not sig_info.names then
                            error(f("[expect_abdl] params item must have `name` or `names` field"), 0)
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

                            _G.debug_level = 5                 -- Temporary set debug level
                            texpect.expect_chdl(sig, sig_name) -- Each element of AliasBundle must be a CallableHDL
                            _G.debug_level = _G.default_debug_level

                            ---@diagnostic disable-next-line: access-invisible
                            if first_sig.hdl ~= sig.hdl then
                                error(f(
                                    "[expect_abdl] signal `%s`(1) and `%s`(2) are not the same signal, (1).hierarchy: %s, (2).hierarchy: %s, names: {%s}",
                                    first_sig_name,
                                    sig_name,
                                    first_sig.fullpath,
                                    sig.fullpath,
                                    table.concat(sig_names, ", ")
                                ))
                            end

                            if sig_info.width then
                                if sig:get_width() ~= sig_info.width then
                                    error(
                                        f(
                                            "[expect_abdl] signal `%s`'s width is %d, but expected %d",
                                            sig_name,
                                            sig:get_width(),
                                            sig_info.width
                                        ),
                                        0
                                    )
                                end
                            elseif sig_info.width_min and sig_info.width_max then
                                local width = sig:get_width()
                                if not (width >= sig_info.width_min and width <= sig_info.width_max) then
                                    error(
                                        f(
                                            "[expect_abdl] signal `%s`'s width is %d, but expected in range [%d, %d]",
                                            sig_name,
                                            width,
                                            sig_info.width_min,
                                            sig_info.width_max
                                        ),
                                        0
                                    )
                                end
                            elseif sig_info.width_min then
                                if sig:get_width() < sig_info.width_min then
                                    error(
                                        f(
                                            "[expect_abdl] signal `%s`'s width is %d, but expected >= %d",
                                            sig_name,
                                            sig:get_width(),
                                            sig_info.width_min
                                        ),
                                        0
                                    )
                                end
                            elseif sig_info.width_max then
                                if sig:get_width() > sig_info.width_max then
                                    error(
                                        f(
                                            "[expect_abdl] signal `%s`'s width is %d, but expected <= %d",
                                            sig_name,
                                            sig:get_width(),
                                            sig_info.width_max
                                        ),
                                        0
                                    )
                                end
                            end
                        end
                    elseif type(sig_info) == "string" then
                        ---@cast sig_info string
                        _G.debug_level = 5                             -- Temporary set debug level
                        texpect.expect_chdl(value[sig_info], sig_info) -- Each element of AliasBundle must be a CallableHDL
                        _G.debug_level = _G.default_debug_level
                    else
                        error(
                            f(
                                "[expect_abdl] every item in `params` must be a `table` or a `string`, but got a %s",
                                type(sig_info)
                            ),
                            0
                        )
                    end
                end
            end
        end
    end
end

---@param value verilua.utils.LuaDataBase|verilua.utils.LuaDataBase
---@param name string
---@param elements_table string[]
function texpect.expect_database(value, name, elements_table)
    if type(value) ~= "table" then
        error(
            f(
                "[expect_database] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "LuaDataBase",
                type(value)
            ),
            0
        )
    else
        if value.__type == nil or value.__type ~= "LuaDataBase" then
            error(
                f(
                    "[expect_database] Expected argument `%s` to be a `%s` value, but received a `%s` value instead, and it is not a `LuaDataBase`, __type => %s",
                    name,
                    "LuaDataBase",
                    type(value),
                    tostring(value.__type)
                ),
                0
            )
        end

        if value.__type == "LuaDataBase" then
            assert(type(elements_table) == "table", "[expect_database] elements_table must be a table")

            -- Remove trivial space
            for i, s in ipairs(elements_table) do
                elements_table[i] = s:gsub(" ", "")
            end

            ---@diagnostic disable-next-line: access-invisible
            if value.backend and value.backend == "duckdb" then
                for i, s in ipairs(elements_table) do
                    elements_table[i] = s:gsub("INTEGER", "BIGINT"):gsub("TEXT", "VARCHAR")
                end
            end

            local expect = inspect(elements_table)
            local got = inspect(value.elements)
            if got ~= expect then
                error(
                    f(
                        "[expect_database] elements_table is not equal to %s.elements\nexpect => %s\ngot => %s",
                        name,
                        expect,
                        got
                    ),
                    0
                )
            end
        end
    end
end

function texpect.expect_covergroup(value, name)
    if type(value) ~= "table" then
        error(
            f(
                "[expect_covergroup] Expected argument `%s` to be a `%s` value, but received a `%s` value instead",
                name,
                "CoverGroup",
                type(value)
            ),
            0
        )
    else
        if value.__type == nil or value.__type ~= "CoverGroup" then
            error(
                f(
                    "[expect_covergroup] Expected argument `%s` to be a `%s` value, but received a `%s` value instead, and it is not a `CoverGroup`, __type => %s",
                    name,
                    "CoverGroup",
                    type(value),
                    tostring(value.__type)
                ),
                0
            )
        end
    end
end

return texpect

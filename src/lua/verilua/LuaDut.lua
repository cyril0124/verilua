---@diagnostic disable: unnecessary-if, unnecessary-assert, need-check-nil

local vpiml = require "verilua.vpiml.vpiml"
local CallableHDL = require "verilua.handles.LuaCallableHDL"

local BeatWidth = 32

local type = type
local assert = assert
local f = string.format
local tonumber = tonumber
local ffi_string = ffi.string
local table_insert = table.insert
local setmetatable = setmetatable

local HexStr = _G.HexStr
local BinStr = _G.BinStr
local DecStr = _G.DecStr
local await_posedge_hdl = _G.await_posedge_hdl
local await_negedge_hdl = _G.await_negedge_hdl

local set_force_enable = false
local force_path_table = {}

---@class (partial) verilua.handles.ProxyTableHandle
---@field __type "ProxyTableHandle"
---
--- Set value into the signal, the value must be an integer(32-bit value).
--- e.g.
--- ```lua
--- dut.path.to.signal:set(123)
--- ```
---@field set fun(self: verilua.handles.ProxyTableHandle, v: integer)
---
--- Immediately set value into the signal, bypassing any delay.
--- e.g.
--- ```lua
--- dut.path.to.signal:set_imm(123)
--- ```
---@field set_imm fun(self: verilua.handles.ProxyTableHandle, v: integer)
---
--- Randomly set value into the signal.
--- e.g.
--- ```lua
--- dut.path.to.signal:set_shuffled()
--- ```
---@field set_shuffled fun(self: verilua.handles.ProxyTableHandle)
---
--- Freeze the current value of the signal.
--- e.g.
--- ```lua
--- assert(dut.path.to.signal:get() == 123)
--- dut.path.to.signal:set_freeze()
--- -- ...
--- assert(dut.path.to.signal:get() == 123)
--- ```
---@field set_freeze fun(self: verilua.handles.ProxyTableHandle)
---
--- Forcely set value into the signal, the value must be an integer(32-bit value).
--- e.g.
--- ```lua
--- dut.path.to.signal:set_force(123)
--- dut.path.to.signal:set(111) -- this will be ignored
--- -- ...
--- assert(dut.path.to.signal:get() == 123)
--- ```
---@field set_force fun(self: verilua.handles.ProxyTableHandle, v: integer)
---
--- Release the `set_force` operation.
--- e.g.
--- ```lua
--- dut.path.to.signal:set_force(123)
--- assert(dut.path.to.signal:get() == 123)
--- dut.path.to.signal:set_release()
--- -- ...
--- dut.path.to.signal:set(111)
--- -- ...
--- assert(dut.path.to.signal:get() == 111)
--- ```
---@field set_release fun(self: verilua.handles.ProxyTableHandle)
---
--- Enable force mode for all subsequent set operations.
--- e.g.
--- ```lua
--- dut:force_all()
--- dut.cycles:set(1)
--- dut.path.to.signal:set(1)
--- ```
---@field force_all fun(self: verilua.handles.ProxyTableHandle)
---
--- Release all forced signals, disabling force mode.
--- e.g.
--- ```lua
--- dut:force_all()
--- dut.clock:posedge()
--- dut:release_all()
--- ```
---@field release_all fun(self: verilua.handles.ProxyTableHandle)
---
--- Execute a code block where all set operations are treated as force operations.
--- Automatically releases forced signals after execution.
--- e.g.
--- ```lua
--- dut:force_region(function()
---     dut.clock:negedge()
---     dut.cycles:set(1)
--- end)
--- ```
---@field force_region fun(self: verilua.handles.ProxyTableHandle, code_func: fun())
---
--- Get the current value of the signal as an integer.
--- e.g.
--- ```lua
--- local value = dut.cycles:get()
--- ```
---@field get fun(self: verilua.handles.ProxyTableHandle): integer
---
--- Get the signal value as a formatted string (hex, binary, or decimal).
--- e.g.
--- ```lua
--- local bin_str = dut.cycles:get_str(BinStr)
--- local dec_str = dut.cycles:get_str(DecStr)
--- local hex_str = dut.cycles:get_str(HexStr)
--- ```
---@field get_str fun(self: verilua.handles.ProxyTableHandle, fmt: integer): string
---
--- Get the signal value as a hexadecimal string.
--- e.g.
--- ```lua
--- local hex_str = dut.cycles:get_hex_str()
--- assert(hex_str == "123")
--- ```
---@field get_hex_str fun(self: verilua.handles.ProxyTableHandle): string
---
--- Set the signal value using a string (hex or binary with prefix).
--- e.g.
--- ```lua
--- dut.cycles:set_str("0x123")    -- for hex string
--- dut.cycles:set_str("0b101010") -- for binary string
--- ```
---@field set_str fun(self: verilua.handles.ProxyTableHandle, str: string)
---
--- Set the signal value using a hexadecimal string (no prefix required).
--- e.g.
--- ```lua
--- dut.cycles:set_hex_str("123")
--- ```
---@field set_hex_str fun(self: verilua.handles.ProxyTableHandle, str: string)
---
--- Forcefully set the signal value using a string.
--- e.g.
--- ```lua
--- dut.cycles:set_force_str("0x123")
--- ```
---@field set_force_str fun(self: verilua.handles.ProxyTableHandle, str: string)
---
--- Wait for positive edge(s) on the signal, optionally executing a callback.
--- e.g.
--- ```lua
--- dut.clock:posedge()
--- dut.reset:posedge(10)
--- dut.clock:posedge(10, function(c) print("current count is " .. c) end)
--- ```
---@field posedge fun(self: verilua.handles.ProxyTableHandle, v?: integer, func?: fun(c: integer))
---
--- Wait for negative edge(s) on the signal, optionally executing a callback.
--- e.g.
--- ```lua
--- dut.clock:negedge()
--- dut.reset:negedge(10)
--- dut.clock:negedge(10, function(c) print("current count is " .. c) end)
--- ```
---@field negedge fun(self: verilua.handles.ProxyTableHandle, v?: integer, func?: fun(c: integer))
---
--- Wait for positive edges until a condition is met or max limit is reached.
--- e.g.
--- ```lua
--- local condition_met = dut.clock:posedge_until(100, function(c)
---     return dut.cycles:get() >= 100
--- end)
--- ```
---@field posedge_until fun(self: verilua.handles.ProxyTableHandle, max_limit: integer, func: fun(c: integer): boolean): boolean
---
--- Wait for negative edges until a condition is met or max limit is reached.
--- e.g.
--- ```lua
--- local condition_met = dut.clock:negedge_until(100, function(c)
---     return dut.cycles:get() >= 100
--- end)
--- ```
---@field negedge_until fun(self: verilua.handles.ProxyTableHandle, max_limit: integer, func: fun(c: integer): boolean): boolean
---
--- Get the raw handle(ComplexHandleRaw) for the signal.
--- e.g.
--- ```lua
--- local hdl = dut.cycles:hdl()
--- ```
---@field hdl fun(self: verilua.handles.ProxyTableHandle): verilua.handles.ComplexHandleRaw
---
--- Get a CallableHDL for the signal.
--- e.g.
--- ```lua
--- local cycles_chdl = dut.cycles:chdl()
--- print("value of cycles is " .. cycles_chdl:get())
--- cycles_chdl:set(123)
--- ```
---@field chdl fun(self: verilua.handles.ProxyTableHandle): verilua.handles.CallableHDL
---
--- Get the full path name of the signal.
--- e.g.
--- ```lua
--- local path = dut.path.to.signal:name()
--- assert(path == "tb_top.path.to.signal")
--- ```
---@field name fun(self: verilua.handles.ProxyTableHandle): string
---
--- Get the bit width of the signal.
--- e.g.
--- ```lua
--- local width = dut.cycles:get_width()
--- assert(width == 64)
--- ```
---@field get_width fun(self: verilua.handles.ProxyTableHandle): integer
---
--- Get a string representation of the signal value with its path.
--- e.g.
--- ```lua
--- local str = dut.path.to.signal:dump_str()
--- -- Returns: "[tb_top.path.to.signal] => 0x1234"
--- ```
---@field dump_str fun(self: verilua.handles.ProxyTableHandle): string
---
--- Print the signal value with its path.
--- e.g.
--- ```lua
--- dut.path.to.signal:dump()
--- -- Prints: [tb_top.path.to.signal] => 0x1234
--- ```
---@field dump fun(self: verilua.handles.ProxyTableHandle)
---
--- Assert that the signal value equals the specified value.
--- e.g.
--- ```lua
--- dut.path.to.signal:expect(1)
--- ```
---@field expect fun(self: verilua.handles.ProxyTableHandle, value: integer)
---
--- Assert that the signal value does not equal the specified value.
--- e.g.
--- ```lua
--- dut.path.to.signal:expect_not(1)
--- ```
---@field expect_not fun(self: verilua.handles.ProxyTableHandle, value: integer)
---
--- Assert that the signal value matches the specified hexadecimal string.
--- e.g.
--- ```lua
--- dut.path.to.signal:expect_hex_str("1234abc")
--- ```
---@field expect_hex_str fun(self: verilua.handles.ProxyTableHandle, hex_value_str: string)
---
--- Assert that the signal value matches the specified binary string.
--- e.g.
--- ```lua
--- dut.path.to.signal:expect_bin_str("10101010")
--- ```
---@field expect_bin_str fun(self: verilua.handles.ProxyTableHandle, bin_value_str: string)
---
--- Assert that the signal value matches the specified decimal string.
--- e.g.
--- ```lua
--- dut.path.to.signal:expect_dec_str("1234")
--- ```
---@field expect_dec_str fun(self: verilua.handles.ProxyTableHandle, dec_value_str: string)
---
--- Assert that the signal value does not match the specified hexadecimal string.
--- e.g.
--- ```lua
--- dut.path.to.signal:expect_not_hex_str("1234abc")
--- ```
---@field expect_not_hex_str fun(self: verilua.handles.ProxyTableHandle, hex_value_str: string)
---
--- Assert that the signal value does not match the specified binary string.
--- e.g.
--- ```lua
--- dut.path.to.signal:expect_not_bin_str("10101010")
--- ```
---@field expect_not_bin_str fun(self: verilua.handles.ProxyTableHandle, bin_value_str: string)
---
--- Assert that the signal value does not match the specified decimal string.
--- e.g.
--- ```lua
--- dut.path.to.signal:expect_not_dec_str("1234")
--- ```
---@field expect_not_dec_str fun(self: verilua.handles.ProxyTableHandle, dec_value_str: string)
---
--- TODO:
---@field _if fun(self: verilua.handles.ProxyTableHandle, condition: fun(): boolean): verilua.handles.ProxyTableHandle
---
--- Check if the signal value equals the specified value.
--- e.g.
--- ```lua
--- assert(dut.path.to.signal:is(1))
--- ```
---@field is fun(self: verilua.handles.ProxyTableHandle, value: integer): boolean
---
--- Check if the signal value does not equal the specified value.
--- e.g.
--- ```lua
--- assert(dut.path.to.signal:is_not(1))
--- ```
---@field is_not fun(self: verilua.handles.ProxyTableHandle, value: integer): boolean
---
--- Check if the signal value matches the specified hexadecimal string.
--- e.g.
--- ```lua
--- assert(dut.path.to.signal:is_hex_str("abcd"))
--- ```
---@field is_hex_str fun(self: verilua.handles.ProxyTableHandle, hex_value_str: string): boolean
---
--- Check if the signal value matches the specified binary string.
--- e.g.
--- ```lua
--- assert(dut.path.to.signal:is_bin_str("10101010"))
--- ```
---@field is_bin_str fun(self: verilua.handles.ProxyTableHandle, bin_value_str: string): boolean
---
--- Check if the signal value matches the specified decimal string.
--- e.g.
--- ```lua
--- assert(dut.path.to.signal:is_dec_str("1234"))
--- ```
---@field is_dec_str fun(self: verilua.handles.ProxyTableHandle, dec_value_str: string): boolean
---
--- --- Get the string representation of the signal's path.
--- e.g.
--- ```lua
--- assert(dut.path.to.signal:tostring() == "tb_top.path.to.signal")
--- ```
---@field tostring fun(self: verilua.handles.ProxyTableHandle): string
---
--- Create a new proxy with a prefixed path.
--- e.g.
--- ```lua
--- local io_in = dut.path.to.mod:with_prefix("io_in_")
--- assert(io_in.value:tostring() == "top.path.to.mod.io_in_value")
--- ```
---@field with_prefix fun(self: verilua.handles.ProxyTableHandle, prefix_str: string): verilua.handles.ProxyTableHandle
---
--- Automatically create a `Bundle` by filtering signals in the design based on specified criteria.
--- The `params` table can contain the following fields:
--- - `startswith` (string, optional): Only include signals that start with this prefix.
--- - `endswith` (string, optional): Only include signals that end with this suffix
--- - `matches` (string, optional): A Lua pattern to match signal names.
--- - `wildmatch` (string, optional): A wildcard pattern (using `*`) to match signal names.
--- - `filter` (function, optional): A custom filter function that takes a signal name and width as arguments and returns a boolean.
--- - `prefix` (string, optional): A prefix to add to each signal name in the bundle.
--- The `params` table must contain at least one of the filtering criteria (`startswith`, `endswith`, `matches`, `wildmatch`, or `filter`).
--- e.g.
--- ```lua
---      local bdl = dut.path.to.mod:auto_bundle { startswith = "io_in_", endswith = "_value" }
---      local bdl = dut.path.to.mod:auto_bundle { startswith = "io_in_" }
---      local bdl = dut.path.to.mod:auto_bundle { endswith = "_value" }
---      local bdl = dut.path.to.mod:auto_bundle { matches = "^io_" }
---      local bdl = dut.path.to.mod:auto_bundle { wildmatch = "*_value_*" }
---      local bdl = dut.path.to.mod:auto_bundle { filter = function (name, width)
---          return width == 32 and name:endswith("_value")
---      end }
--- ```
---
--- Priority:
---      filter > matches > wildmatch > startswith > prefix > endswith
--- Available combinations:
---      - matches + filter
---      - wildmatch + filter
---      - wildmatch + filter + prefix
---      - startswith + endswith
---      - startswith + endswith + filter
---      - prefix + filter
---      - startswith + filter
---      - endswith + filter
---@field auto_bundle fun(self, params: verilua.utils.SignalDB.auto_bundle.params): verilua.handles.Bundle
---
---@overload fun(v: "integer"|"hex"|"name"|"hdl"): integer|string|verilua.handles.ComplexHandleRaw `__call` metamethod, deprecated
---@field [string] verilua.handles.ProxyTableHandle

---@type table<string, verilua.handles.ProxyTableHandle>
local proxy_handle_cache = {}

---@param path string
---@param use_prefix? boolean
---@return verilua.handles.ProxyTableHandle
local function create_proxy(path, use_prefix)
    local local_path = path
    use_prefix = use_prefix or false

    if not use_prefix then
        if proxy_handle_cache[local_path] ~= nil then
            return proxy_handle_cache[local_path]
        end
    end

    ---@type verilua.handles.ProxyTableHandle
    local mt = setmetatable({
        __type = "ProxyTableHandle",
        get_local_path = function(this) return local_path end,

        set = function(t, v)
            assert(v ~= nil)
            if set_force_enable then
                table_insert(force_path_table, local_path)
                vpiml.vpiml_force_value(vpiml.vpiml_handle_by_name(local_path), tonumber(v) --[[@as integer]])
            else
                vpiml.vpiml_set_value(vpiml.vpiml_handle_by_name(local_path), tonumber(v) --[[@as integer]])
            end
        end,

        set_imm = function(t, v)
            assert(v ~= nil)
            if set_force_enable then
                table_insert(force_path_table, local_path)
                vpiml.vpiml_force_imm_value(vpiml.vpiml_handle_by_name(local_path), tonumber(v) --[[@as integer]])
            else
                vpiml.vpiml_set_imm_value(vpiml.vpiml_handle_by_name(local_path), tonumber(v) --[[@as integer]])
            end
        end,


        set_shuffled = function(t)
            vpiml.vpiml_set_shuffled(vpiml.vpiml_handle_by_name(local_path))
        end,
        set_freeze = function(t)
            vpiml.vpiml_set_freeze(vpiml.vpiml_handle_by_name(local_path))
        end,

        set_force = function(t, v)
            assert(v ~= nil)
            if set_force_enable then
                table_insert(force_path_table, local_path)
            end
            vpiml.vpiml_force_value(vpiml.vpiml_handle_by_name(local_path), tonumber(v) --[[@as integer]])
        end,
        set_imm_force = function(t, v)
            assert(v ~= nil)
            if set_force_enable then
                table_insert(force_path_table, local_path)
            end
            vpiml.vpiml_force_imm_value(vpiml.vpiml_handle_by_name(local_path), tonumber(v) --[[@as integer]])
        end,
        set_release = function(t)
            vpiml.vpiml_release_value(vpiml.vpiml_handle_by_name(local_path))
        end,

        force_all = function(t)
            assert(set_force_enable == false)
            set_force_enable = true
        end,
        release_all = function(t)
            assert(set_force_enable == true)
            set_force_enable = false

            for i, _path in ipairs(force_path_table) do
                vpiml.vpiml_release_value(vpiml.vpiml_handle_by_name(_path))
            end
        end,

        force_region = function(t, code_func)
            assert(type(code_func) == "function")
            t:force_all()
            code_func()
            t:release_all()
        end,

        get = function(t)
            return tonumber(vpiml.vpiml_get_value(vpiml.vpiml_handle_by_name(local_path)))
        end,

        get_str = function(t, fmt)
            local hdl = vpiml.vpiml_handle_by_name_safe(local_path)
            if hdl == -1 then
                assert(false, f("No handle found => %s", local_path))
            end
            return ffi_string(vpiml.vpiml_get_value_str(hdl, fmt))
        end,

        get_hex_str = function(t)
            local hdl = vpiml.vpiml_handle_by_name_safe(local_path)
            if hdl == -1 then
                assert(false, f("No handle found => %s", local_path))
            end
            return ffi_string(vpiml.vpiml_get_value_str(hdl, HexStr))
        end,

        set_str = function(t, str)
            if set_force_enable then
                table_insert(force_path_table, local_path)
                vpiml.vpiml_force_value(vpiml.vpiml_handle_by_name(local_path), tonumber(str) --[[@as integer]])
            else
                vpiml.vpiml_set_value(vpiml.vpiml_handle_by_name(local_path), tonumber(str) --[[@as integer]])
            end
        end,

        set_hex_str = function(t, str)
            if set_force_enable then
                table_insert(force_path_table, local_path)
                vpiml.vpiml_force_value_str(vpiml.vpiml_handle_by_name(local_path), "0x" .. str)
            else
                vpiml.vpiml_set_value_str(vpiml.vpiml_handle_by_name(local_path), "0x" .. str)
            end
        end,

        set_force_str = function(t, str)
            vpiml.vpiml_force_value_str(vpiml.vpiml_handle_by_name(local_path), str)
        end,

        posedge = function(t, v, func)
            local _v = v or 1
            local _v_type = type(_v)

            assert(_v_type == "number")

            local do_func = false
            if func ~= nil then
                assert(type(func) == "function")
                do_func = true
            end

            for i = 1, _v do
                if do_func then
                    func(i)
                end
                await_posedge_hdl(vpiml.vpiml_handle_by_name(local_path))
            end
        end,
        negedge = function(t, v, func)
            local _v = v or 1
            local _v_type = type(_v)

            assert(_v_type == "number")
            assert(_v >= 1)

            local do_func = false
            if func ~= nil then
                assert(type(func) == "function")
                do_func = true
            end

            for i = 1, _v do
                if do_func then
                    func(i)
                end
                await_negedge_hdl(vpiml.vpiml_handle_by_name(local_path))
            end
        end,

        posedge_until = function(t, max_limit, func)
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
                    await_posedge_hdl(vpiml.vpiml_handle_by_name(local_path))
                else
                    break
                end
            end

            return condition_meet
        end,
        negedge_until = function(t, max_limit, func)
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
                    await_negedge_hdl(vpiml.vpiml_handle_by_name(local_path))
                else
                    break
                end
            end

            return condition_meet
        end,

        hdl = function(t)
            local hdl = vpiml.vpiml_handle_by_name_safe(local_path)
            if hdl == -1 then
                assert(false, f("No handle found => %s", local_path))
            end
            return hdl
        end,


        chdl = function(t)
            return CallableHDL(local_path, "")
        end,


        name = function(t)
            return local_path
        end,


        get_width = function(t)
            return tonumber(vpiml.vpiml_get_signal_width(vpiml.vpiml_handle_by_name(local_path)))
        end,

        dump_str = function(t)
            local hdl = vpiml.vpiml_handle_by_name(local_path)
            local s = f("[%s] => ", local_path)
            s = s .. "0x" .. ffi_string(vpiml.vpiml_get_value_hex_str(hdl))
            return s
        end,


        dump = function(t)
            print(t:dump_str())
        end,


        expect = function(t, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")

            local beat_num = t:get_width() / BeatWidth
            if beat_num > 2 then
                assert(false,
                    "`dut.<path>:expect(value)` can only be used for hdl with 1 or 2 beat, use `dut.<path>:expect_[hex/bin/dec]_str(value_str)` instead! beat_num => " ..
                    beat_num)
            end

            if t:get() ~= value then
                assert(false, f("[%s] expect => %d, but got => %d", local_path, value, t:get()))
            end
        end,

        expect_not = function(t, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")

            local beat_num = t:get_width() / BeatWidth
            if beat_num > 2 then
                assert(
                    false,
                    "`dut.<path>:expect_not(value)` can only be used for hdl with 1 or 2 beat, use `dut.<path>:expect_not_[hex/bin/dec]_str(value_str)` instead! beat_num => " ..
                    beat_num
                )
            end

            if t:get() == value then
                assert(false, f("[%s] expect not => %d, but got => %d", local_path, value, t:get()))
            end
        end,

        expect_hex_str = function(this, hex_value_str)
            assert(type(hex_value_str) == "string")
            local left = this:get_hex_str():lower():gsub("^0*", "")
            local right = hex_value_str:lower():gsub("^0*", "")
            if left ~= right then
                assert(false, f("[%s] expect => %s, but got => %s", local_path, right, left))
            end
        end,

        expect_bin_str = function(this, bin_value_str)
            assert(type(bin_value_str) == "string")
            if this:get_str(BinStr):gsub("^0*", "") ~= bin_value_str:gsub("^0*") then
                assert(false, f("[%s] expect => %s, but got => %s", local_path, bin_value_str, this:get_str(BinStr)))
            end
        end,

        expect_dec_str = function(this, dec_value_str)
            assert(type(dec_value_str) == "string")
            if this:get_str(DecStr):gsub("^0*", "") ~= dec_value_str:gsub("^0*", "") then
                assert(false, f("[%s] expect => %s, but got => %s", local_path, dec_value_str, this:get_str(DecStr)))
            end
        end,

        expect_not_hex_str = function(this, hex_value_str)
            assert(type(hex_value_str) == "string")
            if this:get_hex_str():lower():gsub("^0*", "") == hex_value_str:lower():gsub("^0*", "") then
                assert(false, f("[%s] expect not => %s, but got => %s", local_path, hex_value_str, this:get_str(HexStr)))
            end
        end,

        expect_not_bin_str = function(this, bin_value_str)
            assert(type(bin_value_str) == "string")
            if this:get_str(BinStr):gsub("^0*", "") == bin_value_str:gsub("^0*") then
                assert(false, f("[%s] expect not => %s, but got => %s", local_path, bin_value_str, this:get_str(BinStr)))
            end
        end,

        expect_not_dec_str = function(this, dec_value_str)
            assert(type(dec_value_str) == "string")
            if this:get_str(DecStr):gsub("^0*", "") == dec_value_str:gsub("^0*", "") then
                assert(false, f("[%s] expect not => %s, but got => %s", local_path, dec_value_str, this:get_str(DecStr)))
            end
        end,

        _if = function(t, condition)
            local _condition = false
            if type(condition) == "boolean" then
                _condition = condition
            elseif type(condition) == "function" then
                _condition = condition()

                local _condition_type = type(_condition)
                if _condition_type ~= "boolean" then
                    assert(false, "invalid condition function return type: " .. _condition_type)
                end
            else
                assert(false, "invalid condition type: " .. type(condition))
            end

            if _condition then
                return t
            else
                return setmetatable({}, {
                    __index = function(_t, k)
                        return function()
                            -- an empty function
                        end
                    end
                })
            end
        end,


        is = function(t, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")

            return t:get() == value
        end,
        is_not = function(t, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")

            return t:get() ~= value
        end,

        is_hex_str = function(t, hex_value_str)
            return t:get_hex_str():lower():gsub("^0*", "") == hex_value_str:lower():gsub("^0*", "")
        end,

        is_bin_str = function(t, bin_value_str)
            return t:get_str(BinStr):gsub("^0*", "") == bin_value_str:gsub("^0*")
        end,

        is_dec_str = function(t, dec_value_str)
            return t:get_str(DecStr):gsub("^0*", "") == dec_value_str:gsub("^0*", "")
        end,

        tostring = function(t)
            return local_path
        end,


        with_prefix = function(t, prefix_str)
            return create_proxy(local_path .. '.' .. prefix_str, true)
        end,

        auto_bundle = function(t, params)
            return require("verilua.utils.SignalDB"):auto_bundle(local_path, params)
        end
    }, {
        __index = function(t, k)
            ---@diagnostic disable-next-line: unnecessary-if
            if not use_prefix then
                return create_proxy(local_path .. '.' .. k, false)
            else
                return create_proxy(local_path .. k, false)
            end
        end,

        --
        -- [Deprecated] please use <LuaDut>:set(...) or <LuaDut>:set_str(...)
        --
        __newindex = function(t, k, v)
            local fullpath = local_path .. '.' .. k
            -- print('assign ' .. v .. ' to ' .. fullpath .. "  " .. local_path) -- debug info
            vpiml.vpiml_set_imm_value(vpiml.vpiml_handle_by_name(fullpath), v)
        end,

        --
        -- [Deprecated] please use <LuaDut>:get(...) or <LuaDut>:get_str(...)
        --
        __call = function(t, v)
            local data_type = v or "integer"
            if data_type == "integer" then
                return tonumber(vpiml.vpiml_get_value(vpiml.vpiml_handle_by_name(local_path)))
            elseif data_type == "hex" then
                local val = tonumber(vpiml.vpiml_get_value(vpiml.vpiml_handle_by_name(local_path)))
                return f("0x%x", val)
            elseif data_type == "name" then
                return local_path
            elseif data_type == "hdl" then
                return vpiml.vpiml_handle_by_name(local_path)
            else
                assert(false, "invalid data type: " .. data_type)
            end
        end,

        __tostring = function()
            return local_path
        end
    })

    if not use_prefix then
        proxy_handle_cache[local_path] = mt
    end

    return mt
end


return {
    create_proxy = create_proxy
}

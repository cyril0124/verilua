local vpiml = require "vpiml"
local class = require "pl.class"
local tablex = require "pl.tablex"
local texpect = require "TypeExpect"
local table_new = require "table.new"
local table_clear = require "table.clear"
local CallableHDL = require "verilua.handles.LuaCallableHDL"

local assert = assert
local rawset = rawset
local ipairs = ipairs
local f = string.format
local table_concat = table.concat
local table_insert = table.insert

local verilua_debug = _G.verilua_debug

---@class (exact) Bundle
---@field __type string
---@field signals_table table<string>
---@field prefix string
---@field hierarchy string
---@field name string
---@field is_decoupled boolean
---@field bits table<string, CallableHDL>
---@field valid CallableHDL
---@field ready CallableHDL
---@field fire fun(self: Bundle): boolean
---@field get_all fun(self: Bundle): table<number|MultiBeatData>
---@field set_all fun(self: Bundle, values_tbl: table<number|MultiBeatData>)
---@field private __dump_parts table<string>
---@field dump_str fun(self: Bundle): string
---@field format_dump_str fun(self: Bundle, format_func: fun(chdl: CallableHDL, name: string): string): string
---@field dump fun(self: Bundle)
---@field format_dump fun(self: Bundle, format_func: fun(chdl: CallableHDL, name: string): string)
---@field [string] CallableHDL
local Bundle = class()

function Bundle:_init(signals_table, prefix, hierarchy, name, is_decoupled, optional_signals)
    texpect.expect_table(signals_table, "signals_table")
    texpect.expect_string(prefix, "prefix")
    texpect.expect_string(hierarchy, "hierarchy")
    
    self.__type = "Bundle"
    self.signals_table = signals_table
    self.prefix = prefix
    self.hierarchy = hierarchy
    self.name = name or "Unknown"
    self.is_decoupled = is_decoupled or false

    local valid_index = tablex.find(signals_table, "valid")
    if optional_signals then
        texpect.expect_table(optional_signals, "optional_signals")
    end
    local optional_signals = optional_signals or {} -- optional signals are allowed to be empty


    if is_decoupled == true then
        assert(valid_index ~= nil, "Decoupled Bundle should contains a valid signal!")
        assert(prefix ~= nil, "prefix is required for decoupled bundle!")
    end

    verilua_debug("New Bundle => ", "name: " .. self.name, "signals: {" .. table_concat(signals_table, ", ") .. "}", "prefix: " .. prefix, "hierarchy: ", hierarchy)

    if is_decoupled == true then
        self.bits = {}

        for _, signal in ipairs(signals_table) do
            if signal == "valid" or signal == "ready" then
                local fullpath = hierarchy .. "." .. prefix .. signal

                if not tablex.find(optional_signals, signal) then
                    rawset(self, signal, CallableHDL(fullpath, signal))
                else
                    local hdl = vpiml.vpiml_handle_by_name_safe(fullpath)
                    if hdl ~= -1 then
                        -- optional are allowed to be empty
                        rawset(self, signal, CallableHDL(fullpath, signal, hdl))
                    end
                end
            else
                local fullpath = hierarchy .. "." .. prefix .. "bits_" ..  signal
                if not tablex.find(optional_signals, signal) then
                    rawset(self.bits, signal, CallableHDL(fullpath, signal))
                else
                    local hdl = vpiml.vpiml_handle_by_name_safe(fullpath)
                    if hdl ~= -1 then
                        -- optional are allowed to be empty
                        rawset(self.bits, signal, CallableHDL(fullpath, signal, hdl))
                    end
                end
            end
        end
    else
        self.signals_table = {}

        for _, signal in ipairs(signals_table) do
            local fullpath
            if prefix ~= nil then
                fullpath = hierarchy .. "." .. prefix .. signal
            else
                fullpath = hierarchy .. "." .. signal
            end

            rawset(self, signal, CallableHDL(fullpath, signal))
            table_insert(self.signals_table, signal)
        end
    end

    if self.valid == nil then
        self.fire = function (this)
            ---@diagnostic disable-next-line: missing-return
            assert(false, "[" .. self.name .. "] has not valid filed in this bundle!")
        end
    else
        if self.ready == nil then
            self.fire = function (this)
                return this.valid:get() == 1
            end
        else
            self.fire = function (this)
                return (this.valid:get() == 1) and (this.ready:get() == 1)
            end
        end
    end

    if not self.is_decoupled then
        self.get_all = function (this)
            local ret = {}
            for i, sig in ipairs(this.signals_table) do
                table_insert(ret, this[sig]:get())
            end
            return ret
        end

        self.set_all = function (this, values_tbl)
            for i, sig in ipairs(this.signals_table) do
                self[sig]:set(values_tbl[i])
            end
        end
    else
        self.get_all = function (this)
            ---@diagnostic disable-next-line: missing-return
            assert(false, "TODO: is_decoupled")
        end

        self.set_all = function (this, values_tbl)
            assert(false, "TODO: is_decoupled")
        end
    end

    -- Used for saving dump parts
    self.__dump_parts = table_new(#self.signals_table, 0)

    if self.is_decoupled then 
        self.dump_str = function (this)
            local parts = this.__dump_parts
            table_clear(parts)

            if this.name ~= "Unknown" then
                table_insert(parts, f("[%s]", this.name))
            end

            table_insert(parts, "valid: " .. this.valid:get())

            if this.ready ~= nil then
                table_insert(parts, "ready: " .. this.ready:get())
            end

            for i, signal in ipairs(this.signals_table) do
                if signal ~= "valid" and signal ~= "ready" then
                    table_insert(parts, f("%s: 0x%s", signal, this.bits[signal]:get_hex_str()))
                end
            end

            return table_concat(parts, " | ")
        end

        self.format_dump_str = function (this, format_func)
            local parts = this.__dump_parts
            table_clear(parts)

            if this.name ~= "Unknown" then
                table_insert(parts, f("[%s]", this.name))
            end

            table_insert(parts, format_func(this.valid, "valid") or ("valid: " .. this.valid:get()))

            if this.ready ~= nil then
                table_insert(parts, format_func(this.ready, "ready") or ("ready: " .. this.ready:get()))
            end

            for i, signal in ipairs(this.signals_table) do
                if signal ~= "valid" and signal ~= "ready" then
                    table_insert(parts, format_func(this.bits[signal], signal) or f("%s: 0x%s", signal, this.bits[signal]:get_hex_str()))
                end
            end

            return table_concat(parts, " | ")
        end
    else
        self.dump_str = function (this)
            local parts = this.__dump_parts
            table_clear(parts)

            if this.name ~= "Unknown" then
                table_insert(parts, f("[%s] ", this.name))
            end

            if this.valid ~= nil then
                table_insert(parts, "valid: " .. this.valid:get())
            end

            if this.ready ~= nil then
                table_insert(parts, "ready: " .. this.ready:get())
            end

            for i, signal in ipairs(this.signals_table) do
                if signal ~= "valid" and signal ~= "ready" then
                    table_insert(parts, f("%s: 0x%s", signal, this[signal]:get_hex_str()))
                end
            end

            return table_concat(parts, " | ")
        end

        self.format_dump_str = function (this, format_func)
            local parts = this.__dump_parts
            table_clear(parts)

            if this.name ~= "Unknown" then
                table_insert(parts, f("[%s] ", this.name))
            end

            if this.valid ~= nil then
                table_insert(parts, format_func(this.valid, "valid") or ("valid: " .. this.valid:get()))
            end

            if this.ready ~= nil then
                table_insert(parts, format_func(this.ready, "ready") or ("ready: " .. this.ready:get()))
            end

            for i, signal in ipairs(this.signals_table) do
                if signal ~= "valid" and signal ~= "ready" then
                    table_insert(parts, format_func(this[signal], signal) or f("%s: 0x%s", signal, this[signal]:get_hex_str()))
                end
            end

            return table_concat(parts, " | ")
        end
    end

    self.dump = function (this)
        print(this:dump_str())
    end

    ---@param format_func fun(chdl, name: string): string
    self.format_dump = function (this, format_func)
       print(this:format_dump_str(format_func))
    end
end

function Bundle:__tostring()
    return f("<[Bundle] name: %s, signals: {%s}, hierarchy: %s>", self.name, table_concat(self.signals_table, ", "), self.hierarchy)
end

return Bundle

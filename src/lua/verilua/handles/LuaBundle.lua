local ffi = require "ffi"
local class = require "pl.class"
local tablex = require "pl.tablex"
local texpect = require "TypeExpect"
local CallableHDL = require "verilua.handles.LuaCallableHDL"

local C = ffi.C
local print = print
local assert = assert
local rawset = rawset
local ipairs = ipairs
local f = string.format
local table_concat = table.concat
local table_insert = table.insert

local verilua_debug = _G.verilua_debug
local HexStr = _G.HexStr

local Bundle = class()

ffi.cdef[[
  long long vpiml_handle_by_name_safe(const char* name);
]]

function Bundle:_init(signals_table, prefix, hierachy, name, is_decoupled, optional_signals)
    texpect.expect_table(signals_table, "signals_table")
    texpect.expect_string(prefix, "prefix")
    texpect.expect_string(hierachy, "hierachy")
    
    self.__type = "Bundle"
    self.signals_table = signals_table
    self.prefix = prefix
    self.hierachy = hierachy
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

    verilua_debug("New Bundle => ", "name: " .. self.name, "signals: {" .. table_concat(signals_table, ", ") .. "}", "prefix: " .. prefix, "hierachy: ", hierachy)
    
    if is_decoupled == true then
        self.bits = {}

        for _, signal in ipairs(signals_table) do
            if signal == "valid" or signal == "ready" then
                local fullpath = hierachy .. "." .. prefix .. signal

                if not tablex.find(optional_signals, signal) then
                    rawset(self, signal, CallableHDL(fullpath, signal))
                else
                    local hdl = C.vpiml_handle_by_name_safe(fullpath)
                    if hdl ~= -1 then
                        -- optional are allowed to be empty
                        rawset(self, signal, CallableHDL(fullpath, signal, hdl))
                    end
                end
            else
                local fullpath = hierachy .. "." .. prefix .. "bits_" ..  signal
                if not tablex.find(optional_signals, signal) then
                    rawset(self.bits, signal, CallableHDL(fullpath, signal))
                else
                    local hdl = C.vpiml_handle_by_name_safe(fullpath)
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
                fullpath = hierachy .. "." .. prefix .. signal
            else
                fullpath = hierachy .. "." .. signal
            end

            rawset(self, signal, CallableHDL(fullpath, signal))
            table_insert(self.signals_table, signal)
        end
    end

    if self.valid == nil then
        self.fire = function (this)
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
            assert(false, "TODO: is_decoupled")
        end

        self.set_all = function (this, values_tbl)
            assert(false, "TODO: is_decoupled")
        end
    end

    if self.is_decoupled then 
        self.dump_str = function (this)
            local s = ""

            if this.name ~= "Unknown" then
                s = s .. f("[%s] ", this.name)
            end
            
            s = s .. "| valid: " .. this.valid:get()

            if this.ready ~= nil then
                s = s .. "| ready: " .. this.ready:get()
            end

            for i, signal in ipairs(this.signals_table) do
                if signal ~= "valid" and signal ~= "ready" then
                    s = s .. f(" | %s: 0x%s", signal, this.bits[signal]:get_str(HexStr))
                end
            end

            return s
        end
    else
        self.dump_str = function (this)
            local s = ""

            if this.name ~= "Unknown" then
                s = s .. f("[%s] ", this.name)
            end

            if this.valid ~= nil then
                s = s .. "| valid: " .. this.valid:get()
            end

            if this.ready ~= nil then
                s = s .. "| ready: " .. this.ready:get()
            end

            for i, signal in ipairs(this.signals_table) do
                if signal ~= "valid" and signal ~= "ready" then
                    s = s .. f(" | %s: 0x%s", signal, this[signal]:get_str(HexStr))
                end
            end

            return s
        end
    end

    self.dump = function (this)
        print(this:dump_str())
    end
    
end

return Bundle

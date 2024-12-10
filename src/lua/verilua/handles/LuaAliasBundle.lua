local fun = require "fun"
local List = require "pl.List"
local class = require "pl.class"
local texpect = require "TypeExpect"
local CallableHDL = require "verilua.handles.LuaCallableHDL"

local type = type
local print = print
local rawset = rawset
local assert = assert
local f = string.format
local table_concat = table.concat

local HexStr = _G.HexStr
local verilua_debug = _G.verilua_debug

local AliasBundle = class()

-- 
-- Access signal using alias name
-- 
-- @alias_signal_tbl: {
--      {<org_name>, <alias_name>}, -- alias_name can be set as `nil`, then no alias name available for signal accessing
--      ...
-- }
-- 
-- @prefix   :
-- @hierachy :
--      signal_name => <hierachy>.<prefix>_<org_name>
-- @name: bundle name
-- 
-- 
-- Example:
--      local abdl = AliasBundle(
--          {
--              {"origin_signal_name",   "alias_name"  },
--              {"origin_signal_name_1"  "alias_name_1"},
--          },
--          "some_prefix",
--          "path.to.hier",
--          "name of alias bundle"
--      )
-- 
--      local value = abdl.alias_name:get()
--      abdl.alias_name_1:set(123)
-- 
function AliasBundle:_init(alias_signal_tbl, prefix, hierachy, name)
    texpect.expect_table(alias_signal_tbl, "alias_signal_tbl")
    texpect.expect_table(alias_signal_tbl[1], "alias_signal_tbl[1]")
    texpect.expect_string(prefix, "prefix")
    texpect.expect_string(hierachy, "hierachy")

    self.__type = "AliasBundle"
    self.prefix = prefix
    self.hierachy = hierachy
    self.name = name or "Unknown"

    self.signals_tbl = fun.totable(fun.map(function (x)
        assert(x[1] ~= nil)
        assert(type(x[1]) == "string")

        return x[1]
    end, alias_signal_tbl))

    self.alias_tbl = fun.totable(fun.map(function (x)
        if x[2] == nil then
            -- No alias name, use real name
            return x[1]
        else
            return x[2]
        end
    end, alias_signal_tbl))

    verilua_debug("New AliasBundle => ", "name: " .. self.name, "signals: {" .. table_concat(self.signals_tbl, ", ") .. "}", "prefix: " .. prefix, "hierachy: ", hierachy)

    -- Construct CallableHDL bundle
    for i = 1, #self.signals_tbl do
        local alias_name = self.alias_tbl[i]
        local real_name = self.signals_tbl[i]
        rawset(self, alias_name, CallableHDL(hierachy .. "." .. prefix .. real_name, real_name, nil))
    end

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

        for i = 1, #self.signals_tbl do
            local alias_name = self.alias_tbl[i]
            local real_name = self.signals_tbl[i]
            if real_name ~= "valid" and real_name ~= "ready" then
                s = s .. f(" | %s: 0x%s", real_name .. " -> " .. alias_name, this[alias_name]:get_str(HexStr))
            end
        end

        return s
    end

    self.dump = function (this)
        print(this:dump_str())
    end
end



return AliasBundle

require "LuaCallableHDL"

local class = require "pl.class"
local List = require "pl.List"
local fun = require "fun"
local CallableHDL = CallableHDL
local assert, type, print, rawset = assert, type, print, rawset
local tconcat = table.concat


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
    assert(type(alias_signal_tbl) == "table")
    assert(type(alias_signal_tbl[1]) == "table")

    assert(prefix ~= nil)
    assert(type(prefix) == "string")

    assert(hierachy ~= nil)
    assert(type(hierachy) == "string")

    self.verbose = true
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

    local _ = self.verbose and print("New AliasBundle => ", "name: " .. self.name, "signals: {" .. tconcat(self.signals_tbl, ", ") .. "}", "prefix: " .. prefix, "hierachy: ", hierachy)

    -- Construct CallableHDL bundle
    for i = 1, #self.signals_tbl do
        local alias_name = self.alias_tbl[i]
        local real_name = self.signals_tbl[i]
        rawset(self, alias_name, CallableHDL(hierachy .. "." .. prefix .. real_name, real_name, nil))
    end
end



return AliasBundle

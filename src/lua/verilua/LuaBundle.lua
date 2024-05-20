local class = require "pl.class"
local tablex = require "pl.tablex"
local List = require "pl.List"
local tinsert = table.insert
require "LuaCallableHDL"

Bundle = class()

local Bundle = Bundle
local CallableHDL = CallableHDL
local assert, print, rawset, ipairs = assert, print, rawset, ipairs
local tconcat = table.concat

function Bundle:_init(signals_table, prefix, hierachy, name, is_decoupled)
    self.verbose = false
    self.signals_table = signals_table
    self.prefix = prefix
    self.hierachy = hierachy
    self.name = name or "Unknown"
    self.is_decoupled = is_decoupled or false

    local signals_list = List(signals_table)
    local valid_index = signals_list:index("valid")
    if is_decoupled == true then
        assert(valid_index ~= nil, "Decoupled Bundle should contains a valid signal!")
        assert(prefix ~= nil, "prefix is required for decoupled bundle!")
    end

    local _ = self.verbose and print("New Bundle => ", "name: " .. self.name, "signals: {" .. tconcat(signals_table, ", ") .. "}", "prefix: " .. prefix, "hierachy: ", hierachy)
    if is_decoupled == true then
        self.bits = {}
        tablex.foreach( signals_table, function(signal)
            local fullpath = ""
            if signal == "valid" or signal == "ready" then
                fullpath = hierachy .. "." .. prefix .. signal
                rawset(self, signal, CallableHDL(fullpath, signal))
            else
                fullpath = hierachy .. "." .. prefix .. "bits_" ..  signal
                rawset(self.bits, signal, CallableHDL(fullpath, signal))
            end
        end)
    else
        self.signals_table = {}

        tablex.foreach( signals_table, function(signal)
            local fullpath = ""

            if prefix ~= nil then
                fullpath = hierachy .. "." .. prefix .. signal
            else
                fullpath = hierachy .. "." .. signal
            end

            rawset(self, signal, CallableHDL(fullpath, signal))
            tinsert(self.signals_table, prefix .. signal)
        end)
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
            for i, sig in ipairs(self.signals_table) do
                tinsert(ret, self[sig]:get())
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
end


-- function Bundle:fire()
--     assert(self.valid ~= nil, "[" .. self.name .. "] has not valid filed in this bundle!")
--     local valid = self.valid:get()
--     local ready = self.ready
--     if ready == nil then
--         ready = 1
--     else
--         ready = self.ready:get()
--     end

--     return (valid == 1 and ready == 1)
-- end


-- function Bundle:get_all()
--     if self.is_decoupled then
--         assert(false, "TODO: ")
--     else
--         local ret = {}

--         for i, sig in ipairs(self.signals_table) do
--             tinsert(ret, self[sig]:get())
--         end

--         return ret
--     end
-- end


-- function Bundle:set_all(values_tbl)
--     if self.is_decoupled then
--         assert(false, "TODO: ")
--     else
--         for i, sig in ipairs(self.signals_table) do
--             self[sig]:set(values_tbl[i])
--         end
--     end
-- end

return Bundle

local class = require "pl.class"
local tablex = require "pl.tablex"
local List = require "pl.List"
require "LuaCallableHDL"

Bundle = class()

local Bundle = Bundle
local CallableHDL = CallableHDL
local assert, print, rawset = assert, print, rawset
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
        tablex.foreach( signals_table, function(signal)
            local fullpath = ""
            if prefix ~= nil then
                fullpath = hierachy .. "." .. prefix .. signal
            else
                fullpath = hierachy .. "." .. signal
            end
            rawset(self, signal, CallableHDL(fullpath, signal))
        end)
    end
end


function Bundle:fire()
    assert(self.valid ~= nil, "[" .. self.name .. "] has not valid filed in this bundle!")
    local valid = self.valid()
    local ready = self.ready
    if ready == nil then
        ready = 1
    else
        ready = self.ready()
    end

    return (valid == 1 and ready == 1)
end



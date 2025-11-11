local class = require "pl.class"
local success, isempty = pcall(function() return require "table.isempty" end)
if not success then
    isempty = function(t) return next(t) == nil end
end

---@alias verilua.utils.Queue.data any

---@class (exact) verilua.utils.Queue
---@overload fun(): verilua.utils.Queue
---@field private data table<integer, verilua.utils.Queue.data>
---@field private first_ptr integer
---@field private last_ptr integer
---@field push fun(self: verilua.utils.Queue, value: verilua.utils.Queue.data)
---@field pop fun(self: verilua.utils.Queue): verilua.utils.Queue.data
---@field query_first_ptr fun(self: verilua.utils.Queue): verilua.utils.Queue.data
---@field front fun(self: verilua.utils.Queue): verilua.utils.Queue.data Alias of query_first_ptr
---@field last fun(self: verilua.utils.Queue): verilua.utils.Queue.data
---@field is_empty fun(self: verilua.utils.Queue): boolean
---@field size fun(self: verilua.utils.Queue): integer
---@field reset fun(self: verilua.utils.Queue)
---@operator len: integer
local Queue = class() --[[@as verilua.utils.Queue]]

function Queue:_init()
    self.data = {}
    self.first_ptr = 1
    self.last_ptr = 0
end

function Queue:push(value)
    local last = self.last_ptr + 1
    self.last_ptr = last
    self.data[last] = value
end

function Queue:pop()
    local first_ptr = self.first_ptr
    if first_ptr > self.last_ptr then error("queue is empty") end
    local value = self.data[first_ptr]
    self.data[first_ptr] = nil -- to allow garbage collection
    self.first_ptr = first_ptr + 1
    return value
end

function Queue:query_first_ptr()
    return self.data[self.first_ptr]
end

function Queue:front()
    return self.data[self.first_ptr]
end

function Queue:last()
    if self.last_ptr == 0 then
        return nil
    else
        return self.data[self.last_ptr]
    end
end

function Queue:is_empty()
    return isempty(self.data)
end

function Queue:size()
    return self.last_ptr - self.first_ptr + 1
end

function Queue:reset()
    self.data = {}
    self.first_ptr = 1
    self.last_ptr = 0
end

function Queue:__len()
    return self.last_ptr - self.first_ptr + 1
end

return Queue

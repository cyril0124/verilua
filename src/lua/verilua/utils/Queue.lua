local class = require "pl.class"
local success, isempty = pcall(function() return require "table.isempty" end)
if not success then
    isempty = function(t) return next(t) == nil end
end

---@alias Queue.data any

---@class (exact) Queue
---@field private data table<Queue.data>
---@field private first_ptr integer
---@field private last_ptr integer
---@field push fun(self: Queue, value: Queue.data)
---@field pop fun(self: Queue): Queue.data
---@field query_first_ptr fun(self: Queue): Queue.data
---@field front fun(self: Queue): Queue.data
---@field last fun(self: Queue): Queue.data
---@field is_empty fun(self: Queue): boolean
---@field size fun(self: Queue): integer
---@operator len: integer
local Queue = class()

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
    self.data[first_ptr] = nil        -- to allow garbage collection
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

function Queue:__len()
    return self.last_ptr - self.first_ptr + 1
end

return Queue
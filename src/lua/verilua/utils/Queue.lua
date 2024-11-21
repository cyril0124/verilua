local class = require "pl.class"
local isempty = require "table.isempty"

local error = error

local Queue = class()

function Queue:_init()
    self.data = {}
    self.first = 1
    self.last = 0
end

function Queue:push(value)
    local last = self.last + 1
    self.last = last
    self.data[last] = value
end

function Queue:pop()
    local first = self.first
    if first > self.last then error("queue is empty") end
    local value = self.data[first]
    self.data[first] = nil        -- to allow garbage collection
    self.first = first + 1
    return value
end

function Queue:query_first()
    return self.data[self.first]
end

function Queue:front()
    return self.data[self.first]
end

function Queue:last()
    if self.last == 0 then
        return nil
    else
        return self.data[self.last]
    end
end

function Queue:is_empty()
    return isempty(self.data)
end

function Queue:size()
    return self.last - self.first + 1
end

return Queue
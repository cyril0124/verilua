local class = require("pl.class")
local tinsert = table.insert
local assert = assert

local StaticQueue = class()

function StaticQueue:_init(size)
    self.first = 1
    self.last = 0
    self.size = size
    self.count = 0

    self.data = {}
    for i = 1, size do
        tinsert(self.data, nil)
    end
end

-- 
-- return
--   0: success
--   1: full
-- 
function StaticQueue:push(value)
    -- assert(self.count < self.size, "full!")
    if self.count >= self.size then return 1 end
    
    local last = self.last + 1
    self.count = self.count + 1
    self.last = last
    self.data[last] = value
    return 0
end


function StaticQueue:pop()
    local first = self.first
    if first > self.last then assert(false, "queue is empty") end
    local value = self.data[first]
    self.data[first] = nil        -- to allow garbage collection
    self.first = first + 1
    self.count = self.count - 1
    return value
end

function StaticQueue:query_first()
    return self.data[self.first]
end

function StaticQueue:is_empty()
    return self.count == 0
end

function StaticQueue:is_full()
    return self.count >= self.size
end

return StaticQueue
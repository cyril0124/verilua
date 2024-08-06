local class = require "pl.class"
local inspect = require "inspect"
local tinsert = table.insert
local assert = assert

local StaticQueue = class()

function StaticQueue:_init(size, name)
    self.name = name or "Unknown_StaticQueue"
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
    
    local last = (self.last % self.size) + 1
    self.last = last
    self.count = self.count + 1
    self.data[last] = value
    return 0
end


function StaticQueue:pop()
    local first = self.first
    if self.count == 0 then assert(false, "queue is empty") end
    local value = self.data[first]
    self.data[first] = nil        -- to allow garbage collection
    self.first = (self.first % self.size) + 1
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

local function format_as_hex(value, path)
    if type(value) == "number" then
        return string.format("0x%X", value)
    elseif type(value) == "cdata" then
        if tonumber(value) == nil then
            return value
        end
        return string.format("0x%X", value)
    end
    return value
end

function StaticQueue:list_data()
    print(self.name .. " list_data:")
    print("first: " .. self.first)
    print("last: " .. self.last)
    print("count: " .. self.count)
    print("data:")
    print(inspect(self.data, {process = format_as_hex}))
    print()
end

return StaticQueue
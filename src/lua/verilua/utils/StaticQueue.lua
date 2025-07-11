local class = require "pl.class"
local inspect = require "inspect"
local table_new = require "table.new"
local table_clear = require "table.clear"

local f = string.format
local assert = assert
local math_random = math.random

---@alias StaticQueue.success 0
---@alias StaticQueue.failed 1
---@alias StaticQueue.data any

---@class (exact) StaticQueue
---@overload fun(size: integer, name?: string): StaticQueue
---@field private name string
---@field private first_ptr integer
---@field private last_ptr integer
---@field private _size integer
---@field private count integer
---@field private data table
---@field push fun(self: StaticQueue, value: StaticQueue.data): StaticQueue.success|StaticQueue.failed
---@field pop fun(self: StaticQueue): StaticQueue.data
---@field query_first fun(self: StaticQueue): StaticQueue.data
---@field front fun(self: StaticQueue): StaticQueue.data Alias of query_first
---@field last fun(self: StaticQueue): StaticQueue.data
---@field is_empty fun(self: StaticQueue): boolean
---@field is_full fun(self: StaticQueue): boolean
---@field size fun(self: StaticQueue): integer
---@field used_count fun(self: StaticQueue): integer
---@field free_count fun(self: StaticQueue): integer
---@field reset fun(self: StaticQueue)
---@field shuffle fun(self: StaticQueue)
---@field get_all_data fun(self: StaticQueue): StaticQueue.data[]
---@field list_data fun(self: StaticQueue)
---@operator len: integer
local StaticQueue = class() --[[@as StaticQueue]]

function StaticQueue:_init(size, name)
    self.name = name or "Unknown_StaticQueue"
    self.first_ptr = 1
    self.last_ptr = 0
    self._size = size
    self.count = 0

    self.data = table_new(size, 0)
end

--
-- return
--   0: success
--   1: full
--
function StaticQueue:push(value)
    -- assert(self.count < self.size, "full!")
    if self.count >= self._size then return 1 end

    local last_ptr = (self.last_ptr % self._size) + 1
    self.last_ptr = last_ptr
    self.count = self.count + 1
    self.data[last_ptr] = value
    return 0
end

function StaticQueue:pop()
    local first_ptr = self.first_ptr
    if self.count == 0 then assert(false, "queue is empty") end
    local value = self.data[first_ptr]
    self.first_ptr = (self.first_ptr % self._size) + 1
    self.count = self.count - 1
    return value
end

function StaticQueue:query_first()
    return self.data[self.first_ptr]
end

function StaticQueue:front()
    return self.data[self.first_ptr]
end

function StaticQueue:is_empty()
    return self.count == 0
end

function StaticQueue:is_full()
    return self.count >= self._size
end

function StaticQueue:size()
    return self.count
end

function StaticQueue:used_count()
    return self.count
end

function StaticQueue:free_count()
    return self._size - self.count
end

function StaticQueue:reset()
    table_clear(self.data)
    self.first_ptr = 1
    self.last_ptr = 0
    self.count = 0
end

function StaticQueue:__len()
    return self.count
end

function StaticQueue:shuffle()
    if self.count <= 1 then return end

    local size = self._size
    local data = self.data
    local first_ptr = self.first_ptr

    for i = self.count, 2, -1 do
        local j = math_random(1, i)

        local real_i = ((first_ptr + i - 2) % size) + 1
        local real_j = ((first_ptr + j - 2) % size) + 1

        data[real_i], data[real_j] = data[real_j], data[real_i]
    end
end

function StaticQueue:get_all_data()
    local ret = {}
    local count = self.count
    if count ~= 0 then
        local size = self._size
        local data = self.data
        local index = self.first_ptr
        local displayed_count = 0

        while displayed_count < count do
            ret[#ret + 1] = data[index]
            index = (index % size) + 1
            displayed_count = displayed_count + 1
        end

        return ret
    else
        return ret
    end
end

function StaticQueue:list_data()
    print("╔══════════════════════════════════════════════════════════════════════")
    print(f("║ [%s] List Data:", self.name))
    print("╠══════════════════════════════════════════════════════════════════════")
    print(f("║ first_ptr: %d, last_ptr: %d, count: %d", self.first_ptr, self.last_ptr, self.count))
    print("╟──────────────────────────────────────────────────────────────────────")

    local datas = self:get_all_data()
    if #datas ~= 0 then
        for i, data in ipairs(datas) do
            print("║ [" .. i .. "]", tostring(data))
        end
    else
        print("║ No data")
    end

    print("╚══════════════════════════════════════════════════════════════════════\n")
end

return StaticQueue

local class = require "pl.class"
local table_new = require "table.new"
local table_clear = require "table.clear"

local f = string.format
local assert = assert
local math_random = math.random

---@alias verilua.utils.StaticQueue.success 0
---@alias verilua.utils.StaticQueue.failed 1

---@generic T
---@class (exact) verilua.utils.StaticQueue<T>
---@overload fun(size: integer, name?: string): verilua.utils.StaticQueue
---@field private name string Name identifier for the queue instance
---@field private first_ptr integer Pointer to the first element in the queue
---@field private last_ptr integer Pointer to the last element in the queue
---@field private _size integer Maximum capacity of the queue
---@field private data table<integer, T> Internal storage array for queue elements
---@field count integer Current number of elements in the queue
----@field push fun(self: verilua.utils.StaticQueue, value: T): verilua.utils.StaticQueue.success|verilua.utils.StaticQueue.failed Push a value to the end of the queue
---@field pop fun(self: verilua.utils.StaticQueue): T Remove and return the first element from the queue
---@field query_first fun(self: verilua.utils.StaticQueue): T Get the first element without removing it
---@field front fun(self: verilua.utils.StaticQueue): T Alias of query_first
---@field last fun(self: verilua.utils.StaticQueue): T Get the last element without removing it
---@field is_empty fun(self: verilua.utils.StaticQueue): boolean Check if the queue is empty
---@field is_full fun(self: verilua.utils.StaticQueue): boolean Check if the queue is full
---@field size fun(self: verilua.utils.StaticQueue): integer Get current number of elements (alias of used_count)
---@field used_count fun(self: verilua.utils.StaticQueue): integer Get current number of elements used
---@field free_count fun(self: verilua.utils.StaticQueue): integer Get number of available slots
---@field reset fun(self: verilua.utils.StaticQueue) Reset the queue to empty state
---@field shuffle fun(self: verilua.utils.StaticQueue) Randomly shuffle all elements in the queue
---@field get_all_data fun(self: verilua.utils.StaticQueue): T[] Get all elements as an array in queue order
---@field list_data fun(self: verilua.utils.StaticQueue) Print all elements with queue information
---@operator len: integer Length operator overload returns current element count
local StaticQueue = class() --[[@as verilua.utils.StaticQueue]]

---@param size integer
---@param name? string
function StaticQueue:_init(size, name)
    assert(type(size) == "number", "size must be a number")

    if name then
        assert(type(name) == "string", "name must be a string")
    end

    self.name = name or "Unknown_StaticQueue"
    self.first_ptr = 1
    self.last_ptr = 0
    self._size = size
    self.count = 0

    self.data = table_new(size, 0)
end

--- Push a value to the end of the queue
---@nodiscard Need check success, `0` for success, `1` for failed
---@param value T
---@return integer TODO: use boolean?
function StaticQueue:push(value)
    if self.count >= self._size then
        return 1
    end

    local last_ptr = (self.last_ptr % self._size) + 1
    self.last_ptr = last_ptr
    self.count = self.count + 1
    self.data[last_ptr] = value
    return 0
end

function StaticQueue:pop()
    if self.count == 0 then
        ---@diagnostic disable-next-line
        assert(false, "queue is empty")
    end

    local first_ptr = self.first_ptr
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

function StaticQueue:last()
    return self.data[self.last_ptr]
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

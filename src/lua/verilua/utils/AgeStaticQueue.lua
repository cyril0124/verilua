local class = require "pl.class"
local table_new = require "table.new"
local table_clear = require "table.clear"

local f = string.format
local assert = assert
local math_random = math.random

---@alias verilua.utils.AgeStaticQueue.success 0
---@alias verilua.utils.AgeStaticQueue.failed 1

---@generic T
---@class (exact) verilua.utils.AgeStaticQueue<T>
---@overload fun(size: integer, max_age?: integer, name?: string): verilua.utils.AgeStaticQueue
---@field private name string Name identifier for the queue instance
---@field private first_ptr integer Pointer to the first element in the queue
---@field private last_ptr integer Pointer to the last element in the queue
---@field private _size integer Maximum capacity of the queue
---@field private data table<integer, T> Internal storage array for queue elements
---@field private global_age integer Global age counter for tracking element ages
---@field private ages table<integer, integer|uint64_t> Array storing the insertion age of each slot
---@field private MAX_AGE integer Maximum age threshold for shuffle protection
---@field count integer Current number of elements in the queue
----@field push fun(self: verilua.utils.AgeStaticQueue, value: T): verilua.utils.AgeStaticQueue.success|verilua.utils.AgeStaticQueue.failed Push a value to the end of the queue
---@field pop fun(self: verilua.utils.AgeStaticQueue): T Remove and return the first element from the queue
---@field query_first fun(self: verilua.utils.AgeStaticQueue): T Get the first element without removing it
---@field front fun(self: verilua.utils.AgeStaticQueue): T Alias of query_first
---@field last fun(self: verilua.utils.AgeStaticQueue): T Get the last element without removing it
---@field is_empty fun(self: verilua.utils.AgeStaticQueue): boolean Check if the queue is empty
---@field is_full fun(self: verilua.utils.AgeStaticQueue): boolean Check if the queue is full
---@field size fun(self: verilua.utils.AgeStaticQueue): integer Get current number of elements (alias of used_count)
---@field used_count fun(self: verilua.utils.AgeStaticQueue): integer Get current number of elements used
---@field free_count fun(self: verilua.utils.AgeStaticQueue): integer Get number of available slots
---@field reset fun(self: verilua.utils.AgeStaticQueue) Reset the queue to empty state
---@field shuffle fun(self: verilua.utils.AgeStaticQueue) Randomly shuffle all elements in the queue
---@field get_all_data fun(self: verilua.utils.AgeStaticQueue): T[] Get all elements as an array in queue order
---@field list_data fun(self: verilua.utils.AgeStaticQueue) Print all elements with queue information
---@operator len: integer Length operator overload returns current element count
local AgeStaticQueue = class() --[[@as verilua.utils.AgeStaticQueue]]

local DEFAULT_MAX_AGE = 10000ULL

---@param size integer
---@param max_age? integer
---@param name? string
function AgeStaticQueue:_init(size, max_age, name)
    assert(type(size) == "number", "size must be a number")

    if max_age then
        assert(type(max_age) == "number", "max_age must be a number")
    end

    if name then
        assert(type(name) == "string", "name must be a string")
    end

    self.name = name or "Unknown_AgeStaticQueue"
    self.first_ptr = 1
    self.last_ptr = 0
    self._size = size
    self.count = 0

    self.data = table_new(size, 0)

    self.global_age = 0ULL
    self.ages = table_new(size, 0)

    self.MAX_AGE = (max_age or DEFAULT_MAX_AGE) + 0ULL
    for i = 1, size do
        self.ages[i] = 0ULL
    end

    -- Note: global_age overflow handling
    -- In LuaJIT, all numbers are 64-bit doubles, can precisely represent integers up to 2^52 (~4.5×10^15)
    -- The ULL suffix (uint64_t literal) is converted to Lua number at runtime
    -- With MAX_AGE = 10000, overflow would require ~1.4 years of continuous high-frequency pops (10^8 pops/sec)
    -- For typical hardware verification scenarios, this is not a concern
    -- If overflow does occur, the relative age relationships will remain mostly correct
    -- due to floating-point arithmetic properties, though precision may gradually degrade
end

--- Push a value to the end of the queue
---@nodiscard Need check success, `0` for success, `1` for failed
---@param value T
---@return integer TODO: use boolean?
function AgeStaticQueue:push(value)
    if self.count >= self._size then
        return 1
    end

    local last_ptr = (self.last_ptr % self._size) + 1
    self.last_ptr = last_ptr
    self.count = self.count + 1
    self.data[last_ptr] = value
    self.ages[last_ptr] = self.global_age
    return 0
end

function AgeStaticQueue:pop()
    if self.count == 0 then
        ---@diagnostic disable-next-line
        assert(false, "queue is empty")
    end

    local first_ptr = self.first_ptr
    local value = self.data[first_ptr]

    self.first_ptr = (self.first_ptr % self._size) + 1
    self.count = self.count - 1

    self.global_age = self.global_age + 1
    self.ages[first_ptr] = 0ULL

    return value
end

function AgeStaticQueue:query_first()
    return self.data[self.first_ptr]
end

function AgeStaticQueue:front()
    return self.data[self.first_ptr]
end

function AgeStaticQueue:last()
    return self.data[self.last_ptr]
end

function AgeStaticQueue:is_empty()
    return self.count == 0
end

function AgeStaticQueue:is_full()
    return self.count >= self._size
end

function AgeStaticQueue:size()
    return self.count
end

function AgeStaticQueue:used_count()
    return self.count
end

function AgeStaticQueue:free_count()
    return self._size - self.count
end

function AgeStaticQueue:reset()
    table_clear(self.data)

    self.global_age = 0ULL
    for i = 1, self._size do
        self.ages[i] = 0ULL
    end

    self.first_ptr = 1
    self.last_ptr = 0
    self.count = 0
end

function AgeStaticQueue:__len()
    return self.count
end

function AgeStaticQueue:shuffle()
    if self.count <= 1 then return end

    local size = self._size
    local data = self.data
    local first_ptr = self.first_ptr

    local ages = self.ages
    local global_age = self.global_age
    local protect_first = (global_age - ages[first_ptr]) >= self.MAX_AGE

    for i = self.count, 2, -1 do
        local j = math_random(1, i)

        local real_i = ((first_ptr + i - 2) % size) + 1
        local real_j = ((first_ptr + j - 2) % size) + 1

        local do_switch = true
        if (real_i == first_ptr or real_j == first_ptr) and protect_first then
            do_switch = false
        end

        if do_switch then
            data[real_i], data[real_j] = data[real_j], data[real_i]
            ages[real_i], ages[real_j] = ages[real_j], ages[real_i]
        end
    end
end

function AgeStaticQueue:get_all_data()
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
    end

    return ret
end

function AgeStaticQueue:list_data()
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

return AgeStaticQueue

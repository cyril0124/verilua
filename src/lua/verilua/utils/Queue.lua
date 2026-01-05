---@diagnostic disable: unnecessary-assert

local inspect = require "inspect"
local class = require "pl.class"
local table_clear = require "table.clear"

---@class verilua.utils.Queue.options Configuration options for Queue
---@field name string? Optional name for the queue (useful for debugging)
---@field compact_threshold integer? Number of operations before triggering compaction (default: 1000)
---@field leak_check boolean? Enable leak checking (default: false)
---@field leak_check_threshold integer? Number of do_leak_check() calls before reporting leak (default: 100000)

---@generic T
---@class (exact) verilua.utils.Queue<T> Generic queue implementation with leak detection and memory optimization
---@overload fun(options: verilua.utils.Queue.options?): verilua.utils.Queue Create a new queue with optional configuration
---@field private name string Queue name for debugging purposes
---@field private data table<integer, T> Internal storage for queue elements
---@field private first_ptr integer Index of the first element in the queue
---@field private last_ptr integer Index of the last element in the queue
---@field private leak_check boolean Whether leak checking is enabled
---@field private leak_check_threshold integer Maximum number of do_leak_check() calls before reporting leak
---@field private leak_check_cnt integer Current count of consecutive do_leak_check() calls
---@field private compact_threshold integer Number of operations before triggering automatic compaction
---@field private _compact fun(self: verilua.utils.Queue) Compact the queue to free memory by moving elements to the beginning
---@field push fun(self: verilua.utils.Queue, value: T) Add an element to the end of the queue
---@field pop fun(self: verilua.utils.Queue): T Remove and return the first element from the queue
---@field query_first_ptr fun(self: verilua.utils.Queue): T Get the first element without removing it
---@field front fun(self: verilua.utils.Queue): T Alias of query_first_ptr - get the first element without removing it
---@field last fun(self: verilua.utils.Queue): T Get the last element without removing it, or nil if queue is empty
---@field is_empty fun(self: verilua.utils.Queue): boolean Check if the queue is empty
---@field size fun(self: verilua.utils.Queue): integer Get the number of elements in the queue
---@field reset fun(self: verilua.utils.Queue) Clear all elements and reset the queue to initial state
---@field do_leak_check fun(self: verilua.utils.Queue) Increment leak check counter and report leak if threshold exceeded
---@field __tostring fun(self: verilua.utils.Queue): string Convert queue to string for printing
---@operator len: integer Get the number of elements in the queue using # operator
local Queue = class() --[[@as verilua.utils.Queue]]

local q_idx = 0

---@param options verilua.utils.Queue.options?
function Queue:_init(options)
    self.data = {}
    self.first_ptr = 1
    self.last_ptr = 0

    if options then
        assert(type(options) == "table")
    end

    -- Generate unique name if not provided
    if options and options.name then
        self.name = options.name
    else
        self.name = "AnonymousQueue_" .. q_idx
        q_idx = q_idx + 1
    end

    local leak_check = options and options.leak_check or false
    local leak_check_threshold = options and options.leak_check_threshold or 100000
    local compact_threshold = options and options.compact_threshold or 1000

    assert(type(self.name) == "string")
    assert(type(leak_check) == "boolean")
    assert(type(leak_check_threshold) == "number")
    assert(type(compact_threshold) == "number")

    self.leak_check = leak_check
    self.leak_check_threshold = leak_check_threshold
    self.leak_check_cnt = 0
    self.compact_threshold = compact_threshold

    self.pop = function(self)
        local first_ptr = self.first_ptr
        local last_ptr = self.last_ptr

        if first_ptr > last_ptr then
            ---@diagnostic disable-next-line
            assert(false, "queue is empty")
        end

        local data = self.data
        local value = data[first_ptr]
        -- Don't set nil to avoid garbage collection overhead
        self.first_ptr = first_ptr + 1

        -- Periodically compact to prevent memory accumulation
        if (first_ptr % self.compact_threshold) == 0 then
            self:_compact()
        end

        return value
    end

    if leak_check then
        local original_pop = self.pop
        self.pop = function(self)
            self.leak_check_cnt = 0
            return original_pop(self)
        end
    end
end

function Queue:push(value)
    local data = self.data
    local last = self.last_ptr + 1
    self.last_ptr = last
    data[last] = value
end

-- Compact the queue by moving elements to the beginning of the table
-- This prevents memory accumulation while maintaining performance
function Queue:_compact()
    local data = self.data
    local first_ptr = self.first_ptr
    local last_ptr = self.last_ptr
    local size = last_ptr - first_ptr + 1

    if size > 0 then
        -- Move data to the beginning of the table
        for i = 1, size do
            data[i] = data[first_ptr + i - 1]
        end
        -- Clear old data
        for i = size + 1, last_ptr do
            data[i] = nil
        end
        self.first_ptr = 1
        self.last_ptr = size
    else
        -- Queue is empty, clear the entire table
        for i = 1, last_ptr do
            data[i] = nil
        end
        self.first_ptr = 1
        self.last_ptr = 0
    end
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
    return self.first_ptr > self.last_ptr
end

function Queue:size()
    return self.last_ptr - self.first_ptr + 1
end

function Queue:reset()
    table_clear(self.data)
    self.leak_check_cnt = 0
    self.first_ptr = 1
    self.last_ptr = 0
end

function Queue:do_leak_check()
    local leak_check_cnt = self.leak_check_cnt
    if leak_check_cnt >= self.leak_check_threshold then
        -- Build queue content information for debugging
        local elements_info = {}
        for i = self.first_ptr, self.last_ptr do
            local value = self.data[i]
            local value_str = inspect(value)
            table.insert(elements_info, string.format("  [%d] %s", i - self.first_ptr + 1, value_str))
        end

        local queue_content = table.concat(elements_info, "\n")
        if #elements_info == 0 then
            queue_content = "  (empty)"
        end

        assert(false, string.format(
            "[%s] Queue leak check failed. Leak check count: %d\n" ..
            "Queue content (%d elements):\n%s",
            self.name,
            leak_check_cnt,
            self.last_ptr - self.first_ptr + 1,
            queue_content
        ))
    end
    self.leak_check_cnt = leak_check_cnt + 1
end

function Queue:__len()
    return self.last_ptr - self.first_ptr + 1
end

--- Convert queue to string for printing
---@return string Formatted string representation of queue elements
function Queue:__tostring()
    local header_parts = {}
    table.insert(header_parts, string.format("[%s]", self.name))

    if self.leak_check then
        table.insert(header_parts, string.format("Leak check: %d/%d", self.leak_check_cnt, self.leak_check_threshold))
    end

    if self:is_empty() then
        return table.concat(header_parts, " ") .. " Queue is empty"
    end

    local elements = {}
    for i = self.first_ptr, self.last_ptr do
        local value = self.data[i]
        local value_str = inspect(value)
        table.insert(elements, string.format("  [%d] %s", i - self.first_ptr + 1, value_str))
    end

    table.insert(header_parts, string.format("Queue (%d elements):", self:size()))

    return table.concat(header_parts, " ") .. "\n" .. table.concat(elements, "\n")
end

return Queue

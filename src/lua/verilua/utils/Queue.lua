---@diagnostic disable: unnecessary-assert

local inspect = require "inspect"
local class = require "pl.class"

---@class verilua.utils.Queue.options
---@field name string?
---@field compact_threshold integer?
---@field leak_check boolean?
---@field leak_check_threshold integer?

---@generic T
---@class (exact) verilua.utils.Queue<T>
---@overload fun(options: verilua.utils.Queue.options?): verilua.utils.Queue
---@field private data table<integer, T>
---@field private first_ptr integer
---@field private last_ptr integer
---@field private leak_check boolean
---@field private leak_check_threshold integer
---@field private leak_check_cnt integer
---@field private compact_threshold integer Threshold for triggering compaction
---@field private _compact fun(self: verilua.utils.Queue) Compact the queue to free memory
---@field push fun(self: verilua.utils.Queue, value: T)
---@field pop fun(self: verilua.utils.Queue): T
---@field query_first_ptr fun(self: verilua.utils.Queue): T
---@field front fun(self: verilua.utils.Queue): T Alias of query_first_ptr
---@field last fun(self: verilua.utils.Queue): T
---@field is_empty fun(self: verilua.utils.Queue): boolean
---@field size fun(self: verilua.utils.Queue): integer
---@field reset fun(self: verilua.utils.Queue)
---@field do_leak_check fun(self: verilua.utils.Queue)
---@operator len: integer
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
    local data = self.data
    local first_ptr = self.first_ptr
    local last_ptr = self.last_ptr

    -- Clear used elements
    for i = first_ptr, last_ptr do
        data[i] = nil
    end

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

return Queue

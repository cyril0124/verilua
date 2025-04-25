local class = require "pl.class"
local utils = require "LuaUtils"
local table_new = require "table.new"

local type = type
local assert = assert
local f = string.format

---@class (exact) IDPool.params
---@field size number
---@field start_value? number
---@field shuffle? boolean

---@class (exact) IDPool
---@overload fun(pool_size_or_params: number|IDPool.params, shuffle?: boolean): IDPool
---@field pool_size number
---@field start_value number
---@field end_value number
---@field pool table<number>
---@field size number
---@field alloc fun(self: IDPool): number
---@field release fun(self: IDPool, id: number)
---@field is_full fun(self: IDPool): boolean Check if the pool is full (all IDs are available)
---@field is_empty fun(self: IDPool): boolean Check if the pool is empty(all IDs are allocated, none left in pool)
---@field used_count fun(self: IDPool): number
---@field free_count fun(self: IDPool): number
---@operator len: number
local IDPool = class()

-- 
-- Example:
--      local idpool = IDPool(100)
--      local id = idpool:alloc()
--      idpool:release(id)
-- 
--      local idpool = IDPool { start_value = 10, size = 100 }
--      local id = idpool:alloc()
--      idpool:release(id)
-- 

---@param params number|IDPool.params
---@param shuffle boolean?
function IDPool:_init(params, shuffle)
    ---@cast self IDPool
    local self = self

    local _shuffle = false
    if type(params) == "table" then
        ---@cast params IDPool.params
        _shuffle = params.shuffle or false

        self.pool_size = assert(params.size, "[IDPool] size is required")

        self.start_value = params.start_value or 0
        self.end_value = self.start_value + self.pool_size - 1
    else
        ---@cast params number
        self.start_value = 0
        self.end_value = params - 1
        self.pool_size = params
        _shuffle = shuffle or false
    end

    self.pool = table_new(self.pool_size, 0)
    self.size = self.pool_size

    local index = 1
    for i = self.end_value, self.start_value, -1 do
        self.pool[index] = i
        index = index + 1
    end

    if _shuffle then
        utils.shuffle(self.pool)
    end
end

function IDPool:alloc()
    local id = self.pool[self.size]
    self.pool[self.size] = nil
    self.size = self.size - 1
    assert(self.size >= 0, "[IDPool] pool is empty")
    return id
end

function IDPool:release(id)
    if id < self.start_value or id > self.end_value then
        assert(false, f("[IDPool] id is out of range: %d, start_value => %d, end_value => %d", id, self.start_value, self.end_value))
    end

    for i = 1, self.size do
        if self.pool[i] == id then
            assert(false, f("[IDPool] id is already in the pool: %d", id))
        end
    end

    self.size = self.size + 1
    self.pool[self.size] = id
end

-- Check if the pool is full (all IDs are available)
function IDPool:is_full()
    return self.size == 0
end

-- Check if the pool is empty(all IDs are allocated, none left in pool)
function IDPool:is_empty()
    return self.size == self.pool_size
end

function IDPool:used_count()
    return self.pool_size - self.size
end

function IDPool:free_count()
    return self.size
end

function IDPool:__len()
    -- equivalent to self.pool_size
    return #self.pool
end

return IDPool
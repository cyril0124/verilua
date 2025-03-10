local class = require "pl.class"
local utils = require "LuaUtils"
local table_new = require "table.new"

local type = type
local assert = assert
local f = string.format

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
function IDPool:_init(params, shuffle)
    local _shuffle = false
    if type(params) == "table" then
        _shuffle = params.shuffle or false
        
        self.pool_size = assert(params.size, "[IDPool] size is required")

        self.start_value = params.start_value or 0
        self.end_value = self.start_value + self.pool_size - 1
    else
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

function IDPool:is_full()
    return self.size == 0
end

function IDPool:pool_size()
    return self.pool_size - self.size
end

function IDPool:__len()
    return #self.pool
end

return IDPool
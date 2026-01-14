---@diagnostic disable: unnecessary-assert

local class = require "pl.class"
local utils = require "LuaUtils"
local table_new = require "table.new"
local table_clear = require "table.clear"
local texpect = require "verilua.TypeExpect"

local type = type
local assert = assert
local f = string.format

---@class (exact) verilua.utils.IDPool.params
---@field size integer
---@field start_value? integer
---@field shuffle? boolean

---@class (exact) verilua.utils.IDPool
---@overload fun(params: verilua.utils.IDPool.params): verilua.utils.IDPool
---@overload fun(pool_size_or_params: integer, shuffle?: boolean): verilua.utils.IDPool
---@field private POOL_SIZE integer
---@field private START_VALUE integer
---@field private END_VALUE integer
---@field private shuffle boolean
---@field private pool integer[]
---@field private size integer
---@field private allocated table<integer, boolean> -- Track allocated IDs for O(1) duplicate check
----@field alloc fun(self: verilua.utils.IDPool): integer
---@field release fun(self: verilua.utils.IDPool, id: integer)
---@field is_full fun(self: verilua.utils.IDPool): boolean Check if the pool is full (all IDs are available)
---@field is_empty fun(self: verilua.utils.IDPool): boolean Check if the pool is empty(all IDs are allocated, none left in pool)
---@field used_count fun(self: verilua.utils.IDPool): integer
---@field free_count fun(self: verilua.utils.IDPool): integer
---@field reset fun(self: verilua.utils.IDPool)
---@operator len: integer
local IDPool = class() --[[@as verilua.utils.IDPool]]

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

---@param params number|verilua.utils.IDPool.params
---@param shuffle boolean?
function IDPool:_init(params, shuffle)
    ---@cast self verilua.utils.IDPool
    local self = self

    local _shuffle = false
    if type(params) == "table" then
        texpect.expect_table(params, "IDPool::_init::params", {
            "size",
            "start_value",
            "shuffle",
        })

        ---@cast params verilua.utils.IDPool.params
        _shuffle = params.shuffle or false

        self.POOL_SIZE = assert(params.size, "[IDPool] size is required")

        self.START_VALUE = params.start_value or 0
        self.END_VALUE = self.START_VALUE + self.POOL_SIZE - 1
    else
        ---@cast params integer
        self.START_VALUE = 0
        self.END_VALUE = params - 1
        self.POOL_SIZE = params
        _shuffle = shuffle or false
    end

    self.pool = table_new(self.POOL_SIZE, 0)
    self.size = self.POOL_SIZE
    self.allocated = {} -- Track allocated IDs for O(1) duplicate check

    local index = 1
    for i = self.END_VALUE, self.START_VALUE, -1 do
        self.pool[index] = i
        index = index + 1
    end

    self.shuffle = _shuffle
    if _shuffle ~= nil then
        utils.shuffle(self.pool)
    end
end

---@nodiscard Return value(ID) should be used
---@return integer
function IDPool:alloc()
    local size = self.size
    local id = self.pool[size]
    self.pool[size] = nil
    self.size = size - 1
    self.allocated[id] = true
    assert(self.size >= 0, "[IDPool] pool is empty")
    return id --[[@as integer]]
end

function IDPool:release(id)
    if id < self.START_VALUE or id > self.END_VALUE then
        assert(
            false,
            f(
                "[IDPool] id is out of range: %d, START_VALUE => %d, END_VALUE => %d",
                id,
                self.START_VALUE,
                self.END_VALUE
            )
        )
    end

    if not self.allocated[id] then
        assert(
            false,
            f("[IDPool] id is not allocated or already in the pool: %d", id)
        )
    end

    self.size = self.size + 1
    self.pool[self.size] = id
    self.allocated[id] = nil -- Remove from allocated set
end

-- Check if the pool is full (all IDs are available)
function IDPool:is_full()
    -- TODO: Re-enable this method in future versions
    assert(false, "<IDPool>:is_full() is deprecated, use `<IDPool>:used_count() == 0` instead")
    return self.size == self.POOL_SIZE
end

-- Check if the pool is empty(all IDs are allocated, none left in pool)
function IDPool:is_empty()
    assert(false, "<IDPool>:is_empty() is deprecated, use `<IDPool>:free_count() == 0` instead")
    return self.size == 0
end

function IDPool:used_count()
    return self.POOL_SIZE - self.size
end

function IDPool:free_count()
    return self.size
end

function IDPool:reset()
    self.size = self.POOL_SIZE
    self.pool = table_new(self.POOL_SIZE, 0)
    table_clear(self.allocated)

    local index = 1
    for i = self.END_VALUE, self.START_VALUE, -1 do
        self.pool[index] = i
        index = index + 1
    end

    if self.shuffle then
        utils.shuffle(self.pool)
    end
end

function IDPool:__len()
    return self.POOL_SIZE
end

return IDPool

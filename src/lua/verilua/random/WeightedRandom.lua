local class = require "pl.class"
local texpect = require "TypeExpect"

local assert = assert
local ipairs = ipairs
local random = math.random

---@class (exact) WeightedRandom.weighted_random_table
---@field [1] integer weight
---@field [2] integer start
---@field [3] integer end

---@class (exact) WeightedRandom
---@overload fun(weighted_random_table: WeightedRandom.weighted_random_table[]): WeightedRandom
---@field private weighted_random_table WeightedRandom.weighted_random_table[]
---@field gen fun(self: WeightedRandom): number
local WeightedRandom = class()

---@param weighted_random_table WeightedRandom.weighted_random_table[]
function WeightedRandom:_init(weighted_random_table)
    texpect.expect_table(weighted_random_table, "weighted_random_table")

    local total_weight = 0
    for index, value in ipairs(weighted_random_table) do
        local _weight = value[1]
        local _start  = value[2]
        local _end    = value[3]

        total_weight  = total_weight + _weight
        assert(_end > _start)
    end
    assert(total_weight == 100)

    self.weighted_random_table = weighted_random_table
end

function WeightedRandom:gen()
    local rand_weight = random(100)

    local cumulative_weight = 0
    for index, value in ipairs(self.weighted_random_table) do
        local weight      = value[1]
        local range_start = value[2]
        local range_end   = value[3]
        cumulative_weight = cumulative_weight + weight

        if rand_weight <= cumulative_weight then
            return random(range_start, range_end)
        end
    end

    local last_value = self.weighted_random_table[#self.weighted_random_table]
    
    ---@diagnostic disable-next-line: need-check-nil
    return random(last_value[2], last_value[3])
end

return WeightedRandom

local class = require "pl.class"
local texpect = require "TypeExpect"

local assert = assert
local random = math.random
local randomseed = math.randomseed

---@class (exact) CyclicRandom
---@overload fun(start_value: integer, end_value: integer): CyclicRandom
---@field private gen_idx integer
---@field private size integer
---@field private values table<integer, integer>
---@field shuffle fun(self: CyclicRandom, seed: integer)
---@field gen fun(self: CyclicRandom, seed?: integer): integer
local CyclicRandom = class()

---@param start_value integer
---@param end_value integer
function CyclicRandom:_init(start_value, end_value)
    texpect.expect_number(start_value, "start_value")
    texpect.expect_number(end_value, "end_value")

    assert(end_value > start_value)

    self.gen_idx = 1
    self.size = end_value - start_value + 1
    self.values = {}

    local idx = 1
    for i = start_value, end_value do
        self.values[idx] = i
        idx = idx + 1
    end

    self:shuffle(0)
end

function CyclicRandom:shuffle(seed)
    randomseed(seed)
    local n = #self.values
    while n >= 2 do
        local k = random(n)
        self.values[n], self.values[k] = self.values[k], self.values[n]
        n = n - 1
    end
end

function CyclicRandom:gen(seed)
    if self.gen_idx > self.size then
        local _seed = seed or 0
        self:shuffle(_seed)
        self.gen_idx = 1
    end

    local value = self.values[self.gen_idx]
    self.gen_idx = self.gen_idx + 1
    return value
end

return CyclicRandom

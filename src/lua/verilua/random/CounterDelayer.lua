local class = require "pl.class"
local texpect = require "TypeExpect"

local assert = assert
local f = string.format
local random = math.random

---@class (exact) verilua.random.CounterDelayer
---@overload fun(min_delay: integer, max_delay: integer): verilua.random.CounterDelayer
---@field private min_delay integer
---@field private max_delay integer
---@field private cnt integer
---@field fire fun(self: verilua.random.CounterDelayer): boolean Check if it is time to fire, return `true` if it is time to fire
local CounterDelayer = class()

---@param min_delay integer
---@param max_delay integer
function CounterDelayer:_init(min_delay, max_delay)
    texpect.expect_number(min_delay, "min_delay")
    texpect.expect_number(max_delay, "max_delay")

    assert(max_delay >= min_delay, f("max_delay:%d min_delay:%d", max_delay, min_delay))

    self.min_delay = min_delay
    self.max_delay = max_delay
    self.cnt = 0
end

function CounterDelayer:fire()
    if self.cnt == 0 then
        self.cnt = random(self.min_delay, self.max_delay)
        return true
    else
        assert(self.cnt > 0)
        self.cnt = self.cnt - 1
        return false
    end
end

return CounterDelayer

local class = require "pl.class"
local texpect = require "TypeExpect"

local assert = assert
local f = string.format
local random = math.random

local CounterDelayer = class()

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
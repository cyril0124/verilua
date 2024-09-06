local class = require "pl.class"
local assert = assert
local random, f = math.random, string.format

local CounterDelayer = class()

function CounterDelayer:_init(min_delay, max_delay)
    assert(min_delay ~= nil)
    assert(max_delay ~= nil)
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
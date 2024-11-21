local class = require "pl.class"
local texpect = require "TypeExpect"

local assert = assert
local random = math.random
local randomseed = math.randomseed

local CyclicdRandom = class()

function CyclicdRandom:_init(start_value, end_value)
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

function CyclicdRandom:shuffle(seed)
    randomseed(seed)
    local n = #self.values
    while n >= 2 do
      local k = random(n)
      self.values[n], self.values[k] = self.values[k], self.values[n]
      n = n - 1
    end
end

function CyclicdRandom:gen(seed)
    if self.gen_idx > self.size then
        local _seed = seed or 0
        self:shuffle(_seed)
        self.gen_idx = 1
    end
    
    local value = self.values[self.gen_idx]
    self.gen_idx = self.gen_idx + 1
    return value
end

return CyclicdRandom
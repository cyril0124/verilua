local class = require "pl.class"

local assert = assert
local printf = printf
local type = type

local CoverPoint = class()

function CoverPoint:_init(name, coverage_group)
    assert(type(name) == "string")

    if type(coverage_group) ~= "table" then
        assert(false, name .. " coverage group is not a valid type! => " .. type(coverage_group))
    end

    self.name = name
    self.__type = "CoverPoint"
    self.fullname = coverage_group.name .. "__" .. name
    self.coverage_group = coverage_group

    self.cnt = 0
    
    printf("[CoverPoint] Create CoverPoint: %s -- CoverGroup: %s -- fullname: %s\n", name, coverage_group.name, self.fullname)
end

function CoverPoint:cover()
    self.cnt = self.cnt + 1
end

function CoverPoint:inc_with_cycle(cycle)
    assert(false, "[CoverPoint] do not use <inc_with_cycle>(cycle), use <inc>() instead!")
end

function CoverPoint:dec_with_cycle(cycle)
    assert(false, "[CoverPoint] do not use <dec_with_cycle>(cycle), use <dec>() instead!")
end

function CoverPoint:inc()
    self.cnt = self.cnt + 1
end

function CoverPoint:dec()
    self.cnt = self.cnt - 1
end

function CoverPoint:reset()
    self.cnt = 0
end

function CoverPoint:dump()
    printf("[CoverPoint: %s CoverGroup: %s] => %d\n", self.name, self.coverage_group.name, self.cnt)
end

return CoverPoint
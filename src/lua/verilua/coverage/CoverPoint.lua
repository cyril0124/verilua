local class = require "pl.class"
local texpect = require "verilua.TypeExpect"

local type = type
local assert = assert
local printf = printf
local f = string.format

local verilua_debug = _G.verilua_debug

local CoverPoint = class()

function CoverPoint:_init(name, coverage_group)
    texpect.expect_string(name, "name")
    texpect.expect_covergroup(coverage_group, "coverage_group")

    self.name = name
    self.__type = "CoverPoint"
    self.fullname = coverage_group.name .. "__" .. name
    self.coverage_group = coverage_group

    self.cnt = 0

    verilua_debug(f("[CoverPoint] Create CoverPoint: %s -- CoverGroup: %s -- fullname: %s\n", name, coverage_group.name,
        self.fullname))
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

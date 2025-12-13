local class = require "pl.class"
local texpect = require "TypeExpect"

local type = type
local assert = assert
local printf = printf
local f = string.format
local table_insert = table.insert

local verilua_debug = _G.verilua_debug

local AccurateCoverPoint = class()

function AccurateCoverPoint:_init(name, coverage_group)
    texpect.expect_string(name, "name")
    texpect.expect_covergroup(coverage_group, "coverage_group")

    self.name = name
    self.__type = "AccurateCoverPoint"
    self.fullname = coverage_group.name .. "__" .. name
    self.coverage_group = coverage_group

    self.covered_cycles_table = {}
    self.cnt = 0

    verilua_debug(f("[AccurateCoverPoint] Create AccurateCoverPoint: %s -- CoverGroup: %s -- fullname: %s\n", name,
        coverage_group.name, self.fullname))
end

function AccurateCoverPoint:inc_with_cycle(cycle)
    self.cnt = self.cnt + 1
    table_insert(self.covered_cycles_table, cycle)
end

function AccurateCoverPoint:dec_with_cycle(cycle)
    self.cnt = self.cnt - 1
    table_insert(self.covered_cycles_table, cycle)
end

function AccurateCoverPoint:inc()
    assert(false, "[AccurateCoverPoint] do not use <inc>(), use <inc_with_cycle>(cycle) instead!")
end

function AccurateCoverPoint:dec()
    assert(false, "[AccurateCoverPoint] do not use <dec>(), use <dec_with_cycle>(cycle) instead!")
end

function AccurateCoverPoint:reset()
    self.cnt = 0
end

function AccurateCoverPoint:dump()
    printf("[AccurateCoverPoint: %s CoverGroup: %s] => %d\n", self.name, self.coverage_group.name, self.cnt)
end

return AccurateCoverPoint

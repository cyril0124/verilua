local class = require "pl.class"

local ipairs = ipairs
local assert = assert
local printf = printf
local print = print
local type = type
local io = io
local f = string.format
local cfg = cfg
local table_insert = table.insert

local CoverGroup = class()

function CoverGroup:_init(name)
    assert(type(name) == "string")

    self.name = name
    self.type = "CoverGroup"
    self.cover_points = {}
    self.cover_point_type = "Unknown"

    printf("[CoverGroup] Create CoverGroup: %s\n", name)
end

function CoverGroup:add_cover_point(cover_point)
    if self.cover_point_type == "Unknown" then
        self.cover_point_type = cover_point.type
    else
        assert(cover_point.type == self.cover_point_type, f("[CoverGroup] all the appended cover point should have the same type, current cover point type: %s, appended cover point type: %s", self.cover_point_type, cover_point.type))
    end
    table_insert(self.cover_points, cover_point)
end

function CoverGroup:report()
    print("\nCoverageGroup Report: ------------------------------------------- ")
    for i, cover_point in ipairs(self.cover_points) do
        cover_point:dump()
    end
    print("-----------------------------------------------------------------\n ")
end

function CoverGroup:save(_filename)
    local filename = _filename
    if not _filename then
        filename = self.name .. ".coverage.json"
    end

    printf("[CoverGroup] Save coverage group: `%s` into `%s`, cover point type is `%s`\n", self.name, filename, self.cover_point_type)

    local file = io.open(filename, 'w')
    file:write("{\n")
    file:write("\t\"date\": " .. "\"" .. os.date() .. "\"" .. ",\n")
    file:write("\t\"simulator\": " .. "\"" .. cfg.simulator .. "\"" .. ",\n")
    file:write("\t\"nr_cover_point\": " .. #self.cover_points .. ",\n")

    local final_idx = #self.cover_points
    if self.cover_point_type == "CoverPoint" then
        for i, cover_point in ipairs(self.cover_points) do
            if i == final_idx then
                file:write(f("\t\"%s\": %d\n", cover_point.fullname, cover_point.cnt))
            else
                file:write(f("\t\"%s\": %d,\n", cover_point.fullname, cover_point.cnt))
            end
        end
    elseif self.cover_point_type == "AccurateCoverPoint" then
        for i, cover_point in ipairs(self.cover_points) do
            file:write(f("\t\"%s\": [ ", cover_point.fullname))

            local covered_cycles_table = cover_point.covered_cycles_table
            local _final_idx = #covered_cycles_table
            for j = 1, _final_idx do
                local cycles = covered_cycles_table[j]
                if j == _final_idx then
                    file:write(f("%d ", cycles))
                else
                    file:write(f("%d, ", cycles))
                end
            end
            
            if i == final_idx then
                file:write("]\n")
            else
                file:write("],\n")
            end
        end
    else
        assert(false, "[CoverGroup] invalid cover point type: " .. self.cover_point_type)
    end

    file:write("}")
    file:close()
end

return CoverGroup
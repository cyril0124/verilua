require 'pl.text'.format_operator()

local type = type
local pairs = pairs
local assert = assert
local tostring = tostring
local setmetatable = setmetatable
local table_insert = table.insert

---@class SVAContext
local SVAContext = {
    unique_stmt_name_vec = {},
    sequence_vec = {},
    property_vec = {},
    content_vec = {},
}

setmetatable(SVAContext, {
    __tostring = function(self)
        local content = ""
        for _, v in pairs(self.sequence_vec) do
            content = content .. v .. "\n\n"
        end

        for _, v in pairs(self.property_vec) do
            content = content .. v .. "\n\n"
        end

        for _, v in pairs(self.content_vec) do
            content = content .. v .. "\n\n"
        end

        return content
    end
})

function SVAContext:cover(cover_name, sequence_or_property)
    local content = ""

    assert(type(cover_name) == "string", "[SVAContext] cover error: cover_name must be a string")
    assert(type(sequence_or_property) == "table", "[SVAContext] cover error: sequence_or_property must be a table")

    -- Make sure the cover_name is unique
    if self.unique_stmt_name_vec[cover_name] then
        pp({unique_stmt_name_vec = self.unique_stmt_name_vec})
        assert(false, "[SVAContext] cover error: cover_name must be unique")
    end
    self.unique_stmt_name_vec[cover_name] = { type = "cover" }

    local t = sequence_or_property.__type
    if t == "Sequence" then
        self.sequence_vec[sequence_or_property.name] = tostring(sequence_or_property)
        content = "%s: cover property (%s);" % {cover_name, tostring(sequence_or_property.name)} -- Provided by `require 'pl.text'.format_operator()`
    elseif t == "Property" then
        self.property_vec[sequence_or_property.name] = tostring(sequence_or_property)
        content = "%s: cover property (%s);" % {cover_name, tostring(sequence_or_property.name)}
    else
        assert(false, "[SVAContext] cover error: sequence_or_property must be a Sequence or Property")
    end

    table_insert(self.content_vec, content)
end

function SVAContext:generate()
    return tostring(self)
end

return SVAContext
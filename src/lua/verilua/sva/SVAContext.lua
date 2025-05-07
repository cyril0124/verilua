require 'pl.text'.format_operator()

local type = type
local pairs = pairs
local assert = assert
local tostring = tostring
local setmetatable = setmetatable
local table_insert = table.insert

---@class (exact) SVAContext
---@field unique_stmt_name_vec table<string, boolean>
---@field sequence_map Sequence[]`
---@field property_map Property[]
---@field content_vec string[]
---@field add_sequence fun(self: SVAContext, sequence: Sequence): SVAContext
---@field add_property fun(self: SVAContext, property: Property): SVAContext
---@field cover fun(self: SVAContext, cover_name: string, sequence_or_property_or_name: string | Sequence | Property): SVAContext
---@field add fun(self: SVAContext, ...: Sequence | Property): SVAContext
---@field generate fun(self: SVAContext): string
local SVAContext = {
    unique_stmt_name_vec = {},
    sequence_map = {},
    property_map = {},
    content_vec = {},
}

setmetatable(SVAContext, {
    __tostring = function(self)
        local content = ""
        for _, v in pairs(self.sequence_map) do
            content = content .. tostring(v) .. "\n\n"
        end

        for _, v in pairs(self.property_map) do
            content = content .. tostring(v) .. "\n\n"
        end

        local content_count = #self.content_vec
        for i, v in ipairs(self.content_vec) do
            content =  content .. "// %d/%d\n" % {i, content_count} .. tostring(v) .. "\n\n"
        end

        return content
    end
})

function SVAContext:add_sequence(sequence)
    assert(type(sequence) == "table", "[SVAContext] input value is not a `table`")
    assert(sequence.__type == "Sequence", "[SVAContext] input value is not a `Sequence`")

    self.sequence_map[sequence.name] = sequence

    return self
end

function SVAContext:add_property(property)
    assert(type(property) == "table", "[SVAContext] input value is not a `table`")
    assert(property.__type == "Property", "[SVAContext] input value is not a `Property`")

    self.property_map[property.name] = property

    return self
end

function SVAContext:add(...)
    local args = {...}

    for _, other in ipairs(args) do
        local t = type(other)
        if t == "table" then
            assert(other.__type == "Sequence" or other.__type == "Property", "[SVAContext] `__concat` error: input value is not a `Sequence` or `Property`")
            if other.__type == "Sequence" then
                ---@cast other Sequence
                self:add_sequence(other)
            elseif other.__type == "Property" then
                ---@cast other Property
                self:add_property(other)
            end
        else
            assert(false, "[SVAContext] `__concat` error: input value is not a `Sequence` or `Property`")
        end
    end

    return self
end

function SVAContext:cover(cover_name, sequence_or_property_or_name)
    local content = ""

    assert(type(cover_name) == "string", "[SVAContext] cover error: `cover_name` must be a string")

    -- Make sure the cover_name is unique   
    if self.unique_stmt_name_vec[cover_name] then
        pp({unique_stmt_name_vec = self.unique_stmt_name_vec})
        assert(false, "[SVAContext] cover error: cover_name must be unique")
    end
    self.unique_stmt_name_vec[cover_name] = true

    local sequence_or_property
    local t = type(sequence_or_property_or_name)
    if t == "string" then
        local maybe_sequence = self.sequence_map[sequence_or_property_or_name]
        local maybe_property = self.property_map[sequence_or_property_or_name]
        sequence_or_property = maybe_sequence or maybe_property

        assert(not(maybe_sequence and maybe_property), "[SVAContext] cover error: `sequence_or_property_or_name`: %s is both a sequence and a property in the current context" % {sequence_or_property_or_name})
        assert(sequence_or_property, "[SVAContext] cover error: `sequence_or_property_or_name`: %s is not available in the current context" % {sequence_or_property_or_name})
    elseif t == "table" then
        local tt = sequence_or_property_or_name.__type
        if tt == "Sequence" then
            local sequence = self.sequence_map[sequence_or_property_or_name.name]
            if sequence then
                sequence_or_property = sequence
            else
                ---@cast sequence_or_property_or_name Sequence
                self:add_sequence(sequence_or_property_or_name)
                sequence_or_property = sequence_or_property_or_name
            end
        elseif tt == "Property" then
            local property = self.property_map[sequence_or_property_or_name.name]
            if property then
                sequence_or_property = property
            else
                ---@cast sequence_or_property_or_name Property
                self:add_property(sequence_or_property_or_name)
                sequence_or_property = sequence_or_property_or_name
            end
        else
            assert(false, tt)
        end
    else
        assert(false, t)
    end

    local tt = sequence_or_property.__type
    if tt == "Sequence" then
        assert(not sequence_or_property.has_port_list, "[SVAContext] cover error: `sequence_or_property_or_name`: %s has a port_list which is not supported by the SVAContext yet" % {sequence_or_property_or_name})
        content = "%s: cover sequence (%s);" % {cover_name, tostring(sequence_or_property.name)} -- Provided by `require 'pl.text'.format_operator()`
    elseif tt == "Property" then
        content = "%s: cover property (%s);" % {cover_name, tostring(sequence_or_property.name)}
    else
        assert(false, "[SVAContext] cover error: sequence_or_property must be a Sequence or Property")
    end

    table_insert(self.content_vec, content)

    return self
end

function SVAContext:generate()
    return tostring(self)
end

return SVAContext
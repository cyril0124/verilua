local class = require "pl.class"
local List = require "pl.List"
local string = require "string"
local stringx = require "pl.stringx"
local texpect = require "TypeExpect"

---@type SVACommon
local common = require "SVACommon"

local pairs = pairs
local ipairs = ipairs
local assert = assert
local f = string.format

---@enum (key) SequenceElementType
local SequenceElementType = {
    None = 0,
    Expr = 1,
    And = 2,
}

---
---@class SequenceElement
---@field typ SequenceElementType
---@field value string
---
---@class SequenceElementList
---@field append fun(self, element: SequenceElement)
---

---
---@class Sequence
---@overload fun(name: string): Sequence
---@field name string
---@field log_name string
---@field values table<string, any>
---@field has_raw boolean
---@field raw_sequence string
---@field verbose boolean
---@field compiled boolean
---@field compiled_sequence string
---@field elements SequenceElementList
---@field _transform_element fun(self, element: SequenceElement): string
---@field _log fun(self, ...: any)
---@field compile fun(self): self
---@field with_expr fun(self, chdl_signal: any): self
---
local Sequence = class()

function Sequence:_init(name)
    texpect.expect_string(name, "name")

    self.__type = "Sequence"
    self.name = name
    self.log_name = "[" .. name .. "]"
    self.verbose = true

    self.values = {}
    self.has_raw = false
    self.raw_sequence = ""
    self.compiled = false
    self.compiled_sequence = ""

    -- self.elements = List()

    self._log = common._log

    if common.unique_name_vec[name] then
        pp({unique_name_vec = common.unique_name_vec})
        assert(false, f("[Sequence] error: name must be unique: %s", name))
    end
    common.unique_name_vec[name] = { type = "Sequence" }
end

function Sequence:__tostring()
    if self.compiled then
        return self.compiled_sequence
    else
        self:compile()
        return self.compiled_sequence
    end
end

function Sequence:with_raw(str)
    if self.has_raw then
        assert(false, "[Sequence] already has raw string")
    end

    if self.compiled then
        assert(false, "[Sequence] compile error: `with_raw` is not allowed after `compile`")
    end

    self.has_raw = true
    self.raw_sequence = str
    return self
end

function Sequence:with_values(values_table)
    texpect.expect_table(values_table, "values_table")
    
    for k, v in pairs(values_table) do
        self.values[k] = v
    end

    return self
end

function Sequence:_transform_element(element)
    if element.typ == "Expr" then
        return "(" .. element.value .. ")"
    else
        assert(false, "Invalid element type " .. element.typ)
    end

    return element.value
end

function Sequence:compile()
    if self.compiled then
        assert(false, "[Sequence] compile error: already compiled")
    end

    if self.has_raw then
        local locals, _ = common.get_locals(3)
        common.expand_locals(locals)

        local raw_sequence = common.render_sva_template(self.raw_sequence, locals, self.values)

        local compiled_sequence = "sequence " .. self.name .. "; " .. raw_sequence .. "; endsequence"
        compiled_sequence = stringx.replace(compiled_sequence, "\n", "")

        self.compiled_sequence = string.gsub(compiled_sequence, "%s+", " ")
    else
        ---@type SequenceElementType
        local last_elemnt_type = "None"

        for i, element in ipairs(self.elements) do
            ---@cast element +SequenceElement

            self:_log("compile: get element %d: %s", i, element.typ)

            -- Check compile error
            if last_elemnt_type == "Expr" and element.typ == "Expr" then
                pp(self.elements)
                assert(false, "[Sequence] compile error: `Expr` cannot be followed by another `Expr`")
            end

            if element.typ == "None" then
                -- do nothing
            elseif element.typ == "Expr" then
                self.compiled_sequence = self.compiled_sequence .. self:_transform_element(element)
            else
                assert(false, "Invalid element type " .. element.typ)
            end

            last_elemnt_type = element.typ
        end

        self.compiled_sequence = "sequence " .. self.name .. ";\n\t" .. self.compiled_sequence .. ";\nendsequence"
    end

    self.compiled = true
    return self
end

-- function Sequence:with_expr(chdl_signal)
--     -- TODO: Check signal width in `[N:M]`
--     if type(chdl_signal) == "string" then
--         local value = self:_render_template(chdl_signal)

--         self.elements:append({typ = "Expr", value = value})
--     else
--         texpect.expect_chdl(chdl_signal, "chdl_signal")

--         self.elements:append({typ = "Expr", value = chdl_signal.fullpath})
--     end

--     return self
-- end

return Sequence
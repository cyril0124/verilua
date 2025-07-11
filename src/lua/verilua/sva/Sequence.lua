require 'pl.text'.format_operator()

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
local table_insert = table.insert

local global_values = {}

---@enum (key) SequenceElementType
local SequenceElementType = {
    None = 0,
    Expr = 1,
    And = 2,
}


---@class (exact) SequenceElement
---@field typ SequenceElementType
---@field value string

---@class (exact) SequenceElementList
---@field append fun(self, element: SequenceElement)

---@class (exact) Sequence
---@overload fun(name: string): Sequence
---@field __type string
---@field name string
---@field log_name string
---@field values table<string, any>
---@field has_raw_sequence boolean
---@field raw_sequence string
---@field has_port_list boolean
---@field port_list table<string>
---@field verbose boolean
---@field compiled boolean
---@field compiled_sequence string
---@field elements SequenceElementList
---@field _transform_element fun(self, element: SequenceElement): string
---@field _log fun(self, ...: any)
---@field compile fun(self): self
---@field with_raw fun(self, str: string): self
---@field with_port_list fun(self, port_list_tbl: table<string>): self
---@field with_expr fun(self, chdl_signal: any): self
---@operator mod(table): Sequence
local Sequence = class()

function Sequence:_init(name)
    texpect.expect_string(name, "name")

    self.__type = "Sequence"
    self.name = name
    self.log_name = "[" .. name .. "]"
    self.verbose = true

    self.values = {}
    self.has_raw_sequence = false
    self.raw_sequence = ""
    self.has_port_list = false
    self.port_list = {}
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

function Sequence:with_port_list(port_list_tbl)
    texpect.expect_table(port_list_tbl, "port_list_tbl")

    for i, port in ipairs(port_list_tbl) do
        texpect.expect_string(port, "port")

        table_insert(self.port_list, port)
    end

    if not self.has_port_list then
        self.has_port_list = #port_list_tbl > 0
    end

    return self
end

function Sequence:with_raw(str)
    if self.has_raw_sequence then
        assert(false, "[Sequence] already has raw string")
    end

    if self.compiled then
        assert(false, "[Sequence] compile error: `with_raw` is not allowed after `compile`")
    end

    self.has_raw_sequence = true
    self.raw_sequence = str
    return self
end

function Sequence:with_values(values_table)
    texpect.expect_table(values_table, "values_table")

    for k, v in pairs(values_table) do
        assert(not self.values[k], "[Sequence] with_values: value already exists: " .. k)
        self.values[k] = v
    end

    return self
end

-- Global version of `with_values` where the values are available in the global scope
function Sequence:with_global_values(values_table)
    texpect.expect_table(values_table, "values_table")

    for k, v in pairs(values_table) do
        assert(not global_values[k], "[Sequence] with_global_values: value already exists: " .. k)
        global_values[k] = v
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

    if self.has_raw_sequence then
        local locals, _ = common.get_locals(3)
        common.expand_locals(locals)

        local raw_sequence = common.render_sva_template(self.raw_sequence, locals, self.values, global_values)

        local port_list_str = ""
        if #self.port_list > 0 then
            port_list_str = table.concat(self.port_list, ", ")
        end

        local compiled_sequence = "sequence $name($port_list); $raw_sequence; endsequence" % {name = self.name, port_list = port_list_str, raw_sequence = raw_sequence}
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

        -- TODO: Port list
        if self.has_port_list then
            assert(false, "TODO: Port list")
        end

        self.compiled_sequence = "sequence " .. self.name .. ";\n\t" .. self.compiled_sequence .. ";\nendsequence"
    end

    self.compiled = true
    return self
end

function Sequence:__mod(other)
    self:with_values(other)
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
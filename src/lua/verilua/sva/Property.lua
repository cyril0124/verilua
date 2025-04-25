require 'pl.text'.format_operator()

local class = require "pl.class"
local string = require "string"
local common = require "SVACommon"
local stringx = require "pl.stringx"
local texpect = require "TypeExpect"

local pairs = pairs
local assert = assert
local f = string.format

local global_values = {}
local tmp_global_values_key = {}

---@class (exact) Property
---@overload fun(name: string): Property
---@field __type string
---@field name string
---@field log_name string
---@field values table<string, any>
---@field has_raw boolean
---@field raw_property string
---@field has_port_list boolean
---@field port_list table<string>
---@field verbose boolean
---@field compiled boolean
---@field compiled_property string
---@field _log fun(self, ...: any)
---@field compile fun(self): self
local Property = class()

function Property:_init(name)
    texpect.expect_string(name, "name")

    self.__type = "Property"
    self.name = name
    self.log_name = "[" .. name .. "]"
    self.verbose = true

    self.values = {}
    self.has_raw = false
    self.raw_property = ""

    self.has_port_list = false
    self.port_list = {}

    self.compiled = false
    self.compiled_property = ""

    self._log = common._log

    if common.unique_name_vec[name] then
        pp({unique_name_vec = common.unique_name_vec})
        assert(false, f("[Property] error: name must be unique: %s", name))
    end
    common.unique_name_vec[name] = { type = "Property" }
end

function Property:__tostring()
    if self.compiled then
        return self.compiled_property
    else
        self:compile()
        return self.compiled_property
    end
end

function Property:with_values(values_table)
    texpect.expect_table(values_table, "values_table")
    
    for k, v in pairs(values_table) do
        assert(not self.values[k], "[Property] with_values: value already exists: " .. k)
        self.values[k] = v
    end

    return self
end

-- Global version of `with_values` where the values are available in the global scope
function Property:with_global_values(values_table)
    texpect.expect_table(values_table, "values_table")
    
    for k, v in pairs(values_table) do
        assert(not global_values[k], "[Property] with_global_values: value already exists: " .. k)
        global_values[k] = v
    end

    return self
end

function Property:_get_global_values()
    return global_values
end

-- Adds temporary global values from a given table and returns the key used for storage.
function Property:with_tmp_global_values(values_table)
    texpect.expect_table(values_table, "values_table")

    local key = 1
    for _, _ in pairs(tmp_global_values_key) do
        key = key + 1
    end

    for k, v in pairs(values_table) do
        assert(not global_values[k], "[Property] with_tmp_global_values: value already exists: " .. k)
        global_values[k] = v

        if not tmp_global_values_key[key] then
            tmp_global_values_key[key] = {}
        end
        table.insert(tmp_global_values_key[key], k)
    end

    return key
end

-- Removes temporary global values associated with the provided key.
function Property:remove_tmp_global_values(key)
    texpect.expect_number(key, "key")

    for _, v in ipairs(tmp_global_values_key[key]) do
        global_values[v] = nil
    end
    tmp_global_values_key[key] = nil
end

function Property:with_raw(str)
    if self.has_raw then
        assert(false, "[Property] already has raw string")
    end

    if self.compiled then
        assert(false, "[Property] compile error: `with_raw` is not allowed after `compile`")
    end

    self.has_raw = true
    self.raw_property = str
    return self
end

function Property:compile()
    if self.compiled then
        assert(false, "[Property] compile error: already compiled")
    end

    if self.has_raw then
        local locals, _ = common.get_locals(3)
        common.expand_locals(locals)

        local raw_property = common.render_sva_template(self.raw_property, locals, self.values, global_values)
        
        local port_list_str = ""
        if #self.port_list > 0 then
            port_list_str = table.concat(self.port_list, ", ")
            port_list_str = port_list_str:sub(1, -2)
        end

        local compiled_property = "property $name($port_list); $raw_property; endproperty" % {name = self.name, port_list = port_list_str, raw_property = raw_property }
        compiled_property = stringx.replace(compiled_property, "\n", "")

        self.compiled_property = string.gsub(compiled_property, "%s+", " ")
    else
        assert(false, "TODO: compile property")
    end

    self.compiled = true
    return self
end

function Property:__mod(other)
    self:with_values(other)
    return self
end

return Property
local stringx = require "pl.stringx"
local template = require "SVATemplate"

local type = type
local pairs = pairs
local assert = assert
local f = string.format
local tostring = tostring
local setmetatable = setmetatable

---@class SVAContext.property
---@field __type "Property"
---@field name string

---@class SVAContext.sequence
---@field __type "Sequence"
---@field name string

---@class SVAContext.add.params
---@field name string
---@field expr string
---@field cov_type? "sequence" | "property"
---@field envs? table<string, any>

---@class (exact) SVAContext
---@field private unique_stmt_name_map table<string, boolean>
---@field private global_envs table<string, any>
---@field private sequence_vec string[]
---@field private property_vec string[]
---@field private content_vec string[]
---@field with_global_envs fun(self: SVAContext, envs: table<string, any>): SVAContext
---@field add fun(self: SVAContext, typ: "cover" | "assert" | "property" | "sequence"): fun(params: SVAContext.add.params): SVAContext.property | SVAContext.sequence | nil
---@field clean fun(self: SVAContext): SVAContext
---@field generate fun(self: SVAContext): string
local SVAContext = {
    unique_stmt_name_map = {},
    global_envs = {},
    sequence_vec = {},
    property_vec = {},
    content_vec = {},
}

setmetatable(SVAContext, {
    __tostring = function(self)
        local content = ""
        for _, v in ipairs(self.sequence_vec) do
            content = content .. tostring(v) .. "\n\n"
        end

        for _, v in ipairs(self.property_vec) do
            content = content .. tostring(v) .. "\n\n"
        end

        local content_count = #self.content_vec
        for i, v in ipairs(self.content_vec) do
            content = content .. f("// %d/%d\n", i, content_count) .. tostring(v) .. "\n\n"
        end

        return content
    end
})

local function process_content(content)
    -- Squash multiple spaces and newlines
    return stringx.replace(content, "\n", ""):gsub("%s+", " ")
end

function SVAContext:generate()
    return tostring(self)
end

_G.cat = nil -- Mark as used
function SVAContext:add(typ)
    local old_cat = _G.cat

    -- Concat tables
    _G.cat = setmetatable({}, {
        __add = function(this, other)
            return this
        end,
        __call = function(this, ...)
            local envs_vec = { ... }
            for _, envs in ipairs(envs_vec) do
                if type(envs) == "table" then
                    for key, value in pairs(envs) do
                        this[key] = value
                    end
                else
                    assert(false, "[SVAContext] add error: `envs` should be a table")
                end
            end
            return this
        end
    })

    ---@param params SVAContext.add.params
    return function(params)
        assert(type(params) == "table", "[SVAContext] add error: `params` should be a table")
        assert(type(params.name) == "string", "[SVAContext] add error: `params.name` should be a string")
        assert(type(params.expr) == "string", "[SVAContext] add error: `params.expr` should be a string")

        local final_envs = cat(params.envs or {}, self.global_envs)
        for _, v in pairs(final_envs) do
            if type(v) == "table" and v.__type then
                if v.__type == "Sequence" then
                    ---@cast v SVAContext.sequence
                    assert(
                        self.unique_stmt_name_map[v.name],
                        "[SVAContext] add error: `params.envs` contains a `Sequence` that is not in the current context"
                    )
                elseif v.__type == "Property" then
                    ---@cast v SVAContext.property
                    assert(
                        self.unique_stmt_name_map[v.name],
                        "[SVAContext] add error: `params.envs` contains a `Property` that is not in the current context"
                    )
                end
            end
        end

        assert(
            not self.unique_stmt_name_map[params.name],
            f("[SVAContext] `params.name`(%s) is not unique", params.name)
        )
        self.unique_stmt_name_map[params.name] = true

        local ret, err = template.substitute(params.expr, final_envs)
        if err then
            assert(false, err)
        end

        if old_cat then
            _G.cat = old_cat
        else
            _G.cat = nil
        end

        if typ == "cover" then
            local cov_type = "property"
            if params.cov_type then
                assert(
                    params.cov_type == "sequence" or params.cov_type == "property",
                    "[SVAContext] cover error: `cov_type` should be `sequence` or `property`"
                )
                cov_type = assert(params.cov_type)
            end

            local pre_content_name = f("_GEN_%s_%s", params.name, cov_type:upper())
            local pre_content = process_content(f("%s %s(); %s; end%s", cov_type, pre_content_name, ret, cov_type))
            local content = pre_content .. "\n" .. f("%s: cover %s (%s);", params.name, cov_type, pre_content_name)
            self.content_vec[#self.content_vec + 1] = content
            self.unique_stmt_name_map[pre_content_name] = true
            return
        elseif typ == "assert" then
            local pre_content_name = f("_GEN_%s_PROPERTY", params.name)
            local pre_content = process_content(f("property %s(); %s; endproperty", pre_content_name, ret))
            local content = pre_content .. "\n" .. f("%s: assert property (%s);", params.name, pre_content_name)
            self.content_vec[#self.content_vec + 1] = content
            self.unique_stmt_name_map[pre_content_name] = true
            return
        elseif typ == "property" then
            local content = f("property %s(); %s; endproperty", params.name, ret)
            self.property_vec[#self.property_vec + 1] = process_content(content)

            ---@type SVAContext.property
            local property = {
                __type = "Property",
                name = params.name,
            }
            self.global_envs[params.name] = property
            return property
        elseif typ == "sequence" then
            local content = f("sequence %s(); %s; endsequence", params.name, ret)
            self.sequence_vec[#self.sequence_vec + 1] = process_content(content)

            ---@type SVAContext.sequence
            local sequence = {
                __type = "Sequence",
                name = params.name,
            }
            self.global_envs[params.name] = sequence
            return sequence
        else
            assert(false, "TODO: " .. typ)
        end

        assert(false, "Should not reach here")
    end
end

function SVAContext:with_global_envs(envs)
    for key, value in pairs(envs) do
        self.global_envs[key] = value
    end
    return self
end

function SVAContext:clean()
    self.unique_stmt_name_map = {}
    self.global_envs = {}
    self.sequence_vec = {}
    self.property_vec = {}
    self.content_vec = {}
    return self
end

return SVAContext

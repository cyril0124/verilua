local debug = require "debug"
local SVATemplate = require "verilua.sva.SVATemplate"

local type = type
local pairs = pairs
local print = print
local assert = assert
local rawget = rawget
local tostring = tostring
local f = string.format

---@class SVACommon
local common = {
    unique_name_vec = {}
}

function common.get_locals(level)
    local i = 1
    local locals = {}
    while true do
        local name, value = debug.getlocal(level, i)
        if not name then break end
        locals[name] = value
        i = i + 1
    end
    return locals, i
end

function common.expand_locals(locals)
    for k, v in pairs(locals) do
        if type(v) == "table" and rawget(v, "__type") == "CallableHDL" then
            locals[k] = v.fullpath
        end
    end
end

function common.serialize_value(value, name)
    local t = type(value)
    if t == "table" then 
        if value.__type == "CallableHDL" then
            return value.fullpath
        elseif value.__type == "ProxyTableHandle" then
            return value:chdl().fullpath
        elseif value.__type == "Sequence" then
            assert(false)
            return tostring(value)
        else
            assert(false, "[SVACommon] Invalid value: " .. tostring(value) .. " name: " .. name)
        end
    elseif t == "number" then
        return value
    else
        assert(false, "[SVACommon] Invalid value: " .. tostring(value) .. " name: " .. name)
    end

    return ""
end

function common.render_sva_template(template, locals, values, global_values)
    local parents = locals

    -- Merge values and global_values
    for k, v in pairs(values) do
        parents[k] = v
    end
    for k, v in pairs(global_values) do
        parents[k] = v
    end

    local _chunk_name = rawget(parents, "_chunk_name")
    local _escape = rawget(parents, "_escape")
    local _inline_escape = rawget(parents, "_inline_escape")
    local _brackets = rawget(parents, "_brackets")
    local _debug = rawget(parents, "_debug")

    local ret, err, _ = SVATemplate.substitute(template, {
        _chunk_name = _chunk_name,
        _escape = _escape,
        _inline_escape = _inline_escape,
        _brackets = _brackets,
        _debug = _debug,
        _parent = parents,
    })

    if err then
        assert(false, "Failed to render template, error: " .. tostring(err))
    end

    return ret
end

function common._log(this, ...)
    if this.verbose then
        print(this.log_name, f(...))
    end
end

function common.gen_cover(this, name)
    local content = ""

    if this.__type == "Sequence" then
        content = this.name
    end

    return f("%s: cover property (%s);", name, tostring(this))
end

return common
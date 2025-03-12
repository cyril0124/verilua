local debug = require "debug"
local stringx = require "pl.stringx"

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

function common.render_template(str)
    local locals, locals_len = common.get_locals(4)
    common.expand_locals(locals)

    if locals_len > 0 then
        str = str:gsub("{{(.-)}}", function(key)
            local value = locals[key]
            assert(value, f("[common.render_template] key not found: %s\n\ttemplate_str is: %s\n", key, str))
            return tostring(value)
        end)
    end

    return str
end

function common.serialize_value(value, name)
    local t = type(value)
    if t == "table" then 
        if value.__type == "CallableHDL" then
            return value.fullpath
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

function common.render_sva_template(template, locals, values)
    return template:gsub("{{(.-)}}", function(key)
        local is_agg_signal = stringx.lfind(key, ".") ~= nil

        local value
        if is_agg_signal then
            local signal_vec = stringx.split(key, ".")
            value = locals[signal_vec[1]]

            if not value then
                value = values[signal_vec[1]]
            end

            for i = 2, #signal_vec do
                value = value[signal_vec[i]]
            end

            assert(value, f("[SVACommon] render_sva_template error: Unknown aggregate signal: %s\n\ttemplate_str is: %s\n", key, template))

            value = common.serialize_value(value, key)
        else
            value = locals[key]
        end

        if not value then
            value = common.serialize_value(values[key], key)
        end

        assert(value, f("[SVACommon] render_sva_template error: Unknown signal: %s\n\ttemplate_str is: %s\n", key, template))
        return tostring(value)
    end)
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
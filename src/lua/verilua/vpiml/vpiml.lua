local vpiml
local handle_cache = {}

if cfg.simulator == "nosim" then
    vpiml = require "VpimlNosim"
else
    vpiml = require "VpimlNormal"
end

local vpiml_handle_by_name = vpiml.vpiml_handle_by_name
local vpiml_handle_by_name_safe = vpiml.vpiml_handle_by_name_safe

---@diagnostic disable-next-line: duplicate-set-field
vpiml.vpiml_handle_by_name = function(name)
    local handle = handle_cache[name]
    if handle then
        return handle
    end

    handle = vpiml_handle_by_name(name)
    handle_cache[name] = handle
    return handle
end

---@diagnostic disable-next-line: duplicate-set-field
vpiml.vpiml_handle_by_name_safe = function(name)
    local handle = handle_cache[name]
    if handle then
        assert(handle ~= -1)
        return handle
    end

    handle = vpiml_handle_by_name_safe(name)
    if handle ~= -1 then
        handle_cache[name] = handle
    end
    return handle
end

return vpiml

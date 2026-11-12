local vpiml
local handle_cache = {}

local sim = cfg.simulator
if sim == "nosim" then
    vpiml = require "verilua.vpiml.VpimlNosim"
elseif sim == "luasim" then
    vpiml = require "verilua.vpiml.VpimlNormal"

    ---@cast vpiml verilua.vpiml.VpimlNormal
    vpiml = require("verilua.luasim.Api").patch_vpiml(vpiml)
else
    vpiml = require "verilua.vpiml.VpimlNormal"
end

local vpiml_handle_by_name = assert(vpiml.vpiml_handle_by_name,
    "backend module does not provide vpiml_handle_by_name")
local vpiml_handle_by_name_safe = assert(vpiml.vpiml_handle_by_name_safe,
    "backend module does not provide vpiml_handle_by_name_safe")

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
    return handle --[[@as integer]]
end

---@cast vpiml verilua.vpiml.VpimlNormal

return vpiml

---@diagnostic disable: unnecessary-assert

local SignalDB = require("SignalDB"):init()

local f = string.format

local vpiml = {}

---@type table<integer, verilua.utils.SignalInfo>
local handle_to_signal_info_map = {}
local handle_allocator = 0

local function alloc_handle(signal_info)
    local handle = handle_allocator
    handle_allocator = handle_allocator + 1

    assert(not handle_to_signal_info_map[handle], f("[VpimlNosim] [alloc_handle] Handle `%d` already exists", handle))
    handle_to_signal_info_map[handle] = signal_info

    return handle
end

vpiml.vpiml_get_top_module = function()
    return SignalDB:get_top_module()
end

vpiml.vpiml_get_simulator_auto = function()
    assert(false, "TODO:")
end

vpiml.vpiml_handle_by_name = function(name)
    local signal_info = SignalDB:get_signal_info(name)
    assert(signal_info, f("[VpimlNosim] [vpiml_handle_by_name] No handle found for `%s`", name))
    return alloc_handle(signal_info)
end

vpiml.vpiml_handle_by_name_safe = function(name)
    local signal_info = SignalDB:get_signal_info(name)
    if not signal_info then
        return -1
    end
    return alloc_handle(signal_info)
end

vpiml.vpiml_get_hdl_type = function(handle)
    local signal_info = handle_to_signal_info_map[handle]
    assert(signal_info, f("[VpimlNosim] [vpiml_get_hdl_type] No signal info found for handle `%d`", handle))
    return signal_info[3]
end

vpiml.vpiml_get_signal_width = function(handle)
    local signal_info = handle_to_signal_info_map[handle]
    assert(signal_info, f("[VpimlNosim] [vpiml_get_signal_width] No signal info found for handle `%d`", handle))
    return signal_info[2]
end

return setmetatable(vpiml, {
    __index = function(_t, k)
        return function(...)
            assert(false, f("[VpimlNosim] `%s` is not implemented", k))
        end
    end
})

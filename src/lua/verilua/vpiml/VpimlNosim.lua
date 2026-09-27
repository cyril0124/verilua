---@diagnostic disable: unnecessary-assert

local SignalDB = require "verilua.utils.SignalDB"
SignalDB:init()

local f = string.format

---@type table<integer, verilua.utils.SignalInfo>
local handle_to_signal_info_map = {}
local handle_allocator = 0

--- Allocate a dense handle for `signal_info`.
---@param signal_info verilua.utils.SignalInfo
---@return integer
local function alloc_handle(signal_info)
    local handle = handle_allocator
    handle_allocator = handle_allocator + 1

    assert(not handle_to_signal_info_map[handle], f("[VpimlNosim] [alloc_handle] Handle `%d` already exists", handle))
    handle_to_signal_info_map[handle] = signal_info

    return handle
end

--- Get the `SignalInfo` bound to `handle`.
--- In `nosim` there is no simulator handle, so handles are the dense integers allocated above.
---@param handle verilua.handles.ComplexHandleRaw
---@param caller string Name of the `vpiml_*` function reporting the error
---@return verilua.utils.SignalInfo
local function get_signal_info(handle, caller)
    local signal_info = handle_to_signal_info_map[handle]
    assert(signal_info, f("[VpimlNosim] [%s] No signal info found for handle `%d`", caller, handle))
    return signal_info
end

---@class verilua.vpiml.VpimlNosim
local vpiml = {}

---@type fun(): string
vpiml.vpiml_get_top_module = function()
    return SignalDB:get_top_module()
end

--- The `nosim` backend is chosen from `cfg.simulator == "nosim"`, so detection is trivial here.
---@type fun(): string
vpiml.vpiml_get_simulator_auto = function()
    return "nosim"
end

--- Safe version of `vpiml_handle_by_name`, returns `-1` when the signal does not exist.
---@type fun(name: string): verilua.handles.ComplexHandleRaw
vpiml.vpiml_handle_by_name_safe = function(name)
    local signal_info = SignalDB:get_signal_info(name)
    if not signal_info then
        return -1
    end
    return alloc_handle(signal_info)
end

---@type fun(name: string): verilua.handles.ComplexHandleRaw
vpiml.vpiml_handle_by_name = function(name)
    local handle = vpiml.vpiml_handle_by_name_safe(name)
    if handle == -1 then
        assert(false, f("[VpimlNosim] [vpiml_handle_by_name] No handle found for `%s`", name))
    end
    return handle
end

---@type fun(handle: verilua.handles.ComplexHandleRaw): string
vpiml.vpiml_get_hdl_type = function(handle)
    return get_signal_info(handle, "vpiml_get_hdl_type")[3]
end

--- `SignalDB` stores widths as plain Lua numbers.
---@type fun(handle: verilua.handles.ComplexHandleRaw): integer
vpiml.vpiml_get_signal_width = function(handle)
    return get_signal_info(handle, "vpiml_get_signal_width")[2] --[[@as integer]]
end

--- Get simulation time precision as exponent (e.g., -9 for ns, -12 for ps)
--- In `nosim` backend, default to ns (-9)
---@type fun(): integer
vpiml.vpiml_get_time_precision = function()
    return -9
end

--- Get current simulation time in steps
--- In `nosim` backend, always returns 0
---@type fun(): integer
vpiml.vpiml_get_sim_time = function()
    return 0
end

--- `vpiml_*` interfaces that `nosim` accepts and ignores.
---
--- `nosim` has no simulation time and never drives a signal, so a stimulus write has no observer
--- and a callback registration can never fire. A time-0 script that calls them runs to the end.
--- Prefixes are matched rather than exact names because the `*_multi_beat_N` variants are
--- generated.
---@type string[]
local IGNORED_INTERFACE_PREFIXES = {
    "vpiml_set_",
    "vpiml_force_",
    "vpiml_release_",
    "vpiml_shuffled_range_",
    "vpiml_reset_shuffled_range",
    "vpiml_register_",
}

---@param name string
---@return boolean
local function is_ignored_interface(name)
    for i = 1, #IGNORED_INTERFACE_PREFIXES do
        local prefix = IGNORED_INTERFACE_PREFIXES[i]
        if string.sub(name, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function ignored() end

--- Interfaces that need a simulator are not implemented: a value read has no answer in `nosim`,
--- and a native clock has no time to advance.
local NOT_IMPLEMENTED_HINT = "nosim has no simulation time and never reads or drives signal values; " ..
    "run this script with a real simulator"

return setmetatable(vpiml, {
    __index = function(_t, k)
        if type(k) == "string" and is_ignored_interface(k) then
            return ignored
        end
        return function(...)
            assert(false, f("[VpimlNosim] `%s` is not implemented: %s", k, NOT_IMPLEMENTED_HINT))
        end
    end
})

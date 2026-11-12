local ffi = require "ffi"
local C = ffi.C

ffi.cdef [[
    typedef struct { uint32_t stopped, readonly, failed, sealed; } luasim_status;
    const volatile luasim_status *luasim_get_status(void);
    int luasim_declare(const char *path, int width);
    void luasim_configure(int precision, uint64_t max_delta, uint64_t max_time, int has_max_time);
    const char *luasim_error(void);
    int luasim_dump(const char *path);
    void luasim_dump_enabled(int enabled);
    void luasim_set_top(const char *top);
    void luasim_seal(void);
]]

---@class verilua.luasim.Config
---@field max_time? integer Absolute step limit; reaching a later scheduled time is an error.
---@field max_delta_cycles? integer Zero-time dispatch/update round limit, default 10000.

local status = C.luasim_get_status()
local Api = {}

--- Validate a safe integer with an optional lower bound (default zero).
---@param value any
---@param label string
---@param minimum? integer
---@return integer
function Api.integer(value, label, minimum)
    assert(type(value) == "number" and value == math.floor(value)
        and value >= (minimum or 0) and value <= 9007199254740991,
        "[luasim] " .. label .. " must be a safe integer >= " .. tostring(minimum or 0))
    return value --[[@as integer]]
end

--- Raise the latched engine failure, if any, at the current Lua call site.
function Api.check()
    if status.failed ~= 0 then error("[luasim] " .. ffi.string(C.luasim_error()), 2) end
end

--- Push the time precision and the engine limits into the native engine.
---@param options? verilua.luasim.Config Defaults to an empty option set.
---@param precision integer
function Api.configure(options, precision)
    options = options or {}
    -- `uint64_t` cdata reaches the engine exactly; Lua numbers must stay exact.
    local cycles = options.max_delta_cycles
    if cycles == nil then
        cycles = 10000
    elseif not ffi.istype("uint64_t", cycles) then
        cycles = Api.integer(cycles, "max_delta_cycles", 1)
    end
    local limit = options.max_time
    if limit == nil then
        limit = 0
    elseif not ffi.istype("uint64_t", limit) then
        limit = Api.integer(limit, "max_time", 1)
    end
    C.luasim_configure(precision, cycles, limit, options.max_time ~= nil and 1 or 0)
    Api.check()
end

--- Create one packed signal before the first task starts.
---@param path string
---@param width integer
function Api.declare(path, width)
    assert(type(path) == "string" and not path:find("%z"), "[luasim] invalid signal path")
    Api.integer(width, "signal width", 1)
    assert(width <= 2147483647, "[luasim] signal width must fit signed 32-bit VPI size")
    C.luasim_declare(path, width)
    Api.check()
end

--- Whether the engine already closed the declaration set.
---@return boolean
function Api.is_sealed()
    return status.sealed ~= 0
end

--- Close the declaration set and write the waveform header.
function Api.seal()
    C.luasim_seal()
end

--- Open the waveform file and start recording changes.
---@param path string
function Api.dump(path)
    C.luasim_dump(path)
    Api.check()
end

--- Toggle waveform recording without closing the file.
---@param enabled boolean
function Api.dump_enabled(enabled)
    C.luasim_dump_enabled(enabled and 1 or 0)
    Api.check()
end

---@param value string
---@param base? integer
---@return string
local function validate_string(value, base)
    assert(type(value) == "string", "[luasim] signal string must be a string")
    value = value:lower():gsub("_", "")
    if not base then
        local prefix, digits = value:match("^0([xbd])(.+)$")
        if prefix then
            base = ({ x = 16, b = 2, d = 10 })[prefix]
            value = assert(digits)
        else
            base = 10
        end
    end
    assert(#value > 0 and not value:find("[xz?]"), "[luasim] X/Z or empty values are unsupported")
    for i = 1, #value do
        local digit = tonumber(value:sub(i, i), 16)
        assert(digit and digit < base, "[luasim] invalid signal string")
    end
    return value
end

--- Validate the complete declaration before publishing any native signal.
---@param options verilua.luasim.SignalOptions
function Api.validate_signal_options(options)
    assert(type(options) == "table", "[luasim] signal options must be a table")
    for key in pairs(options) do
        assert(key == "width" or key == "initial", "[luasim] unsupported signal option: " .. tostring(key))
    end
    local width = Api.integer(options.width, "signal width", 1)
    assert(width <= 2147483647, "[luasim] signal width must fit signed 32-bit VPI size")
    local initial = options.initial
    if initial == nil then return end
    if type(initial) == "string" then
        validate_string(initial)
    elseif type(initial) == "table" then
        local count = math.ceil(width / 32)
        assert(#initial == count, "[luasim] incorrect number of signal words")
        for index = 1, count do Api.integer(initial[index], "signal word", -9007199254740991) end
    elseif type(initial) == "number" then
        Api.integer(initial, "signal value", -9007199254740991)
    else
        assert(type(initial) == "cdata" and ffi.istype("uint64_t", initial),
            "[luasim] initial value must be an integer, uint64_t, words, or string")
    end
end

--- Apply luasim value and phase validation to the common VPI entry points.
---@param vpiml verilua.vpiml.VpimlNormal
---@return verilua.vpiml.VpimlNormal
function Api.patch_vpiml(vpiml)
    assert(_G.cfg.mode == "normal", "[luasim] unsupported scheduler mode: " .. tostring(_G.cfg.mode))
    local function unsupported_dpi() error("[luasim] DPI is unsupported", 2) end
    package.preload["verilua.utils.DpiExporter"] = unsupported_dpi
    package.preload["DpiExporter"] = unsupported_dpi

    local widths = {}
    for name, original in pairs(vpiml) do
        if name:find("^vpiml_force")
            or name:find("^vpiml_release")
            or name == "vpiml_set_freeze"
            or name == "vpiml_set_imm_freeze"
            or name:find("_always$")
            or name == "vpiml_handle_by_index" then
            vpiml[name] = function()
                error("[luasim] unsupported operation: " .. name, 2)
            end
        elseif name == "vpiml_set_shuffled" or name == "vpiml_set_imm_shuffled" then
            vpiml[name] = function(handle)
                assert(status.readonly == 0, "[luasim] writes are forbidden in read-only phase")
                original(handle)
                Api.check()
            end
        elseif name:find("^vpiml_set") then
            local base
            if name:find("hex_str$") then
                base = 16
            elseif name:find("bin_str$") then
                base = 2
            elseif name:find("dec_str$") then
                base = 10
            end
            local string_setter = name:find("str$") ~= nil

            vpiml[name] = function(handle, value, ...)
                -- A deferred write waits in the pending queue, so the phase and the value form
                -- are validated here rather than when the engine finally applies it.
                assert(status.readonly == 0, "[luasim] writes are forbidden in read-only phase")
                if string_setter then
                    -- `0x`/`0b`/`0d` prefixes pick the base downstream, so only the
                    -- setters that already know their base may drop the prefix.
                    if base then
                        value = validate_string(value, base)
                    else
                        validate_string(value)
                    end
                end
                original(handle, value, ...)
                Api.check()
            end
        elseif name == "vpiml_register_time_callback" then
            vpiml[name] = function(delay, id)
                Api.integer(delay, "timer delay")
                assert(not (status.readonly ~= 0 and delay == 0), "[luasim] zero-delay forbidden in read-only phase")
                original(delay, id)
                Api.check()
            end
        elseif name:find("^vpiml_register.*_posedge_") or name:find("^vpiml_register.*_negedge_") then
            vpiml[name] = function(handle, id)
                local width = widths[handle]
                if width == nil then
                    width = vpiml.vpiml_get_signal_width(handle)
                    widths[handle] = width
                end
                assert(width == 1, "[luasim] posedge/negedge require a one-bit signal")
                original(handle, id)
                Api.check()
            end
        elseif name == "vpiml_register_rw_synch_callback" then
            vpiml[name] = function(id)
                assert(status.readonly == 0, "[luasim] cannot await_rw from read-only phase")
                original(id)
                Api.check()
            end
        elseif name == "vpiml_register_rd_synch_callback" or name == "vpiml_register_next_sim_time_callback" then
            vpiml[name] = function(id)
                original(id)
                Api.check()
            end
        elseif name:find("^vpiml_register") then
            vpiml[name] = function(value, id)
                original(value, id)
                Api.check()
            end
        end
    end
    vpiml.vpiml_get_top_module = function()
        return (_G.cfg.top or "tb_top") --[[@as string]]
    end
    require("verilua.luasim.Sim").configure()
    return vpiml
end

return Api

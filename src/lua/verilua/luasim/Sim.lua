local ffi = require "ffi"
local Api = require "verilua.luasim.Api"
local C = ffi.C

---@class verilua.luasim.SignalOptions
---@field width integer Positive packed width representable by signed 32-bit VPI size.
---@field initial? integer|uint64_t|integer[]|string Initial two-state value, default zero.

--- Default time precision: 1 ps, as an exponent of seconds.
local DEFAULT_TIME_PRECISION = -12

local Sim = {}
local configured = false
local declaring = false

local BITS_PER_WORD = 32
-- 2^32; dividing a `uint64_t` by this yields its high word.
local UINT32_RANGE = 4294967296ULL

---@param signal verilua.handles.CallableHDL
---@param width integer
---@param initial integer|uint64_t|integer[]|string
local function apply_initial(signal, width, initial)
    if type(initial) == "string" then
        require("verilua.vpiml.vpiml").vpiml_set_imm_value_str(signal.hdl, initial)
    elseif type(initial) == "table" then
        if width <= BITS_PER_WORD then
            signal:set_imm(assert(initial[1], "[luasim] initial words must not be empty"))
        else
            signal:set_imm(initial)
        end
    elseif width <= 2 * BITS_PER_WORD then
        signal:set_imm(initial)
    else
        local value = ffi.cast("uint64_t", initial)
        local words = {
            tonumber(ffi.cast("uint32_t", value)),
            tonumber(ffi.cast("uint32_t", value / UINT32_RANGE)),
        }
        for index = 3, math.ceil(width / BITS_PER_WORD) do
            words[index] = 0
        end
        signal:set_imm(words)
    end
end

--- Declare signals inside `fn`; declarations close as soon as it returns.
---
--- e.g.
--- ```lua
--- local luasim = require "verilua.luasim.Sim"
--- luasim.declare(function()
---     luasim.signal("tb_top.valid", { width = 1, initial = 0 })
---     luasim.signal("tb_top.data", { width = 128, initial = "0x1234" })
--- end)
--- ```
---@param fn fun()
function Sim.declare(fn)
    assert(_G.cfg.simulator == "luasim", "Sim.declare requires the luasim backend")
    assert(type(fn) == "function", "[luasim] Sim.declare expects a function")
    assert(not Api.is_sealed(), "[luasim] signal declarations are already closed")
    assert(_G.scheduler:get_curr_task_id() == 0, "[luasim] signals cannot be declared inside a task")
    if not configured then
        Sim.configure()
    end
    declaring = true
    local ok, err = pcall(fn)
    declaring = false
    -- Close even after a failure so a half-built block cannot be extended later.
    Api.seal()
    if not ok then
        error(err, 0)
    end
end

--- Configure the engine limits; omitted fields use their defaults.
---@param options? verilua.luasim.Config Engine limits; omitted fields keep their defaults.
function Sim.configure(options)
    local cfg = _G.cfg
    assert(not cfg.is_hse, "[luasim] HSE/DPI mode is unsupported")
    local settings = options or {}
    assert(type(settings) == "table", "[luasim] configuration must be a table")
    local precision = cfg.time_precision or DEFAULT_TIME_PRECISION
    assert(type(precision) == "number" and precision == math.floor(precision)
        and precision >= -15 and precision <= 0, "[luasim] time_precision must be an integer from -15 to 0")
    Api.configure(settings, precision --[[@as integer]])
    C.luasim_set_top(cfg.top or "tb_top")
    Api.check()
    configured = true
end

--- Declare a native packed signal. Only valid inside the `Sim.declare` callback.
---
--- e.g.
--- ```lua
--- local luasim = require "verilua.luasim.Sim"
--- local valid, data
--- luasim.declare(function()
---     valid = luasim.signal("tb_top.valid", { width = 1, initial = 0 })
---     data = luasim.signal("tb_top.data", { width = 128, initial = "0x1234" })
--- end)
---
--- fork {
---     function()
---         valid:set(1)
---         await_rw()
---         assert(valid:get() == 1)
---         data:set_hex_str("1234")
---         await_rw()
---         assert(tonumber(data:get_hex_str(), 16) == 0x1234)
---     end
--- }
--- ```
---@param path string Fully qualified signal path.
---@param options verilua.luasim.SignalOptions
---@return verilua.handles.CallableHDL
function Sim.signal(path, options)
    assert(_G.cfg.simulator == "luasim", "Sim.signal requires the luasim backend")
    assert(declaring, "[luasim] declare signals inside Sim.declare")
    Api.validate_signal_options(options)
    Api.declare(path, options.width)
    local CallableHDL = require "verilua.handles.LuaCallableHDL"
    local name = assert(path:match("[^.]+$"), "[luasim] signal path must end with a name: " .. path)
    local signal = CallableHDL(path, name)
    if options.initial ~= nil then
        apply_initial(signal, options.width, options.initial)
    end
    return signal
end

return Sim

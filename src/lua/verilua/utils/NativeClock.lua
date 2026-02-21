--- NativeClock - A high-performance clock driver for Verilua
---
--- NativeClock drives clock signals entirely in native code (Rust)
--- without returning to Lua for each edge, significantly reducing
--- overhead for pure clock driving.
---
--- Example usage:
--- ```lua
--- local dut = verilua.dut
--- local clk = NativeClock(dut.clock:chdl())
--- clk:start(10, "ns")          -- 10ns period, 50% duty cycle
--- clk:start(10, "ns", {high = 3, start_high = false})  -- custom options
--- clk:stop()
--- clk:destroy()
--- ```

local class = require "pl.class"
local texpect = require "verilua.TypeExpect"
local vpiml = require "verilua.vpiml.vpiml"

---@class NativeClockOpts
---@field high? number High time (same unit as period). Default: period/2
---@field start_high? boolean Start with clock high? Default: true

---@alias TimeUnit "step"|"fs"|"ps"|"ns"|"us"|"ms"|"s"

-- Error codes from libc
local EBUSY = 16
local EEXIST = 17
local EINVAL = 22
local EIO = 5

---@class NativeClock
---@overload fun(chdl: verilua.handles.CallableHDL): NativeClock
---@field private _handle ffi.cdata* Opaque handle to the Rust NativeClock
---@field private _running boolean Track running state in Lua
---@field private _chdl verilua.handles.CallableHDL The CallableHDL passed to create
local NativeClock = class()

--- Time unit to exponent mapping (same as LuaSchedulerCommonV2)
local UNIT_TO_EXPONENT = {
    fs = -15,
    ps = -12,
    ns = -9,
    us = -6,
    ms = -3,
    s = 0,
}

--- Convert time value to simulation steps
--- Reference: LuaSchedulerCommonV2.time_to_steps
---@param value number The time value
---@param unit TimeUnit The time unit
---@return integer steps Time in simulation steps
local function convert_to_steps(value, unit)
    -- "step" is a special case: return the value directly
    if unit == "step" then
        return math.floor(value)
    end

    local unit_exp = UNIT_TO_EXPONENT[unit]
    assert(unit_exp, string.format(
        "Invalid time unit: %s. Valid units: step, fs, ps, ns, us, ms, s", unit))

    local scale = 10 ^ (unit_exp - cfg.time_precision)
    local steps = math.floor(value * scale + 0.5) -- Round to nearest integer

    if steps < 1 then
        assert(false, string.format(
            "Time %g %s is smaller than simulation time_precision (10^%d s)",
            value, unit, cfg.time_precision
        ))
    end

    return steps
end

--- Create a new NativeClock instance
---@param chdl verilua.handles.CallableHDL CallableHDL from chdl()
function NativeClock:_init(chdl)
    -- NativeClock is only supported in HVL mode (not in HSE or WAL)
    assert(not cfg.is_hse, "NativeClock is not supported in HSE mode. Use Lua clock driver instead.")
    assert(not cfg.is_wal, "NativeClock is not supported in WAL mode. Use Lua clock driver instead.")

    texpect.expect_chdl(chdl, "chdl")

    ---@diagnostic disable-next-line: param-type-mismatch
    local handle = vpiml.vpiml_native_clock_new(chdl.hdl)
    assert(handle ~= nil, "NativeClock(): failed to create native clock")

    self._handle = handle
    self._running = false
    self._chdl = chdl
end

--- Start the clock with the specified parameters
---@param period number Clock period
---@param unit TimeUnit Time unit ("ns", "us", "ps", "step", etc.)
---@param opts? NativeClockOpts Optional configuration
function NativeClock:start(period, unit, opts)
    assert(self._handle, "NativeClock:start() called on destroyed instance")
    assert(not self._running, "NativeClock:start() called on already running clock. Call stop() first.")

    opts = opts or {}
    local period_steps = convert_to_steps(period, unit)
    local high_steps
    if opts.high then
        high_steps = convert_to_steps(opts.high, unit)
    else
        high_steps = math.floor(period_steps / 2)
    end
    local start_high = opts.start_high ~= false and 1 or 0

    assert(period_steps >= 2, string.format("period must be >= 2 time steps (got %d)", period_steps))
    assert(high_steps >= 1 and high_steps < period_steps,
        string.format("high must be >= 1 and < period (got high=%d, period=%d)", high_steps, period_steps))

    local ret = vpiml.vpiml_native_clock_start(self._handle, period_steps, high_steps, start_high)

    if ret == EBUSY then
        error("NativeClock:start() internal error: clock already running")
    elseif ret == EEXIST then
        error("Another NativeClock is already driving this signal. Only one NativeClock can drive a signal at a time.")
    elseif ret == EINVAL then
        error(string.format("Invalid parameters: period=%d, high=%d", period_steps, high_steps))
    elseif ret == EIO then
        error("VPI callback registration failed")
    elseif ret ~= 0 then
        error(string.format("vpiml_native_clock_start failed with code %d", ret))
    end

    self._running = true
end

--- Stop the clock
--- The clock signal will retain its last value
function NativeClock:stop()
    if self._handle and self._running then
        vpiml.vpiml_native_clock_stop(self._handle)
        self._running = false
    end
end

--- Check if the clock is currently running
---@return boolean
function NativeClock:is_running()
    if not self._handle then
        return false
    end
    return vpiml.vpiml_native_clock_is_running(self._handle) ~= 0
end

--- Restart the clock with new parameters
--- Convenience method that stops and starts the clock
---@param period number Clock period
---@param unit TimeUnit Time unit
---@param opts? NativeClockOpts Optional configuration
function NativeClock:restart(period, unit, opts)
    self:stop()
    self:start(period, unit, opts)
end

--- Destroy the NativeClock instance and free resources
--- After calling this, the instance cannot be used anymore
function NativeClock:destroy()
    if self._handle then
        vpiml.vpiml_native_clock_destroy(self._handle)
        self._handle = nil
        self._running = false
    end
end

--- Destructor - automatically called when instance is garbage collected
function NativeClock:__gc()
    self:destroy()
end

return NativeClock

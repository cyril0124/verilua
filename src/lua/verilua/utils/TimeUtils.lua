--- Shared simulation-time conversion helpers.
---
--- Time values reach the simulator as integer steps, so every conversion here rounds to
--- the nearest step. A value below one step converts to 0 steps, and callers decide
--- whether that is acceptable.

local f = string.format

---@class verilua.utils.TimeUtils
local M = {}

--- Power of ten of a second for each time unit.
---@type table<string, integer>
local UNIT_EXPONENT = {
    fs = -15,
    ps = -12,
    ns = -9,
    us = -6,
    ms = -3,
    s = 0,
    sec = 0,
}

--- Power of ten of a second for `unit`.
---@param unit TimeUnit Time unit; `nil` and `"step"` never reach this lookup
---@return integer exponent
local function unit_exponent(unit)
    local exponent = UNIT_EXPONENT[unit]
    if exponent == nil then
        assert(false, f("Invalid time unit: %s. Valid units: step, fs, ps, ns, us, ms, s", tostring(unit)))
    end

    return exponent
end

--- Convert a time value in `unit` to simulation steps, rounding to the nearest step.
---@param time number Time value
---@param unit? TimeUnit Time unit; `nil` and `"step"` treat `time` as a step count
---@return integer steps Step count, possibly 0 for a value below one step
function M.time_to_steps(time, unit)
    if unit == nil or unit == "step" then
        return math.floor(time)
    end

    local scale = 10 ^ (unit_exponent(unit) - cfg.time_precision)

    return math.floor(time * scale + 0.5)
end

--- Convert simulation steps to a time value in `unit`.
---@param steps number Step count
---@param unit? TimeUnit Time unit; `nil` and `"step"` return the step count unchanged
---@return number time Time value in `unit`
function M.steps_to_time(steps, unit)
    if unit == nil or unit == "step" then
        return steps
    end

    local scale = 10 ^ (cfg.time_precision - unit_exponent(unit))

    return steps * scale
end

--- Message for a time value that cannot reach a single simulation step.
---@param time number Time value
---@param unit TimeUnit Time unit
---@return string
function M.below_precision_msg(time, unit)
    return f("Time %g %s is smaller than simulation time_precision (10^%d s)", time, unit, cfg.time_precision)
end

return M

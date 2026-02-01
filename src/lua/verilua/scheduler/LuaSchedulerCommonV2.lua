local utils = require "verilua.LuaUtils"
local ceil = math.ceil
local tostring = tostring
local coroutine = coroutine

---@enum verilua.scheduler.YieldType
local YieldType = {
    name             = "YieldType",
    Timer            = 0,
    PosedgeHDL       = 1,
    NegedgeHDL       = 2,
    PosedgeAlways    = 3,
    PosedgeAlwaysHDL = 4,
    NegedgeAlways    = 5,
    NegedgeAlwaysHDL = 6,
    EdgeHDL          = 7,
    EarlyExit        = 8,
    Event            = 9,
    ReadWrite        = 10,
    ReadOnly         = 11,
    NextSimTime      = 12,
    NOOP             = 5555
}
YieldType = utils.enum_define(YieldType)

local Timer = 0
local PosedgeHDL = 1
local NegedgeHDL = 2
local PosedgeAlways = 3
local PosedgeAlwaysHDL = 4
local NegedgeAlways = 5
local NegedgeAlwaysHDL = 6
local EdgeHDL = 7
local EarlyExit = 8
local Event = 9
local ReadWrite = 10
local ReadOnly = 11
local NextSimTime = 12
local NOOP = 5555

---@alias verilua.scheduler.CoroYieldFunc fun(yield_type: verilua.scheduler.YieldType, integet_value: integer): ...

---@type verilua.scheduler.CoroYieldFunc
local coro_yield = coroutine.yield

local await_time
-- TODO: "edge_step" ?
if cfg.mode == "step" then
    local period = cfg.period
    ---@param time integer
    await_time = function(time)
        local t = ceil(time / period)
        for _ = 1, t do
            coro_yield(NOOP, 0)
        end
    end
else
    ---@param time integer
    await_time = function(time)
        coro_yield(Timer, time)
    end
end

--- Time unit to exponent mapping
local UNIT_TO_EXPONENT = {
    fs = -15,
    ps = -12,
    ns = -9,
    us = -6,
    ms = -3,
    s = 0,
}

local time_precision = cfg.time_precision

--- Convert time with unit to simulation steps
---@param time number Time value
---@param unit string Time unit ("fs", "ps", "ns", "us", "ms", "s")
---@return integer steps
local function time_to_steps(time, unit)
    local unit_exp = UNIT_TO_EXPONENT[unit]
    if not unit_exp then
        assert(false, "Unknown time unit:" .. tostring(unit))
    end

    local scale = 10 ^ (unit_exp - time_precision)
    local steps = math.floor(time * scale + 0.5) -- Round to nearest integer

    if steps < 1 then
        assert(false, string.format(
            "Time %g %s is smaller than simulation time_precision (10^%d s)",
            time, unit, time_precision
        ))
    end

    return steps
end

--- Wait for specified femtoseconds
---@param time number femtoseconds
local await_time_fs = function(time)
    coro_yield(Timer, time_to_steps(time, "fs"))
end

--- Wait for specified picoseconds
---@param time number picoseconds
local await_time_ps = function(time)
    coro_yield(Timer, time_to_steps(time, "ps"))
end

--- Wait for specified nanoseconds
---@param time number nanoseconds
local await_time_ns = function(time)
    coro_yield(Timer, time_to_steps(time, "ns"))
end

--- Wait for specified microseconds
---@param time number microseconds
local await_time_us = function(time)
    coro_yield(Timer, time_to_steps(time, "us"))
end

--- Wait for specified milliseconds
---@param time number milliseconds
local await_time_ms = function(time)
    coro_yield(Timer, time_to_steps(time, "ms"))
end

--- Wait for specified seconds
---@param time number seconds
local await_time_s = function(time)
    coro_yield(Timer, time_to_steps(time, "s"))
end

--- Wait for specified time with given unit
---@param time number Time value
---@param unit string Time unit ("fs", "ps", "ns", "us", "ms", "s")
local await_time_unit = function(time, unit)
    coro_yield(Timer, time_to_steps(time, unit))
end

---@param signal_hdl verilua.handles.ComplexHandleRaw
local await_posedge_hdl = function(signal_hdl)
    coro_yield(PosedgeHDL, signal_hdl)
end

---@param signal_hdl verilua.handles.ComplexHandleRaw
local always_await_posedge_hdl = function(signal_hdl)
    coro_yield(PosedgeAlwaysHDL, signal_hdl)
end

---@param signal_hdl verilua.handles.ComplexHandleRaw
local await_negedge_hdl = function(signal_hdl)
    coro_yield(NegedgeHDL, signal_hdl)
end

---@param signal_hdl verilua.handles.ComplexHandleRaw
local await_edge_hdl = function(signal_hdl)
    coro_yield(EdgeHDL, signal_hdl)
end

---@param event_id_integer integer
local await_event = function(event_id_integer)
    coro_yield(Event, event_id_integer)
end

local await_noop = function()
    coro_yield(NOOP, 0)
end

local await_step = await_noop

local exit_task = function()
    coro_yield(EarlyExit, 0)
end

local await_rw = function()
    coro_yield(ReadWrite, 0)
end

local await_rd = function()
    coro_yield(ReadOnly, 0)
end

local await_nsim = function()
    coro_yield(NextSimTime, 0)
end
if cfg.mode == "edge_step" then
    await_nsim = function() end
end

return {
    YieldType                = YieldType,
    await_time               = await_time,
    await_time_fs            = await_time_fs,
    await_time_ps            = await_time_ps,
    await_time_ns            = await_time_ns,
    await_time_us            = await_time_us,
    await_time_ms            = await_time_ms,
    await_time_s             = await_time_s,
    await_time_unit          = await_time_unit,
    await_posedge_hdl        = await_posedge_hdl,
    await_negedge_hdl        = await_negedge_hdl,
    await_edge_hdl           = await_edge_hdl,
    await_noop               = await_noop,
    await_event              = await_event,
    await_step               = await_step,
    exit_task                = exit_task,
    await_rw                 = await_rw,
    await_rd                 = await_rd,
    await_nsim               = await_nsim,
    always_await_posedge_hdl = always_await_posedge_hdl,
}

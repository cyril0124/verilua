local utils = require "LuaUtils"
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

---@param signal_hdl ComplexHandleRaw
local await_posedge_hdl = function(signal_hdl)
    coro_yield(PosedgeHDL, signal_hdl)
end

---@param signal_hdl ComplexHandleRaw
local always_await_posedge_hdl = function(signal_hdl)
    coro_yield(PosedgeAlwaysHDL, signal_hdl)
end

---@param signal_hdl ComplexHandleRaw
local await_negedge_hdl = function(signal_hdl)
    coro_yield(NegedgeHDL, signal_hdl)
end

---@param signal_hdl ComplexHandleRaw
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

return {
    YieldType                = YieldType,
    await_time               = await_time,
    await_posedge_hdl        = await_posedge_hdl,
    await_negedge_hdl        = await_negedge_hdl,
    await_edge_hdl           = await_edge_hdl,
    await_noop               = await_noop,
    await_event              = await_event,
    await_step               = await_step,
    exit_task                = exit_task,
    always_await_posedge_hdl = always_await_posedge_hdl,
}

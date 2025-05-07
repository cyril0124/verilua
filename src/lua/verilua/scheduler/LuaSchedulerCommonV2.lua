local utils = require "LuaUtils"
local STEP = _G.SchedulerMode.STEP
local verilua_mode = cfg.mode
local period = cfg.period
local ceil = math.ceil
local tostring = tostring
local coroutine = coroutine

---@enum YieldType
local YieldType = {
    name             = "YieldType",
    Timer            = 0,
    Posedge          = 1,
    PosedgeHDL       = 2,
    Negedge          = 3,
    NegedgeHDL       = 4,
    PosedgeAlways    = 5,
    PosedgeAlwaysHDL = 6,
    NegedgeAlways    = 7,
    NegedgeAlwaysHDL = 8,
    Edge             = 9,
    EdgeHDL          = 10,
    EarlyExit        = 11,
    Event            = 12,
    NOOP             = 44
}
YieldType = utils.enum_define(YieldType)

-- local Timer = YieldType.Timer
-- local Posedge = YieldType.Posedge 
-- local PosedgeHDL = YieldType.PosedgeHDL
-- local Negedge = YieldType.Negedge
-- local NegedgeHDL = YieldType.NegedgeHDL
-- local PosedgeAlways = YieldType.PosedgeAlways
-- local PosedgeAlwaysHDL = YieldType.PosedgeAlwaysHDL
-- local NegedgeAlways = YieldType.NegedgeAlways
-- local NegedgeAlwaysHDL = YieldType.NegedgeAlwaysHDL
-- local Edge = YieldType.Edge
-- local EdgeHDL = YieldType.EdgeHDL
-- local EarlyExit = YieldType.EarlyExit
-- local Event = YieldType.Event
-- local NOOP = YieldType.NOOP

local Timer = 0
local Posedge = 1
local PosedgeHDL = 2
local Negedge = 3
local NegedgeHDL = 4
local PosedgeAlways = 5
local PosedgeAlwaysHDL = 6
local NegedgeAlways = 7
local NegedgeAlwaysHDL = 8
local Edge = 9
local EdgeHDL = 10
local EarlyExit = 11
local Event = 12
local NOOP = 44

---@type fun(yield_type: YieldType, string_value: string, integet_value: integer): ...
local coro_yield = coroutine.yield

local await_time = function (time)
    if verilua_mode == STEP then
        local t = ceil(time / period)
        for i = 1, t do
            coro_yield(NOOP, "", 0)
        end
    else
        coro_yield(Timer, "", time)
    end
end

local await_posedge = function(signal_str)
    coro_yield(Posedge, tostring(signal_str), 0)
end

local await_posedge_hdl = function(signal_hdl)
    coro_yield(PosedgeHDL, "", signal_hdl)
end

local always_await_posedge_hdl = function(signal_hdl)
    coro_yield(PosedgeAlwaysHDL, "", signal_hdl)
end

local await_negedge = function (signal_str)
    coro_yield(Negedge, tostring(signal_str), 0)
end

local await_negedge_hdl = function (signal_hdl)
    coro_yield(NegedgeHDL, "", signal_hdl)
end

local await_edge = function (signal_str)
    coro_yield(Edge, tostring(signal_str), 0)
end

local await_edge_hdl = function (signal_hdl)
    coro_yield(EdgeHDL, "", signal_hdl)
end

local await_event = function (event_id_integer)
    coro_yield(Event, "", event_id_integer)
end

local await_noop = function ()
    coro_yield(NOOP, "", 0)
end

local await_step = await_noop

local exit_task = function ()
    coro_yield(EarlyExit, "", 0)
end

---@class _G
---@field await_time fun(time: number)
---@field await_posedge fun(signal_str: string)
---@field await_posedge_hdl fun(signal_hdl: ComplexHandleRaw)
---@field always_await_posedge_hdl fun(signal_hdl: ComplexHandleRaw)
---@field await_negedge fun(signal_str: string)
---@field await_negedge_hdl fun(signal_hdl: ComplexHandleRaw)
---@field await_edge fun(signal_str: string)
---@field await_edge_hdl fun(signal_hdl: ComplexHandleRaw)
---@field await_event fun(event_id_integer: integer)
---@field await_noop fun()
---@field await_step fun()
---@field exit_task fun()
return {
    YieldType         = YieldType,
    await_time        = await_time,
    await_posedge     = await_posedge,
    await_posedge_hdl = await_posedge_hdl,
    await_negedge     = await_negedge,
    await_negedge_hdl = await_negedge_hdl,
    await_edge        = await_edge,
    await_edge_hdl    = await_edge_hdl,
    await_noop        = await_noop,
    await_event       = await_event,
    await_step        = await_step,
    exit_task         = exit_task,
    always_await_posedge_hdl = always_await_posedge_hdl,
}
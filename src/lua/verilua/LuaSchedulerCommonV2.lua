local utils = require "LuaUtils"
local VeriluaMode = VeriluaMode
local STEP = VeriluaMode.STEP
local verilua_mode = cfg.mode
local period = cfg.period
local ceil = math.ceil
local tostring = tostring
local coroutine = coroutine
local coro_yield = coroutine.yield

local YieldType = utils.enum_define {
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
    NOOP             = 44
}

local await_time = function (time)
    if verilua_mode == STEP then
        local t = ceil(time / period)
        for i = 1, t do
            coro_yield(YieldType.NOOP, "", 0)
        end
    else
        coro_yield(YieldType.Timer, "", time)
    end
end

local await_posedge = function(signal_str)
    coro_yield(YieldType.Posedge, tostring(signal_str), 0)
end

local await_posedge_hdl = function(signal_hdl)
    coro_yield(YieldType.PosedgeHDL, "", signal_hdl)
end

local always_await_posedge_hdl = function(signal_hdl)
    coro_yield(YieldType.PosedgeAlwaysHDL, "", signal_hdl)
end

local await_negedge = function (signal_str)
    coro_yield(YieldType.Negedge, tostring(signal_str), 0)
end

local await_negedge_hdl = function (signal_hdl)
    coro_yield(YieldType.NegedgeHDL, "", signal_hdl)
end

local await_edge = function (signal_str)
    coro_yield(YieldType.Edge, tostring(signal_str), 0)
end

local await_edge_hdl = function (signal_hdl)
    coro_yield(YieldType.EdgeHDL, "", signal_hdl)
end

local await_noop = function ()
    coro_yield(YieldType.NOOP, "", 0)
end

local await_step = await_noop

local exit_task = function ()
    coro_yield(YieldType.EarlyExit, "", 0)
end

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
    await_step        = await_step,
    exit_task         = exit_task,
    always_await_posedge_hdl = always_await_posedge_hdl,
}
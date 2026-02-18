local vpiml = require "verilua.vpiml.vpiml"
local utils = require "verilua.LuaUtils"

local ceil = math.ceil
local tostring = tostring
local coroutine = coroutine

local scheduler = _G.scheduler
local scheduler_mode = cfg.mode

---@class verilua.scheduler.SchedulerCommon
local M = {}

---@enum verilua.scheduler.YieldType
local YieldType = {
    name      = "YieldType",
    EarlyExit = 4444,
    NOOP      = 5555,
}
M.YieldType = utils.enum_define(YieldType)

local EarlyExit = 4444
local NOOP = 5555

---@alias verilua.scheduler.CoroYieldFunc fun(yield_type: verilua.scheduler.YieldType): ...

---@type verilua.scheduler.CoroYieldFunc
local coro_yield = coroutine.yield

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
---@param unit "fs" | "ps" | "ns" | "us" | "ms" | "s" Time unit ("fs", "ps", "ns", "us", "ms", "s")
---@return integer steps
local function time_to_steps(time, unit)
    local unit_exp = UNIT_TO_EXPONENT[unit]
    if not unit_exp then
        assert(false, "Unknown time unit:" .. tostring(unit))
    end

    ---@cast unit_exp -?
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

---@param time integer
function M.await_time(time)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_time_callback(time, scheduler.curr_task_id)
    coro_yield(NOOP)
end

--- Wait for specified femtoseconds
---@param time number femtoseconds
function M.await_time_fs(time)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_time_callback(time_to_steps(time, "fs"), scheduler.curr_task_id)
    coro_yield(NOOP)
end

--- Wait for specified picoseconds
---@param time number picoseconds
function M.await_time_ps(time)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_time_callback(time_to_steps(time, "ps"), scheduler.curr_task_id)
    coro_yield(NOOP)
end

--- Wait for specified nanoseconds
---@param time number nanoseconds
function M.await_time_ns(time)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_time_callback(time_to_steps(time, "ns"), scheduler.curr_task_id)
    coro_yield(NOOP)
end

--- Wait for specified microseconds
---@param time number microseconds
function M.await_time_us(time)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_time_callback(time_to_steps(time, "us"), scheduler.curr_task_id)
    coro_yield(NOOP)
end

--- Wait for specified milliseconds
---@param time number milliseconds
function M.await_time_ms(time)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_time_callback(time_to_steps(time, "ms"), scheduler.curr_task_id)
    coro_yield(NOOP)
end

--- Wait for specified seconds
---@param time number seconds
function M.await_time_s(time)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_time_callback(time_to_steps(time, "s"), scheduler.curr_task_id)
    coro_yield(NOOP)
end

--- Wait for specified time with given unit
---@param time number Time value
---@param unit "fs" | "ps" | "ns" | "us" | "ms" | "s" Time unit ("fs", "ps", "ns", "us", "ms", "s")
function M.await_time_unit(time, unit)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_time_callback(time_to_steps(time, unit), scheduler.curr_task_id)
    coro_yield(NOOP)
end

---@param signal_hdl verilua.handles.ComplexHandleRaw
function M.await_posedge_hdl(signal_hdl)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_posedge_callback(signal_hdl, scheduler.curr_task_id)
    coro_yield(NOOP)
end

---@param signal_hdl verilua.handles.ComplexHandleRaw
function M.always_await_posedge_hdl(signal_hdl)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_posedge_callback_always(signal_hdl, scheduler.curr_task_id)
    coro_yield(NOOP)
end

---@param signal_hdl verilua.handles.ComplexHandleRaw
function M.await_negedge_hdl(signal_hdl)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_negedge_callback(signal_hdl, scheduler.curr_task_id)
    coro_yield(NOOP)
end

---@param signal_hdl verilua.handles.ComplexHandleRaw
function M.await_edge_hdl(signal_hdl)
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_edge_callback(signal_hdl, scheduler.curr_task_id)
    coro_yield(NOOP)
end

---@param event_id_integer integer
function M.await_event(event_id_integer)
    scheduler:register_event(event_id_integer, scheduler.curr_task_id)
    coro_yield(NOOP)
end

function M.await_noop()
    coro_yield(NOOP)
end

M.await_step = M.await_noop

function M.exit_task()
    coro_yield(EarlyExit)
end

function M.await_rw()
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_rw_synch_callback(scheduler.curr_task_id)
    coro_yield(NOOP)
end

function M.await_rd()
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_rd_synch_callback(scheduler.curr_task_id)
    coro_yield(NOOP)
end

function M.await_nsim()
    ---@diagnostic disable-next-line
    vpiml.vpiml_register_next_sim_time_callback(scheduler.curr_task_id)
    coro_yield(NOOP)
end

if scheduler_mode == "step" then
    for key, _ in pairs(M) do
        if key:contains("await") and not key:contains("await_event") then
            M[key] = function()
                coro_yield(NOOP)
            end
        end
    end

    local period = cfg.period
    ---@param time integer
    M.await_time = function(time)
        -- TODO: "edge_step" ?
        local t = ceil(time / period)
        for _ = 1, t do
            coro_yield(NOOP)
        end
    end
elseif scheduler_mode == "edge_step" then
    for key, _ in pairs(M) do
        if key:contains("await") and not key:contains("await_event") then
            M[key] = function()
                assert(false, "Unsupported yield type in edge_step mode: " .. key .. "")
            end
        end
    end

    -- M.await_nsim = function() end

    M.await_posedge_hdl = function()
        ---@diagnostic disable: access-invisible
        scheduler.posedge_tasks[scheduler.curr_task_id] = true
    end
    M.always_await_posedge_hdl = M.await_posedge_hdl

    M.await_negedge_hdl = function()
        ---@diagnostic disable: access-invisible
        scheduler.negedge_tasks[scheduler.curr_task_id] = true
    end
end

return M

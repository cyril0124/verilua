
local VeriluaMode = VeriluaMode
local STEP = VeriluaMode.STEP
local verilua_mode = cfg.mode
local period = cfg.period
local ceil = math.ceil

YieldType = {
    TIMER = 0,
    SIGNAL_EDGE = 1,
    SIGNAL_EDGE_HDL = 2,
    SIGNAL_EDGE_ALWAYS = 3,
    READ_WRITE_SYNCH = 4,
    CLOCK_POSEDGE = 5,
    CLOCK_POSEDGE_ALWAYS = 6,
    CLOCK_NEGEDGE = 7,
    CLOCK_NEGEDGE_ALWAYS = 8,
    NOOP = 44
}


EdgeType = { POSEDGE = 0, NEGEDGE = 1, EDGE = 2 }


--------------------------------
-- Schedule events
--------------------------------
function await_time(time)
    if verilua_mode == STEP then
        local t = ceil(time / period)
        for i = 1, t do
            coroutine.yield(YieldType.NOOP)
        end
    else
        coroutine.yield(YieldType.TIMER, time)
    end
end

function await_posedge(signal)
    coroutine.yield(YieldType.SIGNAL_EDGE, EdgeType.POSEDGE, tostring(signal))
end

function await_negedge(signal)
    coroutine.yield(YieldType.SIGNAL_EDGE, EdgeType.NEGEDGE,  tostring(signal))
end

function await_edge(signal)
    coroutine.yield(YieldType.SIGNAL_EDGE, EdgeType.EDGE,  tostring(signal))
end


function await_posedge_hdl(signal)
    coroutine.yield(YieldType.SIGNAL_EDGE_HDL, EdgeType.POSEDGE, signal)
end

function await_negedge_hdl(signal)
    coroutine.yield(YieldType.SIGNAL_EDGE_HDL, EdgeType.NEGEDGE,  signal)
end

function await_edge_hdl(signal)
    coroutine.yield(YieldType.SIGNAL_EDGE_HDL, EdgeType.EDGE,  signal)
end

function await_read_write_synch()
    coroutine.yield(YieldType.READ_WRITE_SYNCH, nil,  nil)
end

function always_await_posedge_hdl(signal)
    coroutine.yield(YieldType.SIGNAL_EDGE_ALWAYS, EdgeType.POSEDGE, signal)
end

function await_noop()
    coroutine.yield(YieldType.NOOP, nil, nil)
end

function register_always_await_posedge_hdl()
    local fired = false
    assert(false, "deprecated!")
    return function(signal)
        if not fired then
            fired = true
            coroutine.yield(YieldType.SIGNAL_EDGE_ALWAYS, EdgeType.POSEDGE, signal)
        else
            coroutine.yield(YieldType.NOOP, nil, nil)
        end
    end
end

function await_step()
    coroutine.yield(YieldType.NOOP)
end

function exist_task()
    coroutine.yield(nil)
end
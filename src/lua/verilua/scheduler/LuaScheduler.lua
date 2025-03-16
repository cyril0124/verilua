local cfg = _G.cfg
local SchedulerMode = _G.SchedulerMode

local scheduler
if os.getenv("VL_PREBUILD") then
    scheduler = require("verilua.scheduler.LuaDummyScheduler")
else
    local mode = cfg.mode
    local perf_time = os.getenv("VL_PERF_TIME") == "1"

    if mode == SchedulerMode.NORMAL then
        scheduler = require("verilua.scheduler.LuaNormalSchedulerV2" .. (perf_time and "P" or ""))
    elseif mode == SchedulerMode.STEP then
        scheduler = require("verilua.scheduler.LuaStepSchedulerV2" .. (perf_time and "P" or ""))
    elseif mode == SchedulerMode.DOMINANT then
        assert(false, "TODO:")
        scheduler = require("verilua.scheduler.LuaDominantSchedulerV2" .. (perf_time and "P" or ""))
    else
        assert(false, "Unknown scheduler mode! maybe you forget to set it? please set `cfg.mode` to `normal`, `SchedulerMode.STEP` or `SchedulerMode.DOMINANT`")
    end
end

return scheduler
local cfg = _G.cfg
local VeriluaMode = _G.VeriluaMode

local scheduler
do
    local mode = cfg.mode
    local perf_time = os.getenv("VL_PERF_TIME") == "1"

    if mode == VeriluaMode.NORMAL then
        scheduler = require("verilua.scheduler.LuaNormalSchedulerV2" .. (perf_time and "P" or ""))
    elseif mode == VeriluaMode.STEP then
        scheduler = require("verilua.scheduler.LuaStepSchedulerV2" .. (perf_time and "P" or ""))
    elseif mode == VeriluaMode.DOMINANT then
        assert(false, "TODO:")
        scheduler = require("verilua.scheduler.LuaDominantSchedulerV2" .. (perf_time and "P" or ""))
    else
        assert(false, "Unknown verilua mode! maybe you forget to set it? please set `cfg.mode` to `normal`, `VeriluaMode.STEP` or `VeriluaMode.DOMINANT`")
    end
end

return scheduler
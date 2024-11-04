local scheduler = nil

if cfg.mode == VeriluaMode.NORMAL then
    -- scheduler = require("verilua.scheduler.LuaNormalScheduler")
    scheduler = require("verilua.scheduler.LuaNormalSchedulerV2")
elseif cfg.mode == VeriluaMode.STEP then
    -- scheduler = require("verilua.scheduler.LuaStepScheduler")
    scheduler = require("verilua.scheduler.LuaStepSchedulerV2")
elseif cfg.mode == VeriluaMode.DOMINANT then
    assert(false, "TODO:")
    -- scheduler = require("verilua.scheduler.LuaDominantScheduler")
    scheduler = require("verilua.scheduler.LuaDominantSchedulerV2")
else
    assert(false, "Unknown verilua mode!")
end

return scheduler
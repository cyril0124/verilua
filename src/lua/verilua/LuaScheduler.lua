local scheduler = nil

if cfg.mode == VeriluaMode.NORMAL then
    -- scheduler = require("LuaNormalScheduler")
    scheduler = require("LuaNormalSchedulerV2")
elseif cfg.mode == VeriluaMode.STEP then
    -- scheduler = require("LuaStepScheduler")
    scheduler = require("LuaStepSchedulerV2")
elseif cfg.mode == VeriluaMode.DOMINANT then
    assert(false, "TODO:")
    -- scheduler = require("LuaDominantScheduler")
    scheduler = require("LuaDominantSchedulerV2")
else
    assert(false, "Unknown verilua mode!")
end

return scheduler
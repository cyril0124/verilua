local scheduler = nil

if cfg.mode == VeriluaMode.NORMAL then
    scheduler = require("LuaNormalScheduler")
elseif cfg.mode == VeriluaMode.STEP then
    scheduler = require("LuaStepScheduler")
elseif cfg.mode == VeriluaMode.DOMINANT then
    scheduler = require("LuaDominantScheduler")
else
    assert(false, "Unknown verilua mode!")
end

return scheduler
local cfg = {}

cfg.simulator = _G.cfg.simulator
if cfg.simulator == "verilator" then
    cfg.top = "TOP.top"
else
    cfg.top = "top"
end

cfg.script = "./verilua/main.lua"
cfg.is_hse = true

return cfg
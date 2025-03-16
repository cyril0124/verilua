local cfg = {}

cfg.simulator = _G.cfg.simulator
if cfg.simulator == "verilator" then
    cfg.top = "TOP.tb_top"
else
    cfg.top = "tb_top"
end

cfg.script = "./verilua/main.lua"
cfg.is_hse = true

return cfg
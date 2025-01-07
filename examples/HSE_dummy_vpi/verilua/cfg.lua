local cfg = {}

cfg.simulator = os.getenv("SIM") or "verilator"
if cfg.simulator == "verilator" then
    cfg.top = "TOP.tb_top"
else
    cfg.top = "tb_top"
end

cfg.script = "./verilua/main.lua"
cfg.attach = true
cfg.mode = 'step'

return cfg
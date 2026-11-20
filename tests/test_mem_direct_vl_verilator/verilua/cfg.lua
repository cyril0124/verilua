local cfg = {}
cfg.simulator = os.getenv("SIM") or "verilator"
cfg.top = "TOP.tb_top"
cfg.script = os.getenv("MD_VLV_DIR") .. "/verilua/main.lua"
cfg.is_hse = true
return cfg

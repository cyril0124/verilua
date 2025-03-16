local cfg = {}

cfg.simulator = os.getenv("SIM") or "verilator"

-- [mandatory] This option is used to specify the top module name.
if cfg.simulator == "verilator" then
    -- Top level for verilator has a prefix of "TOP."
    cfg.top = "TOP.tb_top"
else
    cfg.top = "tb_top"
end

-- [mandatory] This option is used to specify the verilua main script to be run.
cfg.script = "./verilua/main.lua"

-- [mandatory] When using verilua as HSE, you must set this two options.
cfg.is_hse = true

return cfg
-- Second user config file, merged after `cfg.lua` (see `verilua.user_cfg` in xmake.lua).
-- A later file wins on conflicting keys, so `var2` here overrides the one from `cfg.lua`.
local cfg = {}

cfg.var2 = "hello from extra_cfg"
cfg.var3 = 3

return cfg

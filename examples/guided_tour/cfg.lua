local cfg = {}

cfg.var1 = 1
cfg.var2 = "hello"

--- Notice:
--          Not all verilua modules are supported in the user configuration file since verilua load user configuration file
---         in a pretty early stage and some modules may not be available yet. Currently, `LuaUtils` is supported.
local utils = require "verilua.LuaUtils"
cfg.test_mode = utils.get_env_or_else("TEST_MODE", "string", "Normal")

return cfg
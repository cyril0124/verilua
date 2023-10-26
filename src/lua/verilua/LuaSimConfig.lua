--------------------------------
-- Default config
--------------------------------
require("LuaUtils")

top = os.getenv("DUT_TOP")
verilua_assert(top ~= "Unknown" and top ~= nil, "DUT_TOP is not set!")
verilua_info("DUT_TOP is " .. top)

config = {
    top = top,
    clock = top .. ".clock",
    reset = top .. ".reset",
    seed = 2,
    verbose = true,
    period = 10,
    unit = "ns",
    enable_shutdown = true,
    shutdown_cycles = 20000000,
    enable_luaPanda = false,
}


--------------------------------
-- Get configuration module
--------------------------------
LuaSimConfig = {}
function LuaSimConfig.get_cfg()
    local VERILUA_HOME = os.getenv("VERILUA_HOME")
    local VERILUA_CFG_PATH = os.getenv("VERILUA_CFG_PATH") or VERILUA_HOME
    local VERILUA_CFG = os.getenv("VERILUA_CFG") or "src/lua/verilua/LuaSimConfig"
    package.path = package.path .. ";" .. VERILUA_CFG_PATH .. "/?.lua"

    return VERILUA_CFG or "LuaSimConfig", VERILUA_CFG_PATH
end




return config
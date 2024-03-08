--------------------------------
-- Default config
--------------------------------
local enum_search =  function(t, v)
    for name, value in pairs(t) do
        if value == v then
            return name
        end
    end
    assert(false, "Key no found: " .. v .. " in " .. t.name)
end

VeriluaMode = setmetatable({
    name     = "VeriluaMode",
    
    NORMAL   = 1,
    STEP     = 2,
    DOMINANT = 3,
    N        = 1, -- alias of NORMAL
    S        = 2, -- alias of STEP
    D        = 3  -- alias of DOMINANT
}, { __call = enum_search })


local config = {}

config.colors = {
    reset = "\27[0m",
    black = "\27[30m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m"
}

function config:config_info(...)
    print(self.colors.cyan .. os.date() .. " [CONFIG INFO]", ...)
    io.write(self.colors.reset)
end

function config:config_warn(...)
    print(self.colors.yellow .. os.date() ..  "[CONFIG WARNING]", ...)
    io.write(self.colors.reset)
end

function config:config_error(cond, ...)
    if cond == nil or cond == false then
        local error_print = function(...)
            print(self.colors.red .. os.date() ..  "[CONFIG ERROR]", ...)
            io.write(self.colors.reset)
            io.flush()
        end
        assert(false, error_print(...))
    end
end

function config:get_or_else(cfg_str, default)
    local cfg = rawget(self, cfg_str)
    if cfg == nil then
        local cfg_name = self.name or "Unknown"
        self:config_warn(string.format("[%s] cfg.%s is nil! use default config => %s", cfg_name, cfg_str, tostring(default)))
        return default
    end
    return cfg
end

config.top               = os.getenv("DUT_TOP")
config:config_error(config.top ~= "Unknown" and config.top ~= nil, config.colors.red .. "DUT_TOP is not set!" .. config.colors.reset)
config:config_info(config.colors.cyan .. "DUT_TOP is " .. config.top .. config.colors.reset)

config.clock             = config.top .. ".clock"
config.reset             = config.top .. ".reset"
config.seed              = 2
config.verbose           = true
config.period            = 10
config.unit              = "ns"
config.enable_shutdown   = true
config.shutdown_cycles   = 20000000
config.enable_luaPanda   = false
config.simulator         = os.getenv("SIM")
assert(config.simulator ~= nil, "Enviroment argument SIM is not set")

--
--  three mode: 
--    (1) NORMAL(N); 
--    (2) STEP(S); 
--    (3) DOMINANT(D);
-- 
config.mode              = VeriluaMode.NORMAL

-- 
-- when you embed verilua in your own verification env, this value should be TRUE
-- 
config.attach            = false


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



function CONNECT_CONFIG(src, dest)
    dest = dest or {}
    local result = dest
    for k, v in pairs(src) do
        if result[k] ~= nil then
            print(string.format("[WARN] duplicate key: %s value: %s", k, v))
        end
        result[k] = v
    end
    return result
end


return config
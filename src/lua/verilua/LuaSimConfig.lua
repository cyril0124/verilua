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

local function get_debug_info(level)
    local info = debug.getinfo(level or 2, "nSl") -- Level 2 because we're inside a function
    
    local file = info.short_src -- info.source
    local line = info.currentline
    local func = info.name or "<anonymous>"

    return file, line, func
end

local enable_debug_print = os.getenv("VL_DEBUG") == "1"
local function debug_print(...)
    if enable_debug_print then
        local file, line, func = get_debug_info(3)
        print(("[%s:%s:%d]"):format(file, func, line), ...)
    end
end

local LuaSimConfig = {}
function LuaSimConfig.get_cfg()
    local VERILUA_CFG_PATH = os.getenv("VERILUA_CFG_PATH")
    local VERILUA_CFG = os.getenv("VERILUA_CFG")
    assert(VERILUA_CFG ~= nil, "[VERILUA_CFG] You should indicate configuration file via setting env var <VERILUA_CFG>")

    if VERILUA_CFG_PATH ~= nil then
        package.path = package.path .. ";" .. VERILUA_CFG_PATH .. "/?.lua"
    end

    return VERILUA_CFG, VERILUA_CFG_PATH
end


function LuaSimConfig.CONNECT_CONFIG(src, dest)
    dest = dest or {}
    local result = dest
    for k, v in pairs(src) do
        if result[k] ~= nil then
            debug_print(string.format("[WARN] duplicate key: %s value: %s", k, v))
        else
            debug_print(string.format("[INFO] new key: %s value: %s", k, v))
        end
        result[k] = v
    end
    return result
end


LuaSimConfig.VeriluaMode = setmetatable({
    name     = "VeriluaMode",
    
    NORMAL   = 1,
    STEP     = 2,
    DOMINANT = 3,
    N        = 1, -- alias of NORMAL
    S        = 2, -- alias of STEP
    D        = 3  -- alias of DOMINANT
}, { __call = enum_search })


return LuaSimConfig
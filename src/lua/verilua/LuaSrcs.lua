
local VERILUA_HOME = os.getenv("VERILUA_HOME")

local srcs = {
    VERILUA_HOME .. "/?.lua",
    VERILUA_HOME .. "/configs/?.lua",
    VERILUA_HOME .. "/src/lua/?.lua",
    VERILUA_HOME .. "/src/lua/verilua/?.lua",
    VERILUA_HOME .. "/src/lua/thirdparty_lib/?.lua",
    VERILUA_HOME .. "/luajit2.1/share/lua/5.1/?.lua",
}

return srcs
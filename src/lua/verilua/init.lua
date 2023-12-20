local PWD = os.getenv("PWD")
local VERILUA_HOME = os.getenv("VERILUA_HOME")

local function append_package_path(path)
    package.path = package.path .. ";" .. path
end

local function append_package_cpath(path)
    package.cpath = package.cpath .. ";" .. path
end

append_package_path(PWD .. "/src/lua/?.lua")
append_package_path(PWD .. "/src/lua/main/?.lua")
append_package_path(PWD .. "/src/lua/configs/?.lua")
append_package_path(VERILUA_HOME .. "/?.lua")
append_package_path(VERILUA_HOME .. "/configs/?.lua")
append_package_path(VERILUA_HOME .. "/src/lua/verilua/?.lua")
append_package_path(VERILUA_HOME .. "/src/lua/?.lua")
append_package_path(VERILUA_HOME .. "/src/lua/thirdparty_lib/?.lua")
append_package_path(VERILUA_HOME .. "/extern/LuaPanda/Debugger/?.lua")
append_package_path(VERILUA_HOME .. "/extern/luafun/?.lua")
append_package_path(VERILUA_HOME .. "/luajit2.1/share/lua/5.1/?.lua")

append_package_cpath(VERILUA_HOME .. "/extern/LuaPanda/Debugger/debugger_lib/?.so")

return {
    append_package_path = append_package_path,
    append_package_cpath = append_package_cpath
}
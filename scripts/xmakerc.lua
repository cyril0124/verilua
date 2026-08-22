---@diagnostic disable

local home = os.getenv("VERILUA_HOME")
if not home or home == "" then
    raise("VERILUA_HOME is not set")
end
includes(path.join(home, "scripts", "xmake", "rules", "verilua"))
add_toolchaindirs(path.join(home, "scripts", "xmake", "toolchains"))
set_policy("run.autobuild", false)

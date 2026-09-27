---@diagnostic disable

local home = os.getenv("VERILUA_HOME")
if not home or home == "" then
    raise("VERILUA_HOME is not set")
end

-- Verilua injects rules and toolchains through `add_toolchaindirs`, which xmake only
-- provides since 2.9.9. This scope has no raise/error, so print a hint before xmake
-- aborts with the raw "global 'add_toolchaindirs' is not callable".
local min_xmake_version = "2.9.9"
if type(xmake) == "table" and xmake.version and xmake.version():lt(min_xmake_version) then
    print(format(
        "verilua: xmake >= %s is required (found %s), please upgrade xmake",
        min_xmake_version,
        tostring(xmake.version())
    ))
end
includes(path.join(home, "scripts", "xmake", "rules", "verilua"))
add_toolchaindirs(path.join(home, "scripts", "xmake", "toolchains"))
set_policy("run.autobuild", false)

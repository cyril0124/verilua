---@diagnostic disable

local rtl_dir = path.join(os.scriptdir(), "..", "rtl")
local post_init_file = path.absolute(path.join(os.scriptdir(), "post_init.lua"))
local post_init_code = [[
_G.__vl_boot_order = {}
table.insert(_G.__vl_boot_order, "post_init")
]]

local function configure_sim(target)
    local sim = os.getenv("SIM") or "verilator"
    if sim == "iverilog" then
        target:set("toolchains", "@iverilog")
    elseif sim == "vcs" then
        target:set("toolchains", "@vcs")
    elseif sim == "xcelium" then
        target:set("toolchains", "@xcelium")
    elseif sim == "verilator" then
        target:set("toolchains", "@verilator")
    else
        raise("unknown simulator: %s", sim)
    end
end

target("test", function()
    add_rules("verilua")
    on_config(configure_sim)
    add_files(path.join(rtl_dir, "top.sv"))
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "main.lua")
    add_runenvs("VL_POST_INIT_SCRIPT", post_init_file)
end)

target("test_code", function()
    set_default(false)
    add_rules("verilua")
    on_config(configure_sim)
    add_files(path.join(rtl_dir, "top.sv"))
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "main.lua")
    add_runenvs("VL_POST_INIT_SCRIPT", post_init_code)
end)

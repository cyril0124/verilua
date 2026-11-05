---@diagnostic disable

local rtl_dir = path.join(os.scriptdir(), "..", "rtl")

target("test", function()
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "verilator" then
            target:set("toolchains", "@verilator")
        else
            raise("test_mem_direct only supports SIM=verilator, got: %s", sim)
        end
    end)

    add_files(path.join(rtl_dir, "top.sv"))
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "main.lua")
    set_values("verilua.verilator_mem_direct", "1")
end)

---@diagnostic disable

local rtl_dir = path.join(os.scriptdir(), "..", "rtl")

target("test", function()
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim ~= "verilator" then
            raise("test_mem_direct_no_public_flat only supports SIM=verilator, got: %s", sim)
        end
        target:set("toolchains", "@verilator")
    end)

    add_files(path.join(rtl_dir, "top.sv"))
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "main.lua")
    set_values("verilua.verilator_mem_direct", "1")
    set_values("verilua.verilator_mem_direct_include", {
        "tb_top.clock",
        "tb_top.u_top.reg32",
        "tb_top.u_top.vec_reg",
    })
    set_values("verilua.verilator_no_public_flat_rw", "1")
    set_values("verilua.verilator_config", [[
public_flat_rw -module "tb_top" -var "clock"
public_flat -module "top" -var "reg32"
public_flat -module "top" -var "vec_reg"
]])
end)

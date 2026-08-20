local vpiml = require "verilua.vpiml.vpiml"
local MemDirect = require "verilua.utils.MemDirect"

assert(MemDirect:try_init(), "[test_mem_direct_no_public_flat] MemDirect:try_init failed")
assert(cfg.enable_mem_direct == true)
assert(MemDirect:lookup("tb_top.u_top.reg32") ~= nil)
assert(MemDirect:lookup("tb_top.u_top.vec_reg") ~= nil)

local clock = dut.clock:chdl()
local reg32 = dut.u_top.reg32:chdl()
local vec_reg = dut.u_top.vec_reg:chdl()
local reg32_vpi = vpiml.vpiml_handle_by_name_safe("tb_top.u_top.reg32")

fork {
    function()
        clock:posedge()
        assert(reg32:get() == 32)
        reg32:set_imm(0xA5)
        assert(reg32:get() == 0xA5)

        for i = 0, 3 do
            assert(tonumber(vec_reg:get_index(i)) == i)
        end
        vec_reg:set_imm_index(2, 0x5A)
        assert(tonumber(vec_reg:get_index(2)) == 0x5A)

        print(string.format(
            "[test_mem_direct_no_public_flat] PASS (reg32 VPI handle %s)",
            (reg32_vpi == nil or reg32_vpi == -1) and "absent" or "present"
        ))
        sim.finish()
    end
}

local MemDirect = require "verilua.utils.MemDirect"
local DpiExporter = require "verilua.utils.DpiExporter"

assert(MemDirect:try_init(), "[test_mem_direct_vl_verilator] try_init failed")
assert(cfg.enable_mem_direct == true)

-- Only the run_dpi.sh flow builds with dpi_exporter output; there the meta_only
-- group (reg16) must be strictly verified (no silent skip).
local is_dpi_flow = os.getenv("MD_VLV_DPI") == "1"
if is_dpi_flow then
    assert(DpiExporter:try_init(), "[test_mem_direct_vl_verilator] DpiExporter try_init failed")
    local info = DpiExporter:lookup("tb_top.uut.reg16")
    assert(info ~= nil, "reg16 must be in the dpi meta table")
    assert(info.metaOnly == true, "reg16 must be marked metaOnly")
    assert(MemDirect:lookup("tb_top.uut.reg16") ~= nil, "reg16 must be in the mem_direct table")
end

-- Include filters were forwarded by `--vl-mem-direct-include`: only clk /
-- reg32 / vec_reg are in the table; everything else must miss (VPI fallback).
assert(MemDirect:lookup("tb_top.clk") ~= nil)
assert(MemDirect:lookup("tb_top.uut.reg32") ~= nil)
assert(MemDirect:lookup("tb_top.uut.vec_reg") ~= nil)
assert(MemDirect:lookup("tb_top.uut.reg8") == nil)

fork {
    function()
        local clock = dut.clk:chdl()
        clock:posedge()

        local reg32 = dut.uut.reg32:chdl()
        assert(reg32:get() == 32, "reg32 initial")
        reg32:set_imm(0xA5)
        assert(reg32:get() == 0xA5, "reg32 set_imm")

        local vec_reg = dut.uut.vec_reg:chdl()
        for i = 0, 3 do
            assert(tonumber(vec_reg:get_index(i)) == i, "vec_reg init " .. i)
        end
        vec_reg:set_imm_index(2, 0x5A)
        assert(tonumber(vec_reg:get_index(2)) == 0x5A, "vec_reg set_imm_index")

        if is_dpi_flow then
            -- meta_only signal: meta (width/type) from the dpi table, value via
            -- mem_direct; no DPI accessor exists for it.
            local reg16 = dut.uut.reg16:chdl()
            assert(reg16.width == 16, "reg16 width from dpi meta")
            assert(reg16.hdl_type == "vpiReg", "reg16 hdl_type from dpi meta")
            assert(reg16.is_dpi_only == false, "reg16 must not be dpi_only")
            assert(reg16:get() == 16, "reg16 initial")
            reg16:set_imm(0x1234)
            assert(reg16:get() == 0x1234, "reg16 set_imm")
        end

        print("[test_mem_direct_vl_verilator] PASS")
        sim.finish()
    end
}

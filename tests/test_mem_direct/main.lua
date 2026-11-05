local ffi = require "ffi"
local vpiml = require "verilua.vpiml.vpiml"
local MemDirect = require "verilua.utils.MemDirect"

assert(MemDirect:try_init(), "[test_mem_direct] MemDirect:try_init failed")
assert(cfg.enable_mem_direct == true, "[test_mem_direct] enable_mem_direct not set")

local clock = dut.clock:chdl()
local reg32 = dut.u_top.reg32:chdl()
local reg64 = dut.u_top.reg64:chdl()
local reg128 = dut.u_top.reg128:chdl()
local vec_reg = dut.u_top.vec_reg:chdl()

-- Miss must not crash lookup
assert(MemDirect:lookup("tb_top.u_top.not_exported") == nil)

local function vpi_get(ch)
    return tonumber(vpiml.vpiml_get_value(ch.hdl))
end

local function vpi_get64(ch)
    return vpiml.vpiml_get_value64(ch.hdl)
end

fork {
    function()
        clock:posedge()

        -- Scalar 32-bit: mem get matches VPI get
        local md32 = reg32:get()
        local vpi32 = vpi_get(reg32)
        assert(md32 == vpi32, string.format("reg32 md=%s vpi=%s", tostring(md32), tostring(vpi32)))
        assert(md32 == 32, "reg32 expected initial 32, got " .. tostring(md32))

        -- set_imm via mem_direct, then read back (same memory as VPI)
        reg32:set_imm(0xA5)
        assert(reg32:get() == 0xA5, "reg32 set_imm/get mismatch")
        assert(vpi_get(reg32) == 0xA5, "reg32 VPI after set_imm mismatch")
        -- get_hex_str via mem_direct (no VPI); format lowercase hex by RTL width
        local hex32 = reg32:get_hex_str()
        assert(type(hex32) == "string" and #hex32 > 0, "reg32 get_hex_str empty")
        assert(tonumber(hex32, 16) == 0xA5, "reg32 get_hex_str value mismatch: " .. hex32)
        -- Prefer matching VPI hex when handle exists (ignore leading-zero policy)
        local vpi_hex = ffi.string(vpiml.vpiml_get_value_hex_str(reg32.hdl)):lower():gsub("^0*", "")
        local md_hex = hex32:lower():gsub("^0*", "")
        if md_hex == "" then
            md_hex = "0"
        end
        if vpi_hex == "" then
            vpi_hex = "0"
        end
        assert(md_hex == vpi_hex, string.format("reg32 hex md=%s vpi=%s", md_hex, vpi_hex))

        -- Normal pending set: after posedge, mem_direct get must see the new value
        -- and match VPI (mem path does not break VPI write visibility).
        reg32:set(0x11)
        assert(reg32:get() == 0xA5, "reg32 must not change before posedge after pending set")
        clock:posedge()
        assert(reg32:get() == 0x11, "reg32 mem get after default set+posedge")
        assert(vpi_get(reg32) == 0x11, "reg32 VPI get after default set+posedge")
        assert(reg32:get() == vpi_get(reg32), "reg32 mem/VPI diverge after pending set")

        -- 64-bit
        local md64 = reg64:get64()
        local vpi64 = vpi_get64(reg64)
        assert(tonumber(md64) == tonumber(vpi64), "reg64 md vs vpi")
        assert(tonumber(md64) == 64, "reg64 expected 64")
        reg64:set_imm(0x1234)
        assert(tonumber(reg64:get64()) == 0x1234, "reg64 set_imm")
        assert(tonumber(reg64:get_hex_str(), 16) == 0x1234, "reg64 get_hex_str")

        reg64:set(0x5678)
        clock:posedge()
        assert(tonumber(reg64:get64()) == 0x5678, "reg64 mem get after default set+posedge")
        assert(tonumber(vpi_get64(reg64)) == 0x5678, "reg64 VPI get after default set+posedge")

        -- Wide 128: get64 low part / multi beats present
        local md128 = reg128:get64()
        assert(md128 ~= nil, "reg128 get64 nil")
        local multi = reg128:get()
        assert(type(multi) == "cdata" or type(multi) == "table" or multi ~= nil, "reg128 get")

        reg128:set({ 0x111, 0, 0, 0 })
        clock:posedge()
        assert(tonumber(reg128:get64()) == 0x111, "reg128 mem get64 after default set+posedge")

        -- Array
        assert(vec_reg.is_array or (MemDirect:lookup("tb_top.u_top.vec_reg") or {}).array_size == 4)
        local entry = assert(MemDirect:lookup("tb_top.u_top.vec_reg"))
        assert(entry.array_size == 4, "vec_reg array_size")
        for i = 0, 3 do
            local v = vec_reg:get_index(i)
            assert(tonumber(v) == i, string.format("vec_reg[%d] expected %d got %s", i, i, tostring(v)))
        end
        vec_reg:set_imm_index(2, 0x5A)
        assert(tonumber(vec_reg:get_index(2)) == 0x5A, "vec_reg set_imm_index")

        -- Normal array set_index (pending) then mem get_index after posedge
        vec_reg:set_index(1, 0x3C)
        clock:posedge()
        assert(tonumber(vec_reg:get_index(1)) == 0x3C, "vec_reg mem get_index after set_index+posedge")

        -- Names listing
        local names = MemDirect:GetSignalNames("u_top.reg32")
        assert(#names >= 1, "GetSignalNames empty")

        print("[test_mem_direct] PASS")
        sim.finish()
    end
}

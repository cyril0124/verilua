local lester = require "lester"
local BitVec = require "BitVec"
local expect = lester.expect

fork {
    function ()
        local clock = dut.clock:chdl()
        local value16 = dut.value16:chdl()
        local value32 = dut.value32:chdl()
        local value64 = dut.value64:chdl()
        local value128 = dut.value128:chdl()

        dut.reset = 1
        clock:negedge(10)
        dut.reset = 0

        expect.equal(value128.width, 128)

        local value_u32_vec = {0x123, 0x456, 0x789, 0xabc}
        clock:negedge()
            value128:set(value_u32_vec)
        clock:negedge()
            local u32_vec = value128:get()
            for i = 1, u32_vec[0] do expect.equal(u32_vec[i], value_u32_vec[i]) end
            expect.equal(value128:get_str(HexStr), "00000abc000007890000045600000123")

        clock:negedge()
            local bitvec = BitVec("0", 128)
            bitvec(60, 123):set(0x12345678)
            value128:set(bitvec.u32_vec)

        clock:negedge()
            expect.equal(value128:get_str(HexStr), "00000000012345678000000000000000")

        clock:negedge()
            value32:set_hex_str("123456")

        clock:negedge()
            expect.equal(tostring(value32:get_bitvec()), "00123456")
            expect.equal(tostring(value128:get_bitvec()), "00000000012345678000000000000000")
            value32:set_hex_str("12345678")

        clock:negedge()
            expect.equal(tostring(value32:get_bitvec()), "12345678")

        clock:negedge()
            value64:set_hex_str("1234567890abcdef")
        clock:negedge()
            expect.equal(tostring(value64:get_bitvec()), "1234567890abcdef")
            expect.equal(tostring(value64:get_bitvec()), "1234567890abcdef")

        do
            local bv = value64:get_bitvec()
            bv:set_bitfield(32, 63, 0xdead)

            clock:negedge()
                value64:set_hex_str(tostring(bv))
            clock:negedge()
                expect.equal(value64:get_hex_str(), "0000dead90abcdef")

            bv:set_bitfield_hex_str(0, 15, "aabb")
            clock:negedge()
                value64:set(bv.u32_vec)
            clock:negedge()
                expect.equal(value64:get_hex_str(), "0000dead90abaabb")
        end

        do
            clock:negedge()
                value32:set_bitfield(16, 31, 0xdead)
            clock:negedge()
                expect.equal(value32:get_hex_str(), "dead5678")

            clock:negedge()
                value32:set_bitfield_hex_str(0, 15, "beef")
            clock:negedge()
                expect.equal(value32:get_hex_str(), "deadbeef")
        end

        do
            clock:negedge()
                value64:set_hex_str("0000000000000000")

            clock:negedge()
                value64:set_bitfield(32, 63, 0xdead)
            clock:negedge()
                expect.equal(value64:get_hex_str(), "0000dead00000000")

            clock:negedge()
                value64:set_bitfield_hex_str(0, 15, "beef")
            clock:negedge()
                expect.equal(value64:get_hex_str(), "0000dead0000beef")
        end

        do
            clock:negedge()
                value128:set_hex_str("000000000000000000000000")
            
            clock:negedge()
                value128:set_bitfield(64, 127, 0xdead)
            clock:negedge()
                expect.equal(value128:get_hex_str(), "000000000000dead0000000000000000")

            clock:negedge()
                value128:set_bitfield_hex_str(0, 15, "beef")
            clock:negedge()
                expect.equal(value128:get_hex_str(), "000000000000dead000000000000beef")
                expect.equal(tonumber(value128:get_bitvec():get_bitfield(0, 15)), 0xbeef)
                expect.equal(value128:get_bitvec():get_bitfield_hex_str(0, 15), "0000beef")
                expect.equal(value128:get_bitvec():get_bitfield_vec(0, 15), {0xbeef})
                expect.equal(value128:get_bitvec():get_bitfield_vec(0, 127), {0xbeef, 0x00, 0xdead, 0x00})
                assert(value128:get_bitvec():get_bitfield(0, 15) == 0xbeef)
        end

        do
            clock:negedge()
                value128.value = 0
            clock:negedge()
                value128:expect_hex_str("0")
            
            clock:negedge()
                value128.value = {0x123, 0x456, 0, 0}
            clock:negedge()
                value128:expect_hex_str("00000000000000000000045600000123")
            
            clock:negedge()
                value128.value = 0x7777777777777777ULL
            clock:negedge()
                value128:expect_hex_str("7777777777777777")

            local bv = BitVec("0", 128)
            
            clock:negedge()
                value128.value = bv
            clock:negedge()
                value128:expect_hex_str("0")

            clock:negedge()
                bv:set_bitfield_hex_str(110, 127, "1234")
                value128.value = bv
            clock:negedge()
                value128:expect_hex_str("048d0000000000000000000000000000")
        end

        print("Finish")
        sim.finish()
    end
}
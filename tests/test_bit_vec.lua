local ffi = require "ffi"
local lester = require "lester"
local BitVec = require "BitVec"

local describe, it, expect = lester.describe, lester.it, lester.expect
local assert, print, f = assert, print, string.format

lester.parse_args()

describe("BitVec test", function ()
    it("should work properly for get_bitfield()", function ()
        local tests = {
            -- 0 ~ 31
            {data = {0xFFFFFFFF}, s = 0, e = 31, expected = 0xFFFFFFFF},
    
            -- 0 ~ 31, 32 ~ 63
            {data = {0xFFFFFFFF, 0x00000000}, s = 0, e = 31, expected = 0xFFFFFFFF},
            {data = {0xFFFFFFFF, 0x00000000}, s = 32, e = 63, expected = 0x00000000},
            {data = {0x12345678, 0x9ABCDEF0}, s = 0, e = 15, expected = 0x5678},
            {data = {0x12345678, 0x9ABCDEF0}, s = 16, e = 31, expected = 0x1234},
            {data = {0x12345678, 0x9ABCDEF0}, s = 32, e = 47, expected = 0xDEF0},
            {data = {0x12345678, 0x9ABCDEF0}, s = 48, e = 63, expected = 0x9ABC},
            {data = {0xFFFFFFFF, 0xFFFFFFFF}, s = 32, e = 63, expected = 0xFFFFFFFF},
    
            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 33, e = 38, expected = 0x11},
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 65, e = 68, expected = 0xb},
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 30, e = 38, expected = 0x8c},
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 0, e = 63, expected = 0x12301010101ULL},
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 0, e = 63, expected = 0x12301010101ULL},
            {data = {0x01010101, 0x00000123, 0xff000456, 0x00001789}, s = 93, e = 120, expected = 0xbc4f},
            {data = {0x01010101, 0xdeadbeef, 0xff000456, 0x00001789}, s = 40, e = 103, expected = 0x89ff000456deadbeULL},
    
            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127, 128 ~ 159
            {data = {0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678}, s = 80, e = 140, expected = 0x1678deadbeefff00ULL},
            {data = {0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678}, s = 120, e = 133, expected = 0x38de},
            {data = ffi.new("uint64_t[?]", 6, {5, 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678}), s = 120, e = 133, expected = 0x38de},
        }
    
        for _, test in ipairs(tests) do
            local bitvec = BitVec(test.data)
            local result = bitvec:get_bitfield(test.s, test.e)
            -- print(type(result), bit.tohex(result), bit.tohex(test.expected), tostring(result == test.expected))
            assert(result == test.expected, f("Failed for s=%d, e=%d: expected 0x%x, got 0x%x", test.s, test.e, test.expected, result))
        end
    end)

    it("should work properly for set_bitfield()", function ()
        local tests = {
            -- 0 ~ 31
            {data = {0x00000000}, s = 0, e = 15, value = 0x1234, expected = {0x1234}},
            {data = {0x00000000}, s = 0, e = 31, value = 0xFFFFFFFF, expected = {0xFFFFFFFF}},
            {data = {0xFFFFFFFF}, s = 0, e = 31, value = 0x00000000, expected = {0x00000000}},
    
            -- 0 ~ 31, 32 ~ 63
            {data = {0x00000000, 0x00000000}, s = 32, e = 63, value = 0xFFFFFFFF, expected = {0x00000000, 0xFFFFFFFF}},
            {data = {0x12345678, 0x9ABCDEF0}, s = 0, e = 15, value = 0xFFFF, expected = {0x1234FFFF, 0x9ABCDEF0}},
            {data = {0x12345678, 0x9ABCDEF0}, s = 16, e = 31, value = 0xFFFF, expected = {0xFFFF5678, 0x9ABCDEF0}},
            {data = {0x12345678, 0x9ABCDEF0}, s = 32, e = 47, value = 0xFFFF, expected = {0x12345678, 0x9abcffff}},
            {data = {0x12345678, 0x9ABCDEF0}, s = 48, e = 63, value = 0xFFFF, expected = {0x12345678, 0xffffdef0}},
    
            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 33, e = 38, value = 0xFF, expected = {0x01010101, 0x0000017f, 0x00000456, 0x00001789}},
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 65, e = 68, value = 0xF, expected = {0x01010101, 0x00000123, 0x0000045e, 0x00001789}},
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 30, e = 38, value = 0xFFF, expected = {0xc1010101, 0x0000017f, 0x00000456, 0x00001789}},
            {data = {0x01010101, 0x00000123, 0x00000456, 0x00001789}, s = 0, e = 63, value = 0xFFFFFFFFFFFFFFFFULL, expected = {0xFFFFFFFF, 0xFFFFFFFF, 0x00000456, 0x00001789}},
            {data = {0x01010101, 0xdeadbeef, 0xff000456, 0x00001789}, s = 93, e = 120, value = 0xFFFF, expected = {0x01010101, 0xdeadbeef, 0xff000456, 0x00001FFF}},
            {data = {0x01010101, 0xdeadbeef, 0xff000456, 0x00001789}, s = 40, e = 103, value = 0xdeadbeefaabbccddULL, expected = {0x01010101, 0xbbccddef, 0xadbeefaa, 0x000017de}},
    
            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127, 128 ~ 159
            {data = {0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678}, s = 80, e = 140, value = 0xFFFFFFFFFFFFFFFFULL, expected = {0x01010101, 0xdeadbeef, 0xffff0456, 0xffffffff, 0x12345fff}},
            {data = {0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678}, s = 120, e = 133, value = 0xFFFF, expected = {0x01010101, 0xdeadbeef, 0xff000456, 0xffadbeef, 0x1234567f}},
        }
    
        for _, test in ipairs(tests) do
            local bitvec = BitVec(test.data)
            bitvec:set_bitfield(test.s, test.e, test.value)
            local result = bitvec.u32_vec
            for i, val in ipairs(result) do
                assert(val == test.expected[i], f("Failed for s=%d, e=%d: expected 0x%x at index %d, got 0x%x", test.s, test.e, test.expected[i], i, val))
            end
        end
    end)

    it("should get correct bit width", function ()
        local bitvec = BitVec({0x12345678})
        expect.equal(bitvec.bit_width, 32)

        local bitvec = BitVec({0x12345678, 0x9ABCDEF0})
        expect.equal(bitvec.bit_width, 64)

        local bitvec = BitVec({0x12345678, 0x9ABCDEF0, 0x12345678, 0x9ABCDEF0})
        expect.equal(bitvec.bit_width, 128)

        local bitvec = BitVec({0x12345678}, 28)
        expect.equal(bitvec.bit_width, 28)

        local bitvec = BitVec({0x12345678, 0x9ABCDEF0}, 56)
        expect.equal(bitvec.bit_width, 56)

        expect.fail(function () local a = BitVec({0x12345678}, 64) end, "Bit width must not exceed")
    end)
end)
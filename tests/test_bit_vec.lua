---@diagnostic disable: assign-type-mismatch

local ffi = require "ffi"
local lester = require "lester"
local BitVec = require "BitVec"

local describe, it, expect = lester.describe, lester.it, lester.expect
local assert, print, f = assert, print, string.format

lester.parse_args()

describe("BitVec test", function()
    it("should work properly for get_bitfield()", function()
        local tests = {
            -- 0 ~ 31
            { data = { 0xFFFFFFFF },                                                                               s = 0,   e = 31,  expected = 0xFFFFFFFF },
            { data = 0xFFFFFFFF,                                                                                   s = 0,   e = 31,  expected = 0xFFFFFFFF },

            -- 0 ~ 31, 32 ~ 63
            { data = { 0xFFFFFFFF, 0x00000000 },                                                                   s = 0,   e = 31,  expected = 0xFFFFFFFF },
            { data = { 0xFFFFFFFF, 0x00000000 },                                                                   s = 32,  e = 63,  expected = 0x00000000 },
            { data = { 0x12345678, 0x9ABCDEF0 },                                                                   s = 0,   e = 15,  expected = 0x5678 },
            { data = { 0x12345678, 0x9ABCDEF0 },                                                                   s = 16,  e = 31,  expected = 0x1234 },
            { data = { 0x12345678, 0x9ABCDEF0 },                                                                   s = 32,  e = 47,  expected = 0xDEF0 },
            { data = { 0x12345678, 0x9ABCDEF0 },                                                                   s = 48,  e = 63,  expected = 0x9ABC },
            { data = { 0xFFFFFFFF, 0xFFFFFFFF },                                                                   s = 32,  e = 63,  expected = 0xFFFFFFFF },

            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },                                           s = 33,  e = 38,  expected = 0x11 },
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },                                           s = 65,  e = 68,  expected = 0xb },
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },                                           s = 30,  e = 38,  expected = 0x8c },
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },                                           s = 0,   e = 63,  expected = 0x12301010101ULL },
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },                                           s = 0,   e = 63,  expected = 0x12301010101ULL },
            { data = { 0x01010101, 0x00000123, 0xff000456, 0x00001789 },                                           s = 93,  e = 120, expected = 0xbc4f },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0x00001789 },                                           s = 40,  e = 103, expected = 0x89ff000456deadbeULL },

            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127, 128 ~ 159
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 },                               s = 80,  e = 140, expected = 0x1678deadbeefff00ULL },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 },                               s = 120, e = 133, expected = 0x38de },
            { data = ffi.new("uint64_t[?]", 6, { 5, 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }), s = 120, e = 133, expected = 0x38de },
        }

        for _, test in ipairs(tests) do
            local bitvec = BitVec(test.data)
            local result = bitvec:get_bitfield(test.s, test.e)
            -- print(type(result), bit.tohex(result), bit.tohex(test.expected), tostring(result == test.expected))
            assert(result == test.expected,
                f("Failed for s=%d, e=%d: expected 0x%x, got 0x%x", test.s, test.e, test.expected, result))
        end
    end)

    it("should work properly for set_bitfield()", function()
        local tests = {
            -- 0 ~ 31
            { data = { 0x00000000 },                                                 s = 0,   e = 15,  value = 0x1234,                expected = { 0x1234 } },
            { data = { 0x00000000 },                                                 s = 0,   e = 15,  value = 0xFFFF,                expected = { 0xFFFF } },
            { data = 0,                                                              s = 0,   e = 15,  value = 0xFFFF,                expected = { 0xFFFF } },
            { data = { 0x00000000 },                                                 s = 0,   e = 31,  value = 0xFFFFFFFF,            expected = { 0xFFFFFFFF } },
            { data = { 0xFFFFFFFF },                                                 s = 0,   e = 31,  value = 0x00000000,            expected = { 0x00000000 } },

            -- 0 ~ 31, 32 ~ 63
            { data = { 0x00000000, 0x00000000 },                                     s = 32,  e = 63,  value = 0xFFFFFFFF,            expected = { 0x00000000, 0xFFFFFFFF } },
            { data = { 0x12345678, 0x9ABCDEF0 },                                     s = 0,   e = 15,  value = 0xFFFF,                expected = { 0x1234FFFF, 0x9ABCDEF0 } },
            { data = { 0x12345678, 0x9ABCDEF0 },                                     s = 16,  e = 31,  value = 0xFFFF,                expected = { 0xFFFF5678, 0x9ABCDEF0 } },
            { data = { 0x12345678, 0x9ABCDEF0 },                                     s = 32,  e = 47,  value = 0xFFFF,                expected = { 0x12345678, 0x9abcffff } },
            { data = { 0x12345678, 0x9ABCDEF0 },                                     s = 48,  e = 63,  value = 0xFFFF,                expected = { 0x12345678, 0xffffdef0 } },

            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },             s = 33,  e = 38,  value = 0xFF,                  expected = { 0x01010101, 0x0000017f, 0x00000456, 0x00001789 } },
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },             s = 65,  e = 68,  value = 0xF,                   expected = { 0x01010101, 0x00000123, 0x0000045e, 0x00001789 } },
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },             s = 30,  e = 38,  value = 0xFFF,                 expected = { 0xc1010101, 0x0000017f, 0x00000456, 0x00001789 } },
            { data = { 0x01010101, 0x00000123, 0x00000456, 0x00001789 },             s = 0,   e = 63,  value = 0xFFFFFFFFFFFFFFFFULL, expected = { 0xFFFFFFFF, 0xFFFFFFFF, 0x00000456, 0x00001789 } },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0x00001789 },             s = 93,  e = 120, value = 0xFFFF,                expected = { 0x01010101, 0xdeadbeef, 0xff000456, 0x00001FFF } },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0x00001789 },             s = 40,  e = 103, value = 0xdeadbeefaabbccddULL, expected = { 0x01010101, 0xbbccddef, 0xadbeefaa, 0x000017de } },

            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127, 128 ~ 159
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 80,  e = 140, value = 0xFFFFFFFFFFFFFFFFULL, expected = { 0x01010101, 0xdeadbeef, 0xffff0456, 0xffffffff, 0x12345fff } },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 120, e = 133, value = 0xFFFF,                expected = { 0x01010101, 0xdeadbeef, 0xff000456, 0xffadbeef, 0x1234567f } },
        }

        for _, test in ipairs(tests) do
            local bitvec = BitVec(test.data)
            bitvec:set_bitfield(test.s, test.e, test.value)
            local result = bitvec.u32_vec
            for i, val in ipairs(result) do
                assert(val == test.expected[i],
                    f("Failed for s=%d, e=%d: expected 0x%x at index %d, got 0x%x", test.s, test.e, test.expected[i], i,
                        val))
            end
        end
    end)

    it("should get correct bit width", function()
        local bitvec = BitVec({ 0x12345678 })
        expect.equal(bitvec.bit_width, 32)

        local bitvec = BitVec({ 0x12345678, 0x9ABCDEF0 })
        expect.equal(bitvec.bit_width, 64)

        local bitvec = BitVec({ 0x12345678, 0x9ABCDEF0, 0x12345678, 0x9ABCDEF0 })
        expect.equal(bitvec.bit_width, 128)

        local bitvec = BitVec({ 0x12345678 }, 28)
        expect.equal(bitvec.bit_width, 28)

        local bitvec = BitVec({ 0x12345678, 0x9ABCDEF0 }, 56)
        expect.equal(bitvec.bit_width, 56)

        expect.fail(function() local a = BitVec({ 0x12345678, 0x123, 0x446 }, 64) end, "must not exceed")
    end)

    it("should work properly for dump()", function()
        local bitvec = BitVec({ 0x12345678 })
        expect.equal(bitvec:dump_str(), "12345678")

        local bitvec = BitVec({ 0x12345678, 0x4455667788 })
        expect.equal(bitvec:dump_str(), "5566778812345678")
    end)

    it("should work properly for get_bitfield_hex_str()", function()
        local tests = {
            { data = { 0x12345678 },                                                 s = 0,  e = 15,      expected = nil },
            { data = { 0x12345678 },                                                 s = 16, e = 31,      expected = nil },
            { data = { 0x12345678 },                                                 s = 32, e = 47,      expected = nil },

            -- 0 ~ 31, 32 ~ 63
            { data = { 0x12345678, 0x11aabbcc },                                     s = 16, e = 31,      expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 16, e = 31 + 16, expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 40, e = 60,      expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 40, e = 60,      expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 0,  e = 15,      expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 0,  e = 40,      expected = "000001cc12345678" },

            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127, 128 ~ 159
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 35, e = 84,      expected = "0000008adbd5b7dd" },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 68, e = 155,     expected = "002345678deadbeefff00045" },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 0,  e = 159,     expected = "12345678deadbeefff000456deadbeef01010101" },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 0,  e = 128,     expected = "00000000deadbeefff000456deadbeef01010101" },
        }

        for _, test in ipairs(tests) do
            local bitvec = BitVec(test.data)
            local result = bitvec:get_bitfield_hex_str(test.s, test.e)
            local expected = test.expected
            if expected == nil then
                expected = bit.tohex(tonumber(bitvec:get_bitfield(test.s, test.e)) --[[@as integer]])
            end
            assert(result == expected,
                f("Failed for s=%d, e=%d: expected 0x%s, got 0x%s", test.s, test.e, expected, result))
        end
    end)

    it("should work properly for get_bitfield_vec()", function()
        local tests = {
            { data = { 0x12345678 },                                                 s = 0,  e = 15,      expected = nil },
            { data = { 0x12345678 },                                                 s = 16, e = 31,      expected = nil },
            { data = { 0x12345678 },                                                 s = 32, e = 47,      expected = nil },

            -- 0 ~ 31, 32 ~ 63
            { data = { 0x12345678, 0x11aabbcc },                                     s = 16, e = 31,      expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 16, e = 31 + 16, expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 40, e = 60,      expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 40, e = 60,      expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 0,  e = 15,      expected = nil },
            { data = { 0x12345678, 0x11aabbcc },                                     s = 0,  e = 40,      expected = { 0x12345678, 0x1cc } },

            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127, 128 ~ 159
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 35, e = 84,      expected = { 0xdbd5b7dd, 0x8a } },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 68, e = 155,     expected = { 0xfff00045, 0x8deadbee, 0x234567 } },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 0,  e = 159,     expected = { 0x1010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 } },
            { data = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x12345678 }, s = 0,  e = 128,     expected = { 0x01010101, 0xdeadbeef, 0xff000456, 0xdeadbeef, 0x0 } },
        }

        for _, test in ipairs(tests) do
            local bitvec = BitVec(test.data)
            local result = bitvec:get_bitfield_vec(test.s, test.e)
            local expected = test.expected
            if expected == nil then
                expected = { tonumber(bitvec:get_bitfield(test.s, test.e)) }
            end

            for i, _ in ipairs(result) do
                assert(expected[i] == result[i],
                    f("Failed for s=%d, e=%d: expected 0x%x at index %d, got 0x%x", test.s, test.e, expected[i], i,
                        result[i]))
            end
        end
    end)

    it("should work properly for set_bitfield_vec()", function()
        local tests = {
            { data = { 0x00 },                         s = 0,  e = 7,   value = { 0x10 },                               expected = { 0x10 } },
            { data = { 0x00 },                         s = 0,  e = 31,  value = { 0x12345678 },                         expected = { 0x12345678 } },
            { data = { 0x1234 },                       s = 16, e = 31,  value = { 0x12345678 },                         expected = { 0x56781234 } },

            { data = { 0x00, 0x1234 },                 s = 0,  e = 31,  value = { 0x12345678 },                         expected = { 0x12345678, 0x1234 } },
            { data = { 0x00, 0x1234 },                 s = 32, e = 48,  value = { 0x12345678 },                         expected = { 0x00, 0x5678 } },
            { data = { 0x00, 0x1234 },                 s = 16, e = 47,  value = { 0x12345678 },                         expected = { 0x56780000, 0x1234 } },

            -- 0 ~ 31, 32 ~ 63, 64 ~ 95
            { data = { 0x00, 0x1234, 0x5678 },         s = 0,  e = 47,  value = { 0x12345678, 0x22334455 },             expected = { 0x12345678, 0x4455, 0x5678 } },
            { data = { 0x00, 0x1234, 0x5678 },         s = 0,  e = 95,  value = { 0x12345678, 0x22334455, 0xaaaacccc }, expected = { 0x12345678, 0x22334455, 0xaaaacccc } },

            -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127
            { data = { 0x00, 0x1234, 0x5678, 0xdead }, s = 48, e = 100, value = { 0x12345678, 0x22334455 },             expected = { 0x00, 0x56781234, 0x44551234, 0xdeb3 } },
            { data = { 0x00, 0x1234, 0x5678, 0xdead }, s = 70, e = 110, value = { 0x12345678, 0x22334455 },             expected = { 0x00, 0x1234, 0x8d159e38, 0x9544 } },
        }

        for _, test in ipairs(tests) do
            local bitvec = BitVec(test.data)
            local result = bitvec.u32_vec
            bitvec:set_bitfield_vec(test.s, test.e, test.value)

            for i, _ in ipairs(result) do
                assert(result[i] == test.expected[i],
                    f("Failed for s=%d, e=%d: expected 0x%x at index %d, got 0x%x", test.s, test.e, test.expected[i], i,
                        result[i]))
            end
        end
    end)

    it("should work properly for set_bitfield_hex_str()", function()
        local tests = {
            { data = { 0x00 },                         s = 0,  e = 7,   value = "10",                       expected = { 0x10 } },
            { data = { 0x00 },                         s = 0,  e = 31,  value = "12345678",                 expected = { 0x12345678 } },
            { data = { 0x1234 },                       s = 16, e = 31,  value = "12345678",                 expected = { 0x56781234 } },

            { data = { 0x00, 0x1234 },                 s = 0,  e = 31,  value = "12345678",                 expected = { 0x12345678, 0x1234 } },
            { data = { 0x00, 0x1234 },                 s = 32, e = 48,  value = "12345678",                 expected = { 0x00, 0x5678 } },
            { data = { 0x00, 0x1234 },                 s = 16, e = 47,  value = "12345678",                 expected = { 0x56780000, 0x1234 } },

            -- -- 0 ~ 31, 32 ~ 63, 64 ~ 95
            { data = { 0x00, 0x1234, 0x5678 },         s = 0,  e = 47,  value = "2233445512345678",         expected = { 0x12345678, 0x4455, 0x5678 } },
            { data = { 0x00, 0x1234, 0x5678 },         s = 0,  e = 95,  value = "aaaacccc2233445512345678", expected = { 0x12345678, 0x22334455, 0xaaaacccc } },

            -- -- 0 ~ 31, 32 ~ 63, 64 ~ 95, 96 ~ 127
            { data = { 0x00, 0x1234, 0x5678, 0xdead }, s = 48, e = 100, value = "2233445512345678",         expected = { 0x00, 0x56781234, 0x44551234, 0xdeb3 } },
            { data = { 0x00, 0x1234, 0x5678, 0xdead }, s = 70, e = 110, value = "2233445512345678",         expected = { 0x00, 0x1234, 0x8d159e38, 0x9544 } },
        }

        for _, test in ipairs(tests) do
            local bitvec = BitVec(test.data)
            local result = bitvec.u32_vec
            bitvec:set_bitfield_hex_str(test.s, test.e, test.value)

            for i, _ in ipairs(result) do
                assert(result[i] == test.expected[i],
                    f("Failed for s=%d, e=%d: expected 0x%x at index %d, got 0x%x", test.s, test.e, test.expected[i], i,
                        result[i]))
            end
        end
    end)

    it("should work properly for creating BitVec using hex string", function()
        local bitvec = BitVec("a")
        assert(bitvec.bit_width == 4)
        assert(bitvec.u32_vec[1] == 0xa, bit.tohex(bitvec.u32_vec[1]))

        local bitvec = BitVec("1122")
        assert(bitvec.bit_width == 16)
        assert(bitvec.u32_vec[1] == 0x1122, bit.tohex(bitvec.u32_vec[1]))

        local bitvec = BitVec("12345678aabbccdd")
        assert(bitvec.bit_width == 64)
        assert(bitvec.u32_vec[2] == 0x12345678)
        assert(bitvec.u32_vec[1] == 0xaabbccdd)

        local bitvec = BitVec("2345678aabbccdd", 64)
        assert(bitvec.bit_width == 64)
        assert(bitvec.u32_vec[2] == 0x02345678)
        assert(bitvec.u32_vec[1] == 0xaabbccdd)

        local bitvec_1 = BitVec({ 0x123, 0x456, 0x789 })
        local bitvec_2 = BitVec("000007890000045600000123")
        expect.equal(bitvec_1:dump_str(), bitvec_2:dump_str())

        for _, bitvec in ipairs({ BitVec("", 64), BitVec({}, 64) }) do
            bitvec(0, 7):set(0x23)
            assert(bitvec.bit_width == 64)
            expect.equal(tonumber(bitvec(0, 7):get()), 0x23)
        end
    end)

    it("should work properly for creating BitVec using number", function()
        local bitvec = BitVec(0)
        expect.equal(#bitvec, 32)
        expect.equal(#(bitvec.u32_vec), 1)
        expect.equal(tostring(bitvec), "00000000")

        local bitvec = BitVec(0x12345678, 128)
        expect.equal(#bitvec, 128)
        expect.equal(#(bitvec.u32_vec), 4)
        expect.equal(tostring(bitvec), "00000000000000000000000012345678")
    end)

    it("should work properly for __tostring", function()
        local bitvec = BitVec("a")
        expect.equal(tostring(bitvec), "0000000a")
        expect.equal(bitvec:dump_str(), "0000000a")

        local bitvec = BitVec({ 0x123, 0x456 })
        expect.equal(bitvec:dump_str(), "0000045600000123")
        expect.equal(tostring(bitvec), "0000045600000123")
    end)

    it("should work properly for __call", function()
        local bitvec = BitVec({ 0x123, 0x456 })

        bitvec(0, 15):set(0xFF)
        expect.equal(bitvec:dump_str(), "00000456000000ff")
        expect.equal(tostring(bitvec), "00000456000000ff")

        bitvec(16, 31):set(0xFF)
        expect.equal(bitvec:dump_str(), "0000045600ff00ff")
        expect.equal(tostring(bitvec), "0000045600ff00ff")

        local tmp = bitvec(32, 47)
        tmp:set(0xFF)
        expect.equal(bitvec:dump_str(), "000000ff00ff00ff")
        expect.equal(tostring(bitvec), "000000ff00ff00ff")

        tmp.value = 0x123
        expect.equal(tostring(tmp), "00000123")
        expect.equal(tostring(bitvec), "0000012300ff00ff")

        tmp.value = "1123"
        expect.equal(tostring(tmp), "00001123")
        expect.equal(tostring(bitvec), "0000112300ff00ff")

        expect.equal(#tmp, (47 - 32) + 1)
    end)

    it("should work properly for __eq", function()
        local bitvec = BitVec({ 0x123, 0x456 })
        local bitvec2 = BitVec({ 0x123, 0x456 })
        assert(bitvec == bitvec2)

        local bitvec = BitVec({ 0x123, 0x456 })
        local bitvec2 = BitVec({ 0x1213, 0x456 })
        assert(bitvec ~= bitvec2)

        local bitvec = BitVec({ 0x123, 0x456, 0x01 })
        local bitvec2 = BitVec({ 0x123, 0x456 })
        assert(bitvec ~= bitvec2)

        local bitvec = BitVec({ 0x123, 0x456, 0x00 })
        local bitvec2 = BitVec({ 0x123, 0x456 })
        assert(bitvec == bitvec2)

        local bitvec = BitVec({ 0x123, 0x456 })
        local bitvec2 = BitVec({ 0x123, 0x456, 0x00 })
        assert(bitvec == bitvec2)

        local bitvec = BitVec({ 0x123, 0x456 })
        local bitvec2 = BitVec({ 0x123, 0x456, 0x01 })
        assert(bitvec ~= bitvec2)

        local bitvec = BitVec({ 0x00, 0x00 })
        local tmp = bitvec(12, 18)
        local tmp2 = bitvec(34, 38)
        tmp.value = 0x01
        tmp2.value = 0x02
        assert(tmp ~= tmp2)

        tmp.value = 0x05
        tmp2.value = "5"
        assert(tmp == tmp2)
    end)

    it("should work properly for __len", function()
        local bitvec = BitVec({ 0x123, 0x456 }, 63)
        expect.equal(#bitvec, 63)

        local bitvec = BitVec({ 0x123, 0x456, 0x789 })
        expect.equal(#bitvec, 96)
    end)

    it("should work properly for BitVec:update_value()", function()
        local bitvec = BitVec({ 0x123, 0x456, 0x789 })
        expect.equal(bitvec:dump_str(), "000007890000045600000123")

        bitvec:update_value({ 0x11, 0x22, 0x33 })
        expect.equal(bitvec:dump_str(), "000000330000002200000011")

        bitvec:update_value({ 0x11 })
        expect.equal(bitvec:dump_str(), "000000000000000000000011")

        bitvec:update_value(0)
        expect.equal(bitvec:dump_str(), "000000000000000000000000")

        bitvec:update_value("112233")
        expect.equal(bitvec:dump_str(), "000000000000000000112233")

        bitvec:update_value(0x1234000056780000ULL)
        expect.equal(bitvec:dump_str(), "000000001234000056780000")
    end)
end)

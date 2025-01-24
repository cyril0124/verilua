local ffi = require "ffi"
local inspect = require "inspect"
local lester = require "lester"
local utils = require "LuaUtils"

local describe, it, expect = lester.describe, lester.it, lester.expect
local assert, print, f = assert, print, string.format

describe("LuaUtils test", function ()
    it("should work for bitfield32() and bitfiled64()", function ()
        local tests = {
            {0xffffffff, 0, 1, 3},
            {0xffffffff, 0, 3, 15},
            {0xffffffff, 0, 4, 31},
            {0xffffffff, 0, 7, 255},
            {0xffffffff, 0, 15, 65535},
            {0xffffffff, 16, 31, 65535},
            {0xffffffff, 0, 31, 2 ^ 32 - 1},
        }
        for _, test in ipairs(tests) do
            local result = utils.bitfield32(test[2], test[3], test[1])
            assert(type(result) == "number", type(result))
            assert(result == test[4], tostring(result) .. " " .. tostring(test[4]))
        end

        for _, test in ipairs(tests) do
            local result = utils.bitfield64(test[2], test[3], test[1])
            assert(type(result) == "cdata", type(result))
            assert(result == test[4], tostring(result) .. " " .. tostring(test[4]))
        end

        local tests = {
            {0xffffffffffffffffULL, 0, 1, 3},
            {0xffffffffffffffffULL, 0, 3, 15},
            {0xffffffffffffffffULL, 0, 4, 31},
            {0xffffffffffffffffULL, 0, 7, 255},
            {0xffffffffffffffffULL, 0, 15, 65535},
            {0xffffffffffffffffULL, 16, 31, 65535},
            {0xffffffffffffffffULL, 0, 31, 2 ^ 32 - 1},
            {0xffffffffffffffffULL, 0, 63, 0xffffffffffffffffULL},
            {0xffffffffffffffffULL, 62, 63, 3},
            {0xffffffffffffffffULL, 63, 63, 1},
        }

        for _, test in ipairs(tests) do
            local result = utils.bitfield64(test[2], test[3], test[1])
            assert(type(result) == "cdata", type(result))
            assert(result == test[4], tostring(result) .. " " .. tostring(test[4]))
        end
    end)

    it("should work properly for bitfield_str()", function ()
        expect.equal(utils.bitfield_str("0000322", 8, 9, 10), "01")
        expect.equal(utils.bitfield_str("322", 0, 8), "101000010")
        expect.equal(utils.bitfield_str("322", 0, 9, 10), "0101000010")
        expect.equal(utils.bitfield_str("0x123", 0, 2), "011")
        expect.equal(utils.bitfield_str("0b0101", 0, 3), "0101") -- get: 0101
        expect.equal(utils.bitfield_str("0b01  01", 0, 3), "0101") -- get: 0101
        expect.equal(tonumber(utils.bitfield_str("123", 0, 6), 2), 123) -- get: 123
        expect.equal(tonumber(utils.bitfield_str("0x1000004", 0, 15), 2), 4) 
        expect.equal(utils.bitfield_str("0x12345678_12345678 12345678 12345678 12345678 12345678 12345678 12345678", 0, 4), "11000")
        expect.equal(utils.bitfield_str("0xff", 7, 7), "1")
        expect.equal(utils.bitfield_str("0x8000000000000000", 63, 63), "1")
    end)

    it("should work properly for bitpat_to_hexstr()", function ()
        assert(utils.bitpat_to_hexstr({
            {s = 0, e = 1, v = 2},
            {s = 4, e = 7, v = 4},
            {s = 63, e = 63, v = 1}
        }, 64) == "8000000000000042")

        assert(utils.bitpat_to_hexstr({
            {s = 0, e = 1, v = 2},
            {s = 4, e = 7, v = 4},
            {s = 127, e = 127, v = 1}
        }, 128) == "80000000000000000000000000000042")

        assert(utils.bitpat_to_hexstr({
            {s = 0, e = 1, v = 2},
            {s = 4, e = 7, v = 4},
            {s = 255, e = 255, v = 1}
        }, 256) == "8000000000000000000000000000000000000000000000000000000000000042")

        assert(utils.bitpat_to_hexstr({
            {s = 0, e = 1, v = 2},
            {s = 4, e = 7, v = 4},
            {s = 109, e = 109, v = 1}
        }, 110) == "00002000000000000000000000000042")

        assert(utils.bitpat_to_hexstr({
            {s = 0, e = 1, v = 2},
            {s = 4, e = 7, v = 4},
            {s = 65, e = 127, v = 0x11231}
        }, 128) == "00000000000224620000000000000042")

        assert(utils.bitpat_to_hexstr({
            {s = 0, e = 63, v = 0xdead}
        }, 512) == "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dead")

        assert(utils.bitpat_to_hexstr({
            {s = 0, e = 63, v = 0xdead},
            {s = 256, e = 255 + 63, v = 0xbeef},
        }, 512) == "000000000000000000000000000000000000000000000000000000000000beef000000000000000000000000000000000000000000000000000000000000dead")

        assert(utils.bitpat_to_hexstr({
            {s = 16, e = 51, v = 0x600000000ULL},
            {s = 0, e = 15, v = 0xdead}
        }, 64) == "000600000000dead")
    end)

    it("should work properly for urandom64() and urandom64_range()", function ()
        local success = false
        for i = 1, 10000 do
            local v = utils.urandom64()
            assert(type(v) == "cdata")
            if v >= 0xFFFFFFFULL then
                success = true
            end
        end
        assert(success)

        local tests = {
            {MIN = 0xFFFF, MAX = 0xFFFFF},
            {MIN = 0xFFFFFFFFULL, MAX = 0xFFFFFFFFFULL},
            {MIN = 0, MAX = 0xFFFFFFFFFFFFFFFFULL}
        }
        for i, v in ipairs(tests) do
            local MIN = v.MIN
            local MAX = v.MAX

            local random_count = 0
            local random_count_tbl = {}
            for i = 1, 10000 do
                local v = utils.urandom64_range(MIN, MAX)
                random_count_tbl[utils.to_hex_str(v)] = v
                assert(type(v) == "cdata")
                if v > MAX or v < MIN then
                    assert(false)
                end
            end

            for _, v in pairs(random_count_tbl) do
                random_count = random_count + 1
            end
            assert(random_count > 100, f("MIN: %s, MAX: %s, random_count: %d, random_count_tbl: %s", utils.to_hex_str(MIN), utils.to_hex_str(MAX), random_count, inspect(random_count_tbl)))
        end
    end)

    it("should work properly for str_group_by() and str_sep()", function ()
        local tests = {
            {"1234567890", 3, {"123", "456", "789", "0"}},
            {"1234567890", 4, {"1234", "5678", "90"}},
            {"1234567890", 5, {"12345", "67890"}},
            {"1234567890", 6, {"123456", "7890"}},
            {"1234567890", 7, {"1234567", "890"}},
        }
        for _, test in ipairs(tests) do
            local str = test[1]
            local nr_group = test[2]
            local result = test[3]
            expect.equal(utils.str_group_by(str, nr_group), result)
        end

        local tests = {
            {"1234567890", 3, "123,456,789,0", ","},
            {"1234567890", 4, "1234,5678,90", ","},
            {"1234567890", 5, "12345,67890", ","},
            {"1234567890", 6, "123456,7890", ","},
            {"1234567890", 7, "1234567,890", ","},
        }
        for _, test in ipairs(tests) do
            local str = test[1]
            local nr_group = test[2]
            local result = test[3]
            local separator = test[4]
            expect.equal(utils.str_sep(str, nr_group, separator), result)
        end
    end)

    it("should work properly for bitmask()", function ()
        local tests = {
            {n = 0, expected = 0},
            {n = 1, expected = 1},
            {n = 2, expected = 3},
            {n = 4, expected = 15},
            {n = 8, expected = 255},
            {n = 16, expected = 65535},
            {n = 32, expected = 0xFFFFFFFFULL},
            {n = 33, expected = 0x1FFFFFFFFULL},
            {n = 40, expected = 0xFFFFFFFFFFULL},
            {n = 48, expected = 0xFFFFFFFFFFFFULL},
            {n = 56, expected = 0xFFFFFFFFFFFFFFULL},
            {n = 64, expected = 0xFFFFFFFFFFFFFFFFULL}
        }
        
        for _, test in ipairs(tests) do
            local n = test.n
            local expected = test.expected
            local result = utils.bitmask(n)
            expect.equal(result, expected + 0ULL)
        end
    end)

    it("should work properly for to_hex_str()", function ()
        local tests = {
            {0x1234, "1234"},
            {0x12345678, "12345678"},
            {0xFFFFFFFF, "ffffffff"},
            {0xFFFFFFFFFULL, "0000000fffffffff"},
            {0xFFFFFFFFFFFFFFFFULL, "ffffffffffffffff"},
            {0x1234567890123456ULL, "1234567890123456"},
            {{0x1234, 0x2445}, "0000244500001234"},
            {{0x1234, 0x2445}, "00002445 00001234", " "},
            {{0x1234, 0x2445}, "00002445_00001234", "_"},
            {{0x1234, 0x2445ULL}, "000000000000244500001234"},
            {{0x1234, 0x2445ULL}, "0000000000002445_00001234", "_"},
            {{0x1234, 0x2445, 0x244}, "000002440000244500001234"},
            {ffi.new("uint32_t[?]", 4, {3, 0x1234, 0x2445, 0x244}), "000002440000244500001234"},
        }

        for _, test in ipairs(tests) do
            local v = test[1]
            local expected = test[2]
            local seperator = test[3]
            local result = utils.to_hex_str(v, seperator)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for reset_bits()", function ()
        local tests = {
            {0xFFFF, 0, 4, 0xFFF0},
            {0xFFFFFFFFFFFFFFFFULL, 0, 8, 0xFFFFFFFFFFFFFF00ULL},
            {0xFFFFFFFFFFFFFFFFULL, 8, 8, 0xFFFFFFFFFFFF00FFULL},
            {0xFFFFFFFFFFFFFFFFULL, 16, 16, 0xFFFFFFFF0000FFFFULL},
            {0xFFFFFFFFFFFFFFFFULL, 32, 32, 0x00000000FFFFFFFFULL},
            {0xFFFFFFFFFFFFFFFFULL, 0, 64, 0x0000000000000000ULL},
            {0x123456789ABCDEF0ULL, 4, 8, 0x123456789ABCD000ULL},
            {0x123456789ABCDEF0ULL, 16, 16, 0x123456780000DEF0ULL},
            {0x123456789ABCDEF0ULL, 32, 32, 0x000000009ABCDEF0ULL},
            {0x123456789ABCDEF0ULL, 48, 16, 0x000056789ABCDEF0ULL},
            {0x123456789ABCDEF0ULL, 60, 4, 0x023456789ABCDEF0ULL},
        }
    
        for i, test in ipairs(tests) do
            local value = test[1]
            local start = test[2]
            local length = test[3]
            local expected = test[4]
            local result = utils.reset_bits(value, start, length)
            expect.equal(result, expected + 0ULL)
        end
    end)

    it("should work properly for cover_with_n()", function ()
        local tests = {
            {128, 32, 4},
            {127, 32, 4},
            {96, 32, 3},
            {31, 32, 1},
            {0, 32, 0},
            {15, 3, 5},
            {14, 3, 5},
        }
        for i, test in ipairs(tests) do
            local value = test[1]
            local n = test[2]
            local expected = test[3]
            local result = utils.cover_with_n(value, n)
            expect.equal(result + 0ULL, expected + 0ULL)
        end
    end)

    it("should work properly for shuffle_bits_hex_str()", function ()
        local test = function(width, iter)
            local iter = iter or 100
            local tbl = {}
            for i = 1, iter do
                local ret = utils.shuffle_bits_hex_str(width)
                expect.equal(utils.bitfield_str("0x" .. ret, width, width), "0")
                for j = 1, width do
                    local v = utils.bitfield_str("0x".. ret, j - 1, j - 1)
                    if v == "1" and tbl[j] == nil then
                        tbl[j] = j
                        break
                    end
                end
            end
            return #tbl
        end

        for i = 1, 70 do
            expect.equal(test(i), i)
        end

        local test = function(width, iter)
            local iter = iter or 100
            local tbl = {}
            for i = 1, iter do
                local ret = utils.shuffle_bits(width)
                for j = 1, width do
                    local v = utils.bitfield_str("0x".. utils.to_hex_str(ret), j - 1, j - 1, width)
                    if v == "1" and tbl[j] == nil then
                        tbl[j] = j
                        break
                    end
                end
            end
            return #tbl
        end

        for i = 1, 64 do
            expect.equal(test(i), i)
        end
    end)
end)
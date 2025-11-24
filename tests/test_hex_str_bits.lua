local utils = require "verilua.LuaUtils"
local hsb = require "verilua.utils.HexStrBits"
local lester = require "lester"

local describe, it, expect = lester.describe, lester.it, lester.expect
local assert, f = assert, string.format

describe("LuaUtils test", function()
    it("should work properly for bitfield_hex_str()", function()
        expect.equal(hsb.bitfield_hex_str("123", 0, 3), f("%x", utils.bitfield64(0, 3, 0x123ULL)))
        expect.equal(hsb.bitfield_hex_str("123", 4, 7), f("%x", utils.bitfield64(4, 7, 0x123ULL)))
        expect.equal(hsb.bitfield_hex_str("123", 8, 11), f("%x", utils.bitfield64(8, 11, 0x123ULL)))
        expect.equal(hsb.bitfield_hex_str("1234", 0, 15), f("%x", utils.bitfield64(0, 15, 0x1234ULL)))
        expect.equal(hsb.bitfield_hex_str("abcd", 0, 3), f("%x", utils.bitfield64(0, 3, 0xabcdULL)))
        expect.equal(hsb.bitfield_hex_str("abcd", 4, 7), f("%x", utils.bitfield64(4, 7, 0xabcdULL)))
        expect.equal(hsb.bitfield_hex_str("abcd", 8, 11), f("%x", utils.bitfield64(8, 11, 0xabcdULL)))
        expect.equal(hsb.bitfield_hex_str("abcd", 12, 15), f("%x", utils.bitfield64(12, 15, 0xabcdULL)))

        expect.equal(hsb.bitfield_hex_str("123", 0, 3, 12), f("%x", utils.bitfield64(0, 3, 0x123ULL)))
        expect.equal(hsb.bitfield_hex_str("123", 4, 7, 12), f("%x", utils.bitfield64(4, 7, 0x123ULL)))
        expect.equal(hsb.bitfield_hex_str("123", 8, 11, 12), f("%x", utils.bitfield64(8, 11, 0x123ULL)))

        expect.equal(hsb.bitfield_hex_str("0", 0, 0), f("%x", utils.bitfield64(0, 0, 0x0ULL)))
        expect.equal(hsb.bitfield_hex_str("1", 0, 0), f("%x", utils.bitfield64(0, 0, 0x1ULL)))
        expect.equal(hsb.bitfield_hex_str("f", 0, 3), f("%x", utils.bitfield64(0, 3, 0xfULL)))
        expect.equal(hsb.bitfield_hex_str("ff", 0, 7), f("%x", utils.bitfield64(0, 7, 0xffULL)))

        expect.equal(hsb.bitfield_hex_str("ffffffff", 0, 31),
            f("%x", utils.bitfield64(0, 31, 0xffffffffULL)))
        expect.equal(hsb.bitfield_hex_str("ffffffffffffffff", 0, 63),
            f("%x", utils.bitfield64(0, 63, 0xffffffffffffffffULL)))

        expect.equal(hsb.bitfield_hex_str("1234", 2, 5), f("%x", utils.bitfield64(2, 5, 0x1234ULL)))
        expect.equal(hsb.bitfield_hex_str("abcd", 6, 9), f("%x", utils.bitfield64(6, 9, 0xabcdULL)))

        expect.equal(hsb.bitfield_hex_str("f", 0, 0), f("%x", utils.bitfield64(0, 0, 0xfULL)))
        expect.equal(hsb.bitfield_hex_str("f", 1, 1), f("%x", utils.bitfield64(1, 1, 0xfULL)))
        expect.equal(hsb.bitfield_hex_str("f", 2, 2), f("%x", utils.bitfield64(2, 2, 0xfULL)))
        expect.equal(hsb.bitfield_hex_str("f", 3, 3), f("%x", utils.bitfield64(3, 3, 0xfULL)))

        expect.equal(hsb.bitfield_hex_str("a", 0, 3), f("%x", utils.bitfield64(0, 3, 0xaULL)))
        expect.equal(hsb.bitfield_hex_str("5", 0, 2), f("%x", utils.bitfield64(0, 2, 0x5ULL)))
        expect.equal(hsb.bitfield_hex_str("5", 1, 2), f("%x", utils.bitfield64(1, 2, 0x5ULL)))
        expect.equal(hsb.bitfield_hex_str("5", 0, 1), f("%x", utils.bitfield64(0, 1, 0x5ULL)))
        expect.equal(hsb.bitfield_hex_str("5", 2, 3), f("%x", utils.bitfield64(2, 3, 0x5ULL)))

        expect.equal(hsb.bitfield_hex_str("12345678", 0, 31),
            f("%x", utils.bitfield64(0, 31, 0x12345678ULL)))
        expect.equal(hsb.bitfield_hex_str("12345678", 4, 19),
            f("%x", utils.bitfield64(4, 19, 0x12345678ULL)))
        expect.equal(hsb.bitfield_hex_str("12345678", 8, 23),
            f("%x", utils.bitfield64(8, 23, 0x12345678ULL)))
        expect.equal(hsb.bitfield_hex_str("12345678", 12, 27),
            f("%x", utils.bitfield64(12, 27, 0x12345678ULL)))

        expect.equal(hsb.bitfield_hex_str("12345678", 4, 11),
            f("%x", utils.bitfield64(4, 11, 0x12345678ULL)))
        expect.equal(hsb.bitfield_hex_str("12345678", 12, 19),
            f("%x", utils.bitfield64(12, 19, 0x12345678ULL)))
        expect.equal(hsb.bitfield_hex_str("12345678", 20, 27),
            f("%x", utils.bitfield64(20, 27, 0x12345678ULL)))

        expect.equal(hsb.bitfield_hex_str("123", 12, 15, 16), f("%x", utils.bitfield64(12, 15, 0x123ULL)))
        expect.equal(hsb.bitfield_hex_str("123", 8, 11, 16), f("%x", utils.bitfield64(8, 11, 0x123ULL)))
        expect.equal(hsb.bitfield_hex_str("123", 0, 3, 16), f("%x", utils.bitfield64(0, 3, 0x123ULL)))
        expect.equal(hsb.bitfield_hex_str("f", 4, 7, 8), f("%x", utils.bitfield64(4, 7, 0xfULL)))
        expect.equal(hsb.bitfield_hex_str("f", 0, 3, 8), f("%x", utils.bitfield64(0, 3, 0xfULL)))

        expect.equal(hsb.bitfield_hex_str("abcd", 0, 7), f("%x", utils.bitfield64(0, 7, 0xabcdULL)))
        expect.equal(hsb.bitfield_hex_str("abcd", 8, 15), f("%x", utils.bitfield64(8, 15, 0xabcdULL)))
        expect.equal(hsb.bitfield_hex_str("abcd", 4, 11), f("%x", utils.bitfield64(4, 11, 0xabcdULL)))

        expect.equal(hsb.bitfield_hex_str("1", 31, 31, 32), f("%x", utils.bitfield64(31, 31, 0x1ULL)))
        expect.equal(hsb.bitfield_hex_str("80000000", 31, 31, 32),
            f("%x", utils.bitfield64(31, 31, 0x80000000ULL)))
        expect.equal(hsb.bitfield_hex_str("1", 63, 63, 64), f("%x", utils.bitfield64(63, 63, 0x1ULL)))
        expect.equal(hsb.bitfield_hex_str("8000000000000000", 63, 63, 64),
            f("%x", utils.bitfield64(63, 63, 0x8000000000000000ULL)))

        expect.equal(hsb.bitfield_hex_str("5555", 0, 15), f("%x", utils.bitfield64(0, 15, 0x5555ULL)))
        expect.equal(hsb.bitfield_hex_str("aaaa", 0, 15), f("%x", utils.bitfield64(0, 15, 0xaaaaULL)))
        expect.equal(hsb.bitfield_hex_str("5555", 1, 14), f("%x", utils.bitfield64(1, 14, 0x5555ULL)))
        expect.equal(hsb.bitfield_hex_str("aaaa", 1, 14), f("%x", utils.bitfield64(1, 14, 0xaaaaULL)))

        expect.equal(hsb.bitfield_hex_str("12345678", 4, 11),
            f("%x", utils.bitfield64(4, 11, 0x12345678ULL)))
        expect.equal(hsb.bitfield_hex_str("abcd", 4, 7), f("%x", utils.bitfield64(4, 7, 0xabcdULL)))
        expect.equal(hsb.bitfield_hex_str("ffff", 0, 15), f("%x", utils.bitfield64(0, 15, 0xffffULL)))
        expect.equal(hsb.bitfield_hex_str("1", 0, 0), f("%x", utils.bitfield64(0, 0, 0x1ULL)))
        expect.equal(hsb.bitfield_hex_str("8000000000000000", 63, 63),
            f("%x", utils.bitfield64(63, 63, 0x8000000000000000ULL)))

        expect.equal(hsb.bitfield_hex_str("1234567890abcdef1234567890abcdef", 4, 19), "bcde")
        expect.equal(hsb.bitfield_hex_str("ffffffffffffffffffffffffffffffff", 32, 63), "ffffffff")
        expect.equal(hsb.bitfield_hex_str("abcdabcdabcdabcdabcdabcdabcdabcd", 60, 79), "abcda")
        expect.equal(hsb.bitfield_hex_str("1234567890abcdef1234567890abcdef1234567890abcdef", 10, 35), "2242af3")
    end)

    it("should work properly for trim_leading_zeros", function()
        local tests = {
            { "0",            "0" },
            { "1",            "1" },
            { "10",           "10" },
            { "010",          "10" },
            { "0000100",      "100" },
            { "000000000010", "10" },

            { "abcd",         "abcd" },
            { "00abcd",       "abcd" },
            { "0000abcd",     "abcd" },
        }
        for _, test in ipairs(tests) do
            local str = test[1]
            local expected = test[2]
            local result = hsb.trim_leading_zeros(str)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for lshift_hex_str", function()
        local tests = {
            { "0",    1,  nil, "0" },
            { "1",    0,  nil, "1" },
            { "1",    1,  nil, "2" },
            { "1",    2,  nil, "4" },
            { "1",    3,  nil, "8" },
            { "1",    4,  nil, "10" },
            { "f",    4,  nil, "f0" },
            { "ff",   4,  nil, "ff0" },
            { "abc",  4,  nil, "abc0" },
            { "1",    64, nil, "10000000000000000" },
            { "f",    1,  4,   "e" },
            { "f",    2,  4,   "c" },
            { "f",    3,  4,   "8" },
            { "f",    4,  4,   "0" },
            { "80",   1,  8,   "00" },
            { "7f",   1,  8,   "fe" },
            { "abc",  4,  12,  "bc0" },
            { "ffff", 8,  16,  "ff00" },
            { "1",    0,  8,   "01" },
            { "11",   4,  4,   "0" },
        }
        for _, test in ipairs(tests) do
            local hex_str = test[1]
            local n = test[2]
            local bitwidth = test[3]
            local expected = test[4]
            local result = hsb.lshift_hex_str(hex_str, n, bitwidth)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for rshift_hex_str", function()
        local tests = {
            { "0",     1, nil, "0" },
            { "1",     0, nil, "1" },
            { "1",     1, nil, "0" },
            { "2",     1, nil, "1" },
            { "f",     1, nil, "7" },
            { "f",     2, nil, "3" },
            { "f",     4, nil, "0" },
            { "10",    1, nil, "8" },
            { "100",   4, nil, "10" },
            { "100",   8, nil, "1" },
            { "abc",   4, nil, "ab" },
            { "abc",   8, nil, "a" },
            { "f",     1, 4,   "7" },
            { "1f",    1, 4,   "7" },
            { "100",   1, 8,   "00" },
            { "180",   1, 8,   "40" },
            { "abc",   4, 8,   "0b" },
            { "ffff",  8, 16,  "00ff" },
            { "1ffff", 8, 16,  "00ff" },
        }
        for _, test in ipairs(tests) do
            local hex_str = test[1]
            local n = test[2]
            local bitwidth = test[3]
            local expected = test[4]
            local result = hsb.rshift_hex_str(hex_str, n, bitwidth)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for bor_hex_str(), bxor_hex_str(), and band_hex_str()", function()
        local bit = require "bit"

        -- Helper function to generate random hex string
        local function random_hex_str(bits)
            local hex_chars = math.ceil(bits / 4)
            local result = {}
            for i = 1, hex_chars do
                result[i] = f("%x", math.random(0, 15))
            end
            return table.concat(result)
        end

        -- Helper function to compare results for 0-64 bit range using bit library as golden
        local function verify_with_bit_lib(hex1, hex2, bits, op_name)
            if bits > 64 then return end -- bit library only works up to 64 bits
            -- Also skip if hex strings are too long for safe tonumber conversion (> 52 bits = 13 hex chars)
            if #hex1 > 13 or #hex2 > 13 then return end

            local num1 = (tonumber(hex1, 16) or 0) + 0ULL
            local num2 = (tonumber(hex2, 16) or 0) + 0ULL

            local expected
            if op_name == "bor" then
                expected = bit.bor(num1, num2)
            elseif op_name == "bxor" then
                expected = bit.bxor(num1, num2)
            elseif op_name == "band" then
                expected = bit.band(num1, num2)
            end

            local expected_hex = f("%x", expected):lower()

            local actual
            if op_name == "bor" then
                actual = hsb.bor_hex_str(hex1, hex2)
            elseif op_name == "bxor" then
                actual = hsb.bxor_hex_str(hex1, hex2)
            elseif op_name == "band" then
                actual = hsb.band_hex_str(hex1, hex2)
            end

            expect.equal(actual, expected_hex,
                f("%s(%s, %s) = %s, expected %s (bits: %d)",
                    op_name, hex1, hex2, actual, expected_hex, bits))
        end

        -- Test 1-64 bits with bit library as golden reference
        print("\nTesting 1-64 bits with bit library as golden reference...")
        for bits = 1, 64 do
            for _ = 1, 5 do -- 5 random tests per bit width
                local hex1 = random_hex_str(bits)
                local hex2 = random_hex_str(bits)

                verify_with_bit_lib(hex1, hex2, bits, "bor")
                verify_with_bit_lib(hex1, hex2, bits, "bxor")
                verify_with_bit_lib(hex1, hex2, bits, "band")
            end
        end

        -- Test edge cases for all bit widths from 1 to 256
        print("\nTesting edge cases for 1-256 bits...")
        for bits = 1, 256 do
            local hex_chars = math.ceil(bits / 4)
            local all_zeros = string.rep("0", hex_chars)
            local all_ones = string.rep("f", hex_chars)

            -- Test OR operations
            expect.equal(hsb.bor_hex_str(all_zeros, all_zeros), "0")
            expect.equal(hsb.bor_hex_str(all_zeros, all_ones), all_ones)
            expect.equal(hsb.bor_hex_str(all_ones, all_zeros), all_ones)
            expect.equal(hsb.bor_hex_str(all_ones, all_ones), all_ones)

            -- Test XOR operations
            expect.equal(hsb.bxor_hex_str(all_zeros, all_zeros), "0")
            expect.equal(hsb.bxor_hex_str(all_zeros, all_ones), all_ones)
            expect.equal(hsb.bxor_hex_str(all_ones, all_zeros), all_ones)
            expect.equal(hsb.bxor_hex_str(all_ones, all_ones), "0")

            -- Test AND operations
            expect.equal(hsb.band_hex_str(all_zeros, all_zeros), "0")
            expect.equal(hsb.band_hex_str(all_zeros, all_ones), "0")
            expect.equal(hsb.band_hex_str(all_ones, all_zeros), "0")
            expect.equal(hsb.band_hex_str(all_ones, all_ones), all_ones)
        end

        -- Test specific bit patterns
        print("\nTesting specific bit patterns...")
        local test_patterns = {
            -- {hex1, hex2, expected_or, expected_xor, expected_and}
            { "0",    "0",    "0",    "0",    "0" },
            { "1",    "0",    "1",    "1",    "0" },
            { "f",    "0",    "f",    "f",    "0" },
            { "f",    "f",    "f",    "0",    "f" },
            { "a",    "5",    "f",    "f",    "0" }, -- 1010 | 0101 = 1111, 1010 ^ 0101 = 1111, 1010 & 0101 = 0000
            { "c",    "3",    "f",    "f",    "0" }, -- 1100 | 0011 = 1111, 1100 ^ 0011 = 1111, 1100 & 0011 = 0000
            { "ff",   "00",   "ff",   "ff",   "0" },
            { "ff",   "ff",   "ff",   "0",    "ff" },
            { "aa",   "55",   "ff",   "ff",   "0" },
            { "f0",   "0f",   "ff",   "ff",   "0" },
            { "1234", "5678", "567c", "444c", "1230" },
            { "abcd", "1234", "bbfd", "b9f9", "204" },
            { "ffff", "0000", "ffff", "ffff", "0" },
            { "ffff", "ffff", "ffff", "0",    "ffff" },
        }

        for _, test in ipairs(test_patterns) do
            local hex1, hex2 = test[1], test[2]
            local exp_or, exp_xor, exp_and = test[3], test[4], test[5]

            expect.equal(hsb.bor_hex_str(hex1, hex2), exp_or,
                f("bor(%s, %s)", hex1, hex2))
            expect.equal(hsb.bxor_hex_str(hex1, hex2), exp_xor,
                f("bxor(%s, %s)", hex1, hex2))
            expect.equal(hsb.band_hex_str(hex1, hex2), exp_and,
                f("band(%s, %s)", hex1, hex2))
        end

        -- Test different lengths
        print("\nTesting different length strings...")
        expect.equal(hsb.bor_hex_str("1", "ff"), "ff")
        expect.equal(hsb.bor_hex_str("ff", "1"), "ff")
        expect.equal(hsb.bxor_hex_str("1", "ff"), "fe")
        expect.equal(hsb.bxor_hex_str("ff", "1"), "fe")
        expect.equal(hsb.band_hex_str("1", "ff"), "1")
        expect.equal(hsb.band_hex_str("ff", "1"), "1")

        expect.equal(hsb.bor_hex_str("1234", "ff"), "12ff")
        expect.equal(hsb.bxor_hex_str("1234", "ff"), "12cb")
        expect.equal(hsb.band_hex_str("1234", "ff"), "34")

        -- Test large bit widths (65-256 bits)
        print("\nTesting large bit widths (65-256 bits)...")
        for bits = 65, 256, 16 do
            local hex_chars = math.ceil(bits / 4)

            -- Test with alternating pattern
            local pattern1 = string.rep("a", hex_chars) -- 1010...
            local pattern2 = string.rep("5", hex_chars) -- 0101...

            expect.equal(hsb.bor_hex_str(pattern1, pattern2), string.rep("f", hex_chars))
            expect.equal(hsb.bxor_hex_str(pattern1, pattern2), string.rep("f", hex_chars))
            expect.equal(hsb.band_hex_str(pattern1, pattern2), "0")

            -- Test with random values
            for _ = 1, 3 do
                local hex1 = random_hex_str(bits)
                local hex2 = random_hex_str(bits)

                -- Verify properties: OR >= max(a,b), AND <= min(a,b), XOR symmetric
                local or_result = hsb.bor_hex_str(hex1, hex2)
                local xor_result1 = hsb.bxor_hex_str(hex1, hex2)
                local xor_result2 = hsb.bxor_hex_str(hex2, hex1)
                local and_result = hsb.band_hex_str(hex1, hex2)

                -- XOR should be commutative
                expect.equal(xor_result1, xor_result2)

                -- OR should be commutative
                expect.equal(hsb.bor_hex_str(hex1, hex2), hsb.bor_hex_str(hex2, hex1))

                -- AND should be commutative
                expect.equal(hsb.band_hex_str(hex1, hex2), hsb.band_hex_str(hex2, hex1))
            end
        end

        -- Test boundary values
        print("\nTesting boundary values...")
        -- 128-bit boundaries
        expect.equal(hsb.bor_hex_str("0", string.rep("f", 32)), string.rep("f", 32))
        expect.equal(hsb.bxor_hex_str(string.rep("f", 32), string.rep("f", 32)), "0")
        expect.equal(hsb.band_hex_str(string.rep("f", 32), "0"), "0")

        -- 256-bit boundaries
        expect.equal(hsb.bor_hex_str("1", string.rep("0", 63) .. "1"), "1")
        expect.equal(hsb.bxor_hex_str(string.rep("f", 64), string.rep("a", 64)),
            string.rep("5", 64))

        -- Test with single bit set at various positions
        print("\nTesting single bit patterns...")
        for bit_pos = 0, 255, 32 do
            local hex_chars = math.ceil((bit_pos + 1) / 4)
            local hex_val = f("%x", bit.lshift(1, bit_pos % 64))
            if bit_pos >= 64 then
                hex_val = string.rep("0", hex_chars - #hex_val) .. hex_val
            end

            -- OR with zero should give original
            local result = hsb.bor_hex_str(hex_val, "0")
            expect.equal(result, hsb.trim_leading_zeros(hex_val))

            -- XOR with itself should give zero
            expect.equal(hsb.bxor_hex_str(hex_val, hex_val), "0")

            -- AND with all ones should give original
            local all_ones = string.rep("f", hex_chars)
            expect.equal(hsb.band_hex_str(hex_val, all_ones), hsb.trim_leading_zeros(hex_val))
        end

        print("\nAll bitwise operation tests passed!")
    end)

    it("should work properly for add_hex_str()", function()
        local bit = require "bit"

        -- Helper function to generate random hex string
        local function random_hex_str(bits)
            local hex_chars = math.ceil(bits / 4)
            local result = {}
            for i = 1, hex_chars do
                result[i] = f("%x", math.random(0, 15))
            end
            return table.concat(result)
        end

        -- Test basic addition without carry
        print("\nTesting basic addition without carry...")
        local test_cases_no_carry = {
            -- {hex1, hex2, expected_result, expected_carry}
            { "0",    "0",    "0",    false },
            { "1",    "0",    "1",    false },
            { "0",    "1",    "1",    false },
            { "1",    "1",    "2",    false },
            { "5",    "3",    "8",    false },
            { "a",    "5",    "f",    false },
            { "10",   "20",   "30",   false },
            { "ff",   "0",    "ff",   false },
            { "100",  "200",  "300",  false },
            { "1234", "5678", "68ac", false },
            { "abcd", "1234", "be01", false },
            { "7fff", "0",    "7fff", false },
            { "0",    "7fff", "7fff", false },
        }

        for _, test in ipairs(test_cases_no_carry) do
            local hex1, hex2, expected, exp_carry = test[1], test[2], test[3], test[4]
            local result, carry = hsb.add_hex_str(hex1, hex2)
            expect.equal(result, expected,
                f("add_hex_str(%s, %s) result", hex1, hex2))
            expect.equal(carry, exp_carry,
                f("add_hex_str(%s, %s) carry", hex1, hex2))
        end

        -- Test addition with carry
        print("\nTesting addition with carry...")
        local test_cases_with_carry = {
            -- {hex1, hex2, expected_result, expected_carry}
            { "f",        "1",        "10",        false },
            { "ff",       "1",        "100",       false },
            { "fff",      "1",        "1000",      false },
            { "ffff",     "1",        "10000",     false },
            { "f",        "f",        "1e",        false },
            { "ff",       "ff",       "1fe",       false },
            { "fff",      "fff",      "1ffe",      false },
            { "ffff",     "ffff",     "1fffe",     false },
            { "8000",     "8000",     "10000",     false },
            { "80000000", "80000000", "100000000", false },
            { "ffffffff", "1",        "100000000", false },
            { "ffffffff", "ffffffff", "1fffffffe", false },
        }

        for _, test in ipairs(test_cases_with_carry) do
            local hex1, hex2, expected, exp_carry = test[1], test[2], test[3], test[4]
            local result, carry = hsb.add_hex_str(hex1, hex2)
            expect.equal(result, expected,
                f("add_hex_str(%s, %s) result", hex1, hex2))
            expect.equal(carry, exp_carry,
                f("add_hex_str(%s, %s) carry", hex1, hex2))
        end

        -- Test overflow (carry out from MSB)
        print("\nTesting overflow cases...")
        local test_cases_overflow = {
            -- For 4-bit: f + 1 = 0 with carry
            -- For 8-bit: ff + 1 = 0 with carry
            -- etc.
        }

        -- Test 1-bit to 8-bit overflow
        for bits = 1, 8 do
            local hex_chars = math.ceil(bits / 4)
            local max_val = string.rep("f", hex_chars)
            local result, carry = hsb.add_hex_str(max_val, "1")
            -- Result should wrap around, but we don't truncate, so it becomes max_val + 1
            expect.equal(carry, false) -- No carry flag since we extended the result
        end

        -- Test where both operands are max value
        for bits = 4, 64, 4 do
            local hex_chars = math.ceil(bits / 4)
            local max_val = string.rep("f", hex_chars)
            local result, carry = hsb.add_hex_str(max_val, max_val)
            local expected = "1" .. string.rep("f", hex_chars - 1) .. "e"
            expect.equal(result, expected)
            -- Without bitwidth parameter, carry is always false (result extends naturally)
            expect.equal(carry, false)
        end

        -- Test different length operands
        print("\nTesting different length operands...")
        local diff_len_cases = {
            { "1",    "ff",       "100",       false },
            { "ff",   "1",        "100",       false },
            { "1",    "ffff",     "10000",     false },
            { "ffff", "1",        "10000",     false },
            { "123",  "456789",   "4568ac",    false },
            { "abc",  "def123",   "defbdf",    false },
            { "f",    "ffffffff", "10000000e", false },
        }

        for _, test in ipairs(diff_len_cases) do
            local hex1, hex2, expected, exp_carry = test[1], test[2], test[3], test[4]
            local result, carry = hsb.add_hex_str(hex1, hex2)
            expect.equal(result, expected,
                f("add_hex_str(%s, %s) result", hex1, hex2))
            expect.equal(carry, exp_carry,
                f("add_hex_str(%s, %s) carry", hex1, hex2))
        end

        -- Test commutativity
        print("\nTesting commutativity...")
        for _ = 1, 20 do
            local bits = math.random(1, 128)
            local hex1 = random_hex_str(bits)
            local hex2 = random_hex_str(bits)

            local result1, carry1 = hsb.add_hex_str(hex1, hex2)
            local result2, carry2 = hsb.add_hex_str(hex2, hex1)

            expect.equal(result1, result2,
                f("commutativity: %s + %s vs %s + %s", hex1, hex2, hex2, hex1))
            expect.equal(carry1, carry2,
                f("carry commutativity: %s + %s vs %s + %s", hex1, hex2, hex2, hex1))
        end

        -- Test identity (a + 0 = a)
        print("\nTesting identity property...")
        for bits = 1, 128, 8 do
            local hex = random_hex_str(bits)
            local result, carry = hsb.add_hex_str(hex, "0")
            expect.equal(result, hsb.trim_leading_zeros(hex))
            expect.equal(carry, false)

            result, carry = hsb.add_hex_str("0", hex)
            expect.equal(result, hsb.trim_leading_zeros(hex))
            expect.equal(carry, false)
        end

        -- Test systematic coverage for 1-64 bits with bitwidth parameter
        print("\nTesting 1-64 bits with bitwidth parameter...")
        for bits = 1, 64 do
            for _ = 1, 3 do
                local hex1 = random_hex_str(bits)
                local hex2 = random_hex_str(bits)

                -- Test addition with bitwidth
                local result, carry = hsb.add_hex_str(hex1, hex2, bits)

                -- Result should be truncated to bitwidth - check the numeric value fits
                local result_val = tonumber(result, 16) or 0
                local max_for_bitwidth = math.pow(2, bits) - 1
                expect.equal(result_val <= max_for_bitwidth, true,
                    f("Result %s (val=%d) should fit in %d bits (max=%d)",
                        result, result_val, bits, max_for_bitwidth))

                -- For small values we can verify with bit library
                if bits <= 30 then -- bit library has issues with bits=31,32 due to signed overflow
                    local num1 = tonumber(hex1, 16) or 0
                    local num2 = tonumber(hex2, 16) or 0
                    local mask = bit.lshift(1, bits) - 1
                    num1 = bit.band(num1, mask)
                    num2 = bit.band(num2, mask)

                    local expected_sum = num1 + num2
                    local expected_carry = expected_sum > mask
                    local expected_result = bit.band(expected_sum, mask)
                    local expected_hex = f("%x", expected_result)
                    -- Expand to match bitwidth
                    expected_hex = utils.expand_hex_str(expected_hex, bits)

                    expect.equal(result, expected_hex,
                        f("add(%s, %s, %d) result", hex1, hex2, bits))
                    expect.equal(carry, expected_carry,
                        f("add(%s, %s, %d) carry", hex1, hex2, bits))
                end
            end
        end

        -- Test 65-128 bits
        print("\nTesting 65-128 bits...")
        for bits = 65, 128, 8 do
            local hex_chars = math.ceil(bits / 4)

            -- Test max value + 1
            local max_val = string.rep("f", hex_chars)
            local result, carry = hsb.add_hex_str(max_val, "1")
            local expected = "1" .. string.rep("0", hex_chars)
            expect.equal(result, expected)
            expect.equal(carry, false)

            -- Test random values
            for _ = 1, 3 do
                local hex1 = random_hex_str(bits)
                local hex2 = random_hex_str(bits)

                local result1, carry1 = hsb.add_hex_str(hex1, hex2)
                local result2, carry2 = hsb.add_hex_str(hex2, hex1)

                expect.equal(result1, result2)
                expect.equal(carry1, carry2)
            end
        end

        -- Test 129-256 bits
        print("\nTesting 129-256 bits...")
        for bits = 129, 256, 16 do
            local hex_chars = math.ceil(bits / 4)

            -- Test max value + 1
            local max_val = string.rep("f", hex_chars)
            local result, carry = hsb.add_hex_str(max_val, "1")
            local expected = "1" .. string.rep("0", hex_chars)
            expect.equal(result, expected)
            expect.equal(carry, false)

            -- Test half max + half max (should not overflow)
            local half_max = "7" .. string.rep("f", hex_chars - 1)
            result, carry = hsb.add_hex_str(half_max, half_max)
            expect.equal(carry, false)

            -- Test random values
            for _ = 1, 3 do
                local hex1 = random_hex_str(bits)
                local hex2 = random_hex_str(bits)

                local result1, carry1 = hsb.add_hex_str(hex1, hex2)
                local result2, carry2 = hsb.add_hex_str(hex2, hex1)

                expect.equal(result1, result2)
                expect.equal(carry1, carry2)
            end
        end

        -- Test specific bit boundaries (32, 64, 128, 256)
        print("\nTesting bit boundaries...")
        local boundaries = { 32, 64, 128, 256 }
        for _, bits in ipairs(boundaries) do
            local hex_chars = math.ceil(bits / 4)
            local max_val = string.rep("f", hex_chars)
            local one = "1"

            -- max + 1 should give 1 followed by zeros
            local result, carry = hsb.add_hex_str(max_val, one)
            expect.equal(result, "1" .. string.rep("0", hex_chars))
            -- Without bitwidth parameter, carry is always false (result extends naturally)
            expect.equal(carry, false)

            -- max + max should give 1 followed by f...fe
            result, carry = hsb.add_hex_str(max_val, max_val)
            expect.equal(result, "1" .. string.rep("f", hex_chars - 1) .. "e")
            -- Without bitwidth parameter, carry is always false (result extends naturally)
            expect.equal(carry, false)

            -- Test power of 2 additions
            local power_of_2 = "1" .. string.rep("0", hex_chars - 1)
            result, carry = hsb.add_hex_str(power_of_2, power_of_2)
            expect.equal(result, "2" .. string.rep("0", hex_chars - 1))
            expect.equal(carry, false)
        end

        -- Test carry propagation
        print("\nTesting carry propagation...")
        local carry_prop_cases = {
            { "fff",        "1", "1000",        false },
            { "ffff",       "1", "10000",       false },
            { "fffff",      "1", "100000",      false },
            { "ffffff",     "1", "1000000",     false },
            { "fffffff",    "1", "10000000",    false },
            { "ffffffff",   "1", "100000000",   false },
            { "fffffffff",  "1", "1000000000",  false },
            { "ffffffffff", "1", "10000000000", false },
        }

        for _, test in ipairs(carry_prop_cases) do
            local hex1, hex2, expected, exp_carry = test[1], test[2], test[3], test[4]
            local result, carry = hsb.add_hex_str(hex1, hex2)
            expect.equal(result, expected,
                f("carry propagation: %s + %s", hex1, hex2))
            expect.equal(carry, exp_carry)
        end

        -- Test alternating bit patterns
        print("\nTesting alternating bit patterns...")
        for bits = 8, 256, 32 do
            local hex_chars = math.ceil(bits / 4)
            local pattern_a = string.rep("a", hex_chars) -- 1010...
            local pattern_5 = string.rep("5", hex_chars) -- 0101...

            local result, carry = hsb.add_hex_str(pattern_a, pattern_5)
            expect.equal(result, string.rep("f", hex_chars))
            expect.equal(carry, false)
        end

        -- Test sequential additions (a + b + c = (a + b) + c)
        print("\nTesting sequential additions (associativity)...")
        for _ = 1, 10 do
            local bits = math.random(32, 128)
            local hex1 = random_hex_str(bits)
            local hex2 = random_hex_str(bits)
            local hex3 = random_hex_str(bits)

            -- (a + b) + c
            local temp1, _ = hsb.add_hex_str(hex1, hex2)
            local result1, carry1 = hsb.add_hex_str(temp1, hex3)

            -- a + (b + c)
            local temp2, _ = hsb.add_hex_str(hex2, hex3)
            local result2, carry2 = hsb.add_hex_str(hex1, temp2)

            expect.equal(result1, result2,
                f("associativity: (%s + %s) + %s vs %s + (%s + %s)",
                    hex1, hex2, hex3, hex1, hex2, hex3))
            expect.equal(carry1, carry2)
        end

        -- Test edge case: single hex digit for all values 0-f
        print("\nTesting single hex digits...")
        for i = 0, 15 do
            for j = 0, 15 do
                local hex1 = f("%x", i)
                local hex2 = f("%x", j)
                local expected = f("%x", i + j)

                local result, carry = hsb.add_hex_str(hex1, hex2)
                expect.equal(result, expected,
                    f("%x + %x", i, j))
                expect.equal(carry, false)
            end
        end

        -- Test large number with small number
        print("\nTesting large + small additions...")
        for bits = 64, 256, 64 do
            local large = random_hex_str(bits)
            local small = random_hex_str(8) -- 8 bits = 2 hex chars

            local result1, carry1 = hsb.add_hex_str(large, small)
            local result2, carry2 = hsb.add_hex_str(small, large)

            expect.equal(result1, result2)
            expect.equal(carry1, carry2)
        end

        -- Test carry flag behavior
        print("\nTesting carry flag behavior...")
        -- Without bitwidth parameter, carry is always false since result extends naturally
        local max_64bit = string.rep("f", 16)
        local result, carry = hsb.add_hex_str(max_64bit, max_64bit)
        -- Result is 1ffffffffffffff (17 hex chars), carry is false (no bitwidth constraint)
        expect.equal(carry, false)

        -- With bitwidth parameter, carry indicates overflow
        result, carry = hsb.add_hex_str(max_64bit, max_64bit, 64)
        -- Result wraps to fit in 64 bits, carry is true
        expect.equal(carry, true)

        -- Test specific patterns without bitwidth - carry should always be false
        local no_bitwidth_cases = {
            { string.rep("f", 16), "1",                 "1" .. string.rep("0", 16), false },
            { string.rep("8", 16), string.rep("8", 16), "11111111111111110",        false },
        }

        for _, test in ipairs(no_bitwidth_cases) do
            local hex1, hex2, expected, exp_carry = test[1], test[2], test[3], test[4]
            local result, carry = hsb.add_hex_str(hex1, hex2)
            expect.equal(result, expected,
                f("no bitwidth: %s + %s",
                    hex1:sub(1, 10) .. "...", hex2:sub(1, 10) .. "..."))
            expect.equal(carry, exp_carry,
                f("no bitwidth carry: %s + %s",
                    string.sub(hex1, 1, 8) .. "...", string.sub(hex2, 1, 8) .. "..."))
        end

        print("\nAll add_hex_str tests passed!")
    end)

    it("should work properly for add_hex_str, bor_hex_str, bxor_hex_str, band_hex_str with bitwidth parameter",
        function()
            local bit = require "bit"

            -- Helper function to generate random hex string
            local function random_hex_str(bits)
                local hex_chars = math.ceil(bits / 4)
                local result = {}
                for i = 1, hex_chars do
                    result[i] = f("%x", math.random(0, 15))
                end
                return table.concat(result)
            end

            print("\nTesting add_hex_str with bitwidth parameter...")

            -- Test add_hex_str with various bitwidths
            local add_test_cases = {
                -- {hex1, hex2, bitwidth, expected_result, expected_carry}
                { "ff",   "1",   8,  "00",       true },  -- 255 + 1 = 256, truncated to 8 bits = 0, carry
                { "ff",   "1",   16, "0100",     false }, -- 255 + 1 = 256, fits in 16 bits
                { "ffff", "1",   16, "0000",     true },  -- 65535 + 1 = 65536, truncated to 16 bits = 0
                { "ffff", "1",   32, "00010000", false }, -- 65535 + 1 = 65536, fits in 32 bits
                { "f",    "f",   4,  "e",        true },  -- 15 + 15 = 30, truncated to 4 bits = 14
                { "f",    "f",   8,  "1e",       false }, -- 15 + 15 = 30, fits in 8 bits
                { "7f",   "1",   8,  "80",       false }, -- 127 + 1 = 128, fits in 8 bits
                { "80",   "80",  8,  "00",       true },  -- 128 + 128 = 256, truncated to 8 bits = 0
                { "123",  "456", 12, "579",      false }, -- No overflow in 12 bits
                { "fff",  "1",   12, "000",      true },  -- 4095 + 1 = 4096, truncated to 12 bits = 0
            }

            for _, test in ipairs(add_test_cases) do
                local hex1, hex2, bw, expected, exp_carry = test[1], test[2], test[3], test[4], test[5]
                local result, carry = hsb.add_hex_str(hex1, hex2, bw)
                expect.equal(result, expected,
                    f("add_hex_str(%s, %s, %d)", hex1, hex2, bw))
                expect.equal(carry, exp_carry,
                    f("add_hex_str(%s, %s, %d) carry", hex1, hex2, bw))
            end

            -- Test systematic coverage for 4-bit to 256-bit additions
            for bits = 4, 64, 4 do
                local max_val = string.rep("f", math.ceil(bits / 4))

                -- max + max with bitwidth should wrap
                local result, carry = hsb.add_hex_str(max_val, max_val, bits)
                local expected = string.rep("f", math.ceil(bits / 4) - 1) .. "e"
                expect.equal(result, expected,
                    f("max + max with bitwidth %d", bits))
                expect.equal(carry, true)

                -- max + 1 with bitwidth should wrap to 0
                result, carry = hsb.add_hex_str(max_val, "1", bits)
                local expected_zero = string.rep("0", math.ceil(bits / 4))
                expect.equal(result, expected_zero,
                    f("max + 1 with bitwidth %d", bits))
                expect.equal(carry, true)
            end

            print("\nTesting bor_hex_str with bitwidth parameter...")

            -- Test bor_hex_str with bitwidth
            local bor_test_cases = {
                { "ff",    "0",   8,  "ff" },
                { "ff",    "0",   4,  "f" },  -- Truncate to 4 bits
                { "1ff",   "0",   8,  "ff" }, -- Truncate to 8 bits
                { "f0",    "0f",  8,  "ff" },
                { "f0",    "0f",  4,  "f" },  -- Truncate to 4 bits
                { "a",     "5",   4,  "f" },
                { "1a",    "15",  8,  "1f" },
                { "123",   "456", 12, "577" },
                { "ffff",  "0",   16, "ffff" },
                { "1ffff", "0",   16, "ffff" }, -- Truncate to 16 bits
            }

            for _, test in ipairs(bor_test_cases) do
                local hex1, hex2, bw, expected = test[1], test[2], test[3], test[4]
                local result = hsb.bor_hex_str(hex1, hex2, bw)
                expect.equal(result, expected,
                    f("bor_hex_str(%s, %s, %d)", hex1, hex2, bw))
            end

            -- Test for all bit widths 1-256
            for bits = 1, 256, 8 do
                local hex_chars = math.ceil(bits / 4)
                local all_zeros = "0"

                -- Calculate the correct all_ones value for this bitwidth
                local all_ones
                if bits % 4 == 0 then
                    -- Bitwidth is multiple of 4, all hex digits are 'f'
                    all_ones = string.rep("f", hex_chars)
                else
                    -- Bitwidth is not multiple of 4, MSB digit is masked
                    local bits_in_msb = bits % 4
                    local msb_mask = (bit.lshift(1, bits_in_msb) - 1)
                    local msb_hex = f("%x", msb_mask)
                    if hex_chars > 1 then
                        all_ones = msb_hex .. string.rep("f", hex_chars - 1)
                    else
                        all_ones = msb_hex
                    end
                end

                -- all_ones OR all_zeros should be all_ones
                local result = hsb.bor_hex_str(all_ones, all_zeros, bits)
                expect.equal(result, all_ones)

                -- Test with larger input that needs truncation
                local larger_ones = string.rep("f", hex_chars) -- Unmasked all hex digits are 'f'
                local larger = "1" .. larger_ones
                result = hsb.bor_hex_str(larger, all_zeros, bits)
                expect.equal(result, all_ones,
                    f("bor truncation for %d bits", bits))
            end

            print("\nTesting bxor_hex_str with bitwidth parameter...")

            -- Test bxor_hex_str with bitwidth
            local bxor_test_cases = {
                { "ff",    "ff",  8,  "00" },
                { "ff",    "ff",  4,  "0" },  -- XOR same values = 0
                { "1ff",   "ff",  8,  "00" }, -- Truncate to 8 bits, then XOR
                { "f0",    "0f",  8,  "ff" },
                { "f0",    "0f",  4,  "f" },  -- Truncate to 4 bits
                { "a",     "5",   4,  "f" },
                { "1a",    "15",  8,  "0f" },
                { "123",   "456", 12, "575" },
                { "ffff",  "0",   16, "ffff" },
                { "1ffff", "1",   16, "fffe" }, -- Truncate to 16 bits
            }

            for _, test in ipairs(bxor_test_cases) do
                local hex1, hex2, bw, expected = test[1], test[2], test[3], test[4]
                local result = hsb.bxor_hex_str(hex1, hex2, bw)
                expect.equal(result, expected,
                    f("bxor_hex_str(%s, %s, %d)", hex1, hex2, bw))
            end

            -- Test XOR properties with bitwidth
            for bits = 4, 256, 16 do
                local hex_chars = math.ceil(bits / 4)
                local all_ones = string.rep("f", hex_chars)

                -- XOR with self should be 0
                local result = hsb.bxor_hex_str(all_ones, all_ones, bits)
                local expected_zero = string.rep("0", hex_chars)
                expect.equal(result, expected_zero,
                    f("XOR self = 0 for %d bits", bits))

                -- XOR with 0 should be identity
                result = hsb.bxor_hex_str(all_ones, "0", bits)
                expect.equal(result, all_ones,
                    f("XOR with 0 = identity for %d bits", bits))

                -- Test with truncation
                local larger = "1" .. all_ones
                result = hsb.bxor_hex_str(larger, "0", bits)
                expect.equal(result, all_ones,
                    f("bxor truncation for %d bits", bits))
            end

            print("\nTesting band_hex_str with bitwidth parameter...")

            -- Test band_hex_str with bitwidth
            local band_test_cases = {
                { "ff",    "0",    8,  "00" },
                { "ff",    "0",    4,  "0" },
                { "1ff",   "ff",   8,  "ff" }, -- Truncate to 8 bits, then AND
                { "f0",    "0f",   8,  "00" },
                { "f0",    "0f",   4,  "0" },
                { "ff",    "aa",   8,  "aa" },
                { "ff",    "55",   8,  "55" },
                { "1ff",   "1aa",  8,  "aa" },   -- Truncate to 8 bits
                { "ffff",  "0",    16, "0000" },
                { "1ffff", "ffff", 16, "ffff" }, -- Truncate to 16 bits
            }

            for _, test in ipairs(band_test_cases) do
                local hex1, hex2, bw, expected = test[1], test[2], test[3], test[4]
                local result = hsb.band_hex_str(hex1, hex2, bw)
                expect.equal(result, expected,
                    f("band_hex_str(%s, %s, %d)", hex1, hex2, bw))
            end

            -- Test AND properties with bitwidth
            for bits = 4, 256, 16 do
                local hex_chars = math.ceil(bits / 4)
                local all_ones = string.rep("f", hex_chars)
                local all_zeros = "0"

                -- AND with 0 should be 0
                local result = hsb.band_hex_str(all_ones, all_zeros, bits)
                local expected_zero = string.rep("0", hex_chars)
                expect.equal(result, expected_zero,
                    f("AND with 0 = 0 for %d bits", bits))

                -- AND with all_ones should be identity
                result = hsb.band_hex_str(all_ones, all_ones, bits)
                expect.equal(result, all_ones,
                    f("AND with all_ones = identity for %d bits", bits))

                -- Test with truncation
                local larger1 = "1" .. all_ones
                local larger2 = "1" .. string.rep("0", hex_chars)
                result = hsb.band_hex_str(larger1, larger2, bits)
                local expected_zero = string.rep("0", hex_chars)
                expect.equal(result, expected_zero,
                    f("band truncation for %d bits", bits))
            end

            -- Test combinations: use bitwise ops result as input to add
            print("\nTesting combinations of operations with bitwidth...")
            for bits = 8, 64, 8 do
                local hex1 = random_hex_str(bits)
                local hex2 = random_hex_str(bits)

                -- (a OR b) + (a AND b) should equal a + b (with carry consideration)
                local or_result = hsb.bor_hex_str(hex1, hex2, bits)
                local and_result = hsb.band_hex_str(hex1, hex2, bits)
                local sum1, carry1 = hsb.add_hex_str(or_result, and_result, bits)
                local sum2, carry2 = hsb.add_hex_str(hex1, hex2, bits)

                expect.equal(sum1, sum2,
                    f("(a OR b) + (a AND b) = a + b for %d bits", bits))
                expect.equal(carry1, carry2)
            end

            -- Test edge cases: all operations with max values
            print("\nTesting edge cases with max values and bitwidth...")
            for bits = 4, 64, 4 do
                local hex_chars = math.ceil(bits / 4)
                -- Create proper max value for this bitwidth
                local max_val
                if bits % 4 == 0 then
                    max_val = string.rep("f", hex_chars)
                else
                    local bits_in_msb = bits % 4
                    local msb_mask = (bit.lshift(1, bits_in_msb) - 1)
                    local msb_hex = f("%x", msb_mask)
                    if hex_chars > 1 then
                        max_val = msb_hex .. string.rep("f", hex_chars - 1)
                    else
                        max_val = msb_hex
                    end
                end

                -- OR: max OR max = max
                local result = hsb.bor_hex_str(max_val, max_val, bits)
                expect.equal(result, max_val)

                -- XOR: max XOR max = 0
                result = hsb.bxor_hex_str(max_val, max_val, bits)
                local expected_zero = string.rep("0", hex_chars)
                expect.equal(result, expected_zero)

                -- AND: max AND max = max
                result = hsb.band_hex_str(max_val, max_val, bits)
                expect.equal(result, max_val)

                -- ADD: max + max with truncation
                local add_result, carry = hsb.add_hex_str(max_val, max_val, bits)
                -- max + max = 2*max which overflows for any bitwidth
                -- Calculate expected result: For N-bit max value (all 1s), max + max = 2*max = all 1s << 1 = all 1s followed by 0
                -- After masking to N bits: lowest N bits of (2*max) = all 1s except LSB = 0
                -- In hex: if all hex digits are 'f', then result is 'fff...fe'
                local expected
                if bits % 4 == 0 then
                    expected = string.rep("f", hex_chars - 1) .. "e"
                else
                    -- Handle non-multiple of 4
                    local bits_in_msb = bits % 4
                    local msb_mask = (bit.lshift(1, bits_in_msb) - 1)
                    local msb_max = msb_mask
                    -- When we add max + max, we get: max_val * 2
                    -- For bits not multiple of 4, the MSB hex digit is masked
                    -- After doubling and truncating, we need to recalculate
                    -- Actually, the pattern still holds: result is all 1s except LSB=0
                    expected = string.rep("f", hex_chars - 1) .. "e"
                end
                expect.equal(add_result, expected)
                expect.equal(carry, true) -- max + max always overflows
            end

            -- Test with very large bitwidths (128, 256)
            print("\nTesting large bitwidths (128, 256)...")
            for _, bits in ipairs({ 128, 256 }) do
                local hex_chars = math.ceil(bits / 4)
                local max_val = string.rep("f", hex_chars)
                local half_max = "7" .. string.rep("f", hex_chars - 1)

                -- Test all operations
                local result = hsb.bor_hex_str(half_max, half_max, bits)
                expect.equal(result, half_max)

                result = hsb.bxor_hex_str(half_max, half_max, bits)
                local expected_zero = string.rep("0", hex_chars)
                expect.equal(result, expected_zero)

                result = hsb.band_hex_str(half_max, half_max, bits)
                expect.equal(result, half_max)

                local add_result, carry = hsb.add_hex_str(half_max, half_max, bits)
                -- half_max + half_max should not overflow for these bit widths
                expect.equal(carry, false)
            end

            -- Test bitwidth parameter padding (result smaller than bitwidth)
            print("\nTesting bitwidth padding...")
            local padding_tests = {
                { op = "bor",  hex1 = "1", hex2 = "2", bitwidth = 8,  min_len = 1 },
                { op = "bxor", hex1 = "1", hex2 = "2", bitwidth = 16, min_len = 1 },
                { op = "band", hex1 = "f", hex2 = "f", bitwidth = 8,  min_len = 1 },
                { op = "add",  hex1 = "1", hex2 = "1", bitwidth = 8,  min_len = 1 },
            }

            for _, test in ipairs(padding_tests) do
                local result
                if test.op == "bor" then
                    result = hsb.bor_hex_str(test.hex1, test.hex2, test.bitwidth)
                elseif test.op == "bxor" then
                    result = hsb.bxor_hex_str(test.hex1, test.hex2, test.bitwidth)
                elseif test.op == "band" then
                    result = hsb.band_hex_str(test.hex1, test.hex2, test.bitwidth)
                elseif test.op == "add" then
                    result = hsb.add_hex_str(test.hex1, test.hex2, test.bitwidth)
                end

                -- Result should be valid hex string
                expect.equal(type(result), "string")
                expect.equal(#result >= test.min_len, true,
                    f("%s result length check", test.op))
            end

            -- Verify backward compatibility (no bitwidth parameter)
            print("\nTesting backward compatibility (no bitwidth)...")
            local compat_tests = {
                { op = "bor",  hex1 = "ff", hex2 = "0",  expected = "ff" },
                { op = "bxor", hex1 = "ff", hex2 = "ff", expected = "0" },
                { op = "band", hex1 = "ff", hex2 = "aa", expected = "aa" },
                { op = "add",  hex1 = "ff", hex2 = "1",  expected = "100" },
            }

            for _, test in ipairs(compat_tests) do
                local result
                if test.op == "bor" then
                    result = hsb.bor_hex_str(test.hex1, test.hex2)
                elseif test.op == "bxor" then
                    result = hsb.bxor_hex_str(test.hex1, test.hex2)
                elseif test.op == "band" then
                    result = hsb.band_hex_str(test.hex1, test.hex2)
                elseif test.op == "add" then
                    result = hsb.add_hex_str(test.hex1, test.hex2)
                end

                expect.equal(result, test.expected,
                    f("%s backward compatibility", test.op))
            end

            print("\nAll bitwidth parameter tests passed!")
        end)

    it("should work properly for bnot_hex_str()", function()
        local bit = require "bit"

        -- Helper function to generate random hex string
        local function random_hex_str(bits)
            local hex_chars = math.ceil(bits / 4)
            local result = {}
            for i = 1, hex_chars do
                result[i] = f("%x", math.random(0, 15))
            end
            return table.concat(result)
        end

        print("\nTesting bnot_hex_str basic functionality...")

        -- Test basic NOT operations without bitwidth parameter
        local basic_tests = {
            -- {input, expected_output (trimmed leading zeros)}
            { "0",        "f" },        -- 4-bit: NOT 0000 = 1111
            { "f",        "0" },        -- 4-bit: NOT 1111 = 0000
            { "00",       "ff" },       -- 8-bit: NOT 00000000 = 11111111
            { "ff",       "0" },        -- 8-bit: NOT 11111111 = 00000000 -> trimmed to "0"
            { "a",        "5" },        -- 4-bit: NOT 1010 = 0101
            { "5",        "a" },        -- 4-bit: NOT 0101 = 1010
            { "aa",       "55" },       -- 8-bit: NOT 10101010 = 01010101
            { "55",       "aa" },       -- 8-bit: NOT 01010101 = 10101010
            { "0f",       "f0" },       -- 8-bit: NOT 00001111 = 11110000
            { "f0",       "f" },        -- 8-bit: NOT 11110000 = 00001111 -> trimmed to "f"
            { "1234",     "edcb" },     -- 16-bit
            { "ffff",     "0" },        -- 16-bit -> trimmed to "0"
            { "0000",     "ffff" },     -- 16-bit
            { "abcd",     "5432" },     -- 16-bit
            { "deadbeef", "21524110" }, -- 32-bit
            { "12345678", "edcba987" }, -- 32-bit
            { "ffffffff", "0" },        -- 32-bit -> trimmed to "0"
        }

        for _, test in ipairs(basic_tests) do
            local input, expected = test[1], test[2]
            local result = hsb.bnot_hex_str(input)
            expect.equal(result, expected,
                f("bnot_hex_str(%s) without bitwidth", input))
        end

        print("\nTesting bnot_hex_str with explicit bitwidth parameter...")

        -- Test NOT operations with explicit bitwidth
        local bitwidth_tests = {
            -- {input, bitwidth, expected_output}
            { "0",    4,  "f" },        -- 4-bit: NOT 0 = f
            { "f",    4,  "0" },        -- 4-bit: NOT f = 0
            { "0",    8,  "ff" },       -- 8-bit: NOT 00 = ff
            { "ff",   8,  "00" },       -- 8-bit: NOT ff = 00
            { "0",    16, "ffff" },     -- 16-bit: NOT 0000 = ffff
            { "ffff", 16, "0000" },     -- 16-bit: NOT ffff = 0000
            { "a",    4,  "5" },        -- 4-bit: NOT a = 5
            { "5",    4,  "a" },        -- 4-bit: NOT 5 = a
            { "aa",   8,  "55" },       -- 8-bit: NOT aa = 55
            { "55",   8,  "aa" },       -- 8-bit: NOT 55 = aa
            { "f0",   8,  "0f" },       -- 8-bit: NOT f0 = 0f
            { "0f",   8,  "f0" },       -- 8-bit: NOT 0f = f0
            { "1",    4,  "e" },        -- 4-bit: NOT 0001 = 1110
            { "1",    8,  "fe" },       -- 8-bit: NOT 00000001 = 11111110
            { "1",    16, "fffe" },     -- 16-bit: NOT 0000000000000001 = 1111111111111110
            { "1",    32, "fffffffe" }, -- 32-bit
            { "7",    4,  "8" },        -- 4-bit: NOT 0111 = 1000
            { "7f",   8,  "80" },       -- 8-bit: NOT 01111111 = 10000000
            { "1234", 16, "edcb" },     -- 16-bit
            { "1234", 12, "dcb" },      -- 12-bit: truncate input to 12 bits (234), NOT 0x234 = 0xdcb
        }

        for _, test in ipairs(bitwidth_tests) do
            local input, bitwidth, expected = test[1], test[2], test[3]
            local result = hsb.bnot_hex_str(input, bitwidth)
            expect.equal(result, expected,
                f("bnot_hex_str(%s, %d)", input, bitwidth))
        end

        print("\nTesting bnot_hex_str double negation property...")

        -- Test double negation: NOT(NOT(x)) = x
        for bits = 4, 64, 4 do
            local hex = random_hex_str(bits)
            local not1 = hsb.bnot_hex_str(hex, bits)
            local not2 = hsb.bnot_hex_str(not1, bits)

            -- Expand original hex to match bitwidth for comparison
            local expected = utils.expand_hex_str(hex, bits)
            expect.equal(not2, expected,
                f("double negation for %d bits", bits))
        end

        print("\nTesting bnot_hex_str with bit library verification (1-64 bits)...")

        -- Verify against bit library for 1-64 bits
        for bits = 1, 64 do
            -- Test a few values per bitwidth
            for _ = 1, 3 do
                local hex = random_hex_str(bits)
                local result = hsb.bnot_hex_str(hex, bits)

                -- For small values, verify with bit library
                if bits <= 30 then
                    local num = tonumber(hex, 16) or 0
                    local mask = bit.lshift(1, bits) - 1
                    num = bit.band(num, mask)

                    local expected_num = bit.band(bit.bnot(num), mask)
                    local expected_hex = f("%x", expected_num)
                    expected_hex = utils.expand_hex_str(expected_hex, bits)

                    expect.equal(result, expected_hex,
                        f("bnot(%s, %d) verified with bit library", hex, bits))
                end
            end
        end

        print("\nTesting bnot_hex_str edge cases...")

        -- Test all single hex digits
        for i = 0, 15 do
            local hex = f("%x", i)
            local result = hsb.bnot_hex_str(hex, 4)
            local expected_num = bit.band(bit.bnot(i), 0xF)
            local expected = f("%x", expected_num)
            expect.equal(result, expected,
                f("bnot single digit %s", hex))
        end

        -- Test alternating patterns
        local pattern_tests = {
            { "aaaa", 16, "5555" }, -- 1010... -> 0101...
            { "5555", 16, "aaaa" }, -- 0101... -> 1010...
            { "ff00", 16, "00ff" }, -- 11110000... -> 00001111...
            { "00ff", 16, "ff00" }, -- 00001111... -> 11110000...
        }

        for _, test in ipairs(pattern_tests) do
            local input, bitwidth, expected = test[1], test[2], test[3]
            local result = hsb.bnot_hex_str(input, bitwidth)
            expect.equal(result, expected,
                f("bnot pattern %s", input))
        end

        print("\nTesting bnot_hex_str with large bit widths (65-256 bits)...")

        -- Test large bitwidths
        for bits = 65, 256, 16 do
            local hex_chars = math.ceil(bits / 4)

            -- Test all zeros -> all ones
            local all_zeros = "0"
            local result = hsb.bnot_hex_str(all_zeros, bits)
            -- Calculate expected all ones for this bitwidth
            local expected_ones
            if bits % 4 == 0 then
                expected_ones = string.rep("f", hex_chars)
            else
                local bits_in_msb = bits % 4
                local msb_mask = bit.lshift(1, bits_in_msb) - 1
                local msb_hex = f("%x", msb_mask)
                expected_ones = msb_hex .. string.rep("f", hex_chars - 1)
            end
            expect.equal(result, expected_ones,
                f("bnot all zeros for %d bits", bits))

            -- Test all ones -> all zeros
            local all_ones = string.rep("f", hex_chars)
            result = hsb.bnot_hex_str(all_ones, bits)
            local expected_zeros = string.rep("0", hex_chars)
            expect.equal(result, expected_zeros,
                f("bnot all ones for %d bits", bits))

            -- Test random values with double negation
            for _ = 1, 3 do
                local hex = random_hex_str(bits)
                -- Mask the input to ensure it fits within bitwidth
                local masked_hex = hsb.bnot_hex_str(hsb.bnot_hex_str(hex, bits), bits)
                local not1 = hsb.bnot_hex_str(hex, bits)
                local not2 = hsb.bnot_hex_str(not1, bits)
                expect.equal(not2, masked_hex,
                    f("double negation for %d bits", bits))
            end
        end

        print("\nTesting bnot_hex_str with De Morgan's laws...")

        -- Test De Morgan's laws: NOT(A OR B) = (NOT A) AND (NOT B)
        -- Test De Morgan's laws: NOT(A AND B) = (NOT A) OR (NOT B)
        for bits = 8, 64, 8 do
            for _ = 1, 5 do
                local hex1 = random_hex_str(bits)
                local hex2 = random_hex_str(bits)

                -- NOT(A OR B) = (NOT A) AND (NOT B)
                local or_result = hsb.bor_hex_str(hex1, hex2, bits)
                local not_or = hsb.bnot_hex_str(or_result, bits)

                local not_a = hsb.bnot_hex_str(hex1, bits)
                local not_b = hsb.bnot_hex_str(hex2, bits)
                local not_a_and_not_b = hsb.band_hex_str(not_a, not_b, bits)

                expect.equal(not_or, not_a_and_not_b,
                    f("De Morgan's law 1 for %d bits", bits))

                -- NOT(A AND B) = (NOT A) OR (NOT B)
                local and_result = hsb.band_hex_str(hex1, hex2, bits)
                local not_and = hsb.bnot_hex_str(and_result, bits)

                local not_a_or_not_b = hsb.bor_hex_str(not_a, not_b, bits)

                expect.equal(not_and, not_a_or_not_b,
                    f("De Morgan's law 2 for %d bits", bits))
            end
        end

        print("\nTesting bnot_hex_str with specific bit boundaries (32, 64, 128, 256)...")

        local boundaries = { 32, 64, 128, 256 }
        for _, bits in ipairs(boundaries) do
            local hex_chars = math.ceil(bits / 4)

            -- Test max value -> 0
            local max_val = string.rep("f", hex_chars)
            local result = hsb.bnot_hex_str(max_val, bits)
            expect.equal(result, string.rep("0", hex_chars),
                f("bnot max value for %d bits", bits))

            -- Test 0 -> max value
            result = hsb.bnot_hex_str("0", bits)
            local expected_max
            if bits % 4 == 0 then
                expected_max = string.rep("f", hex_chars)
            else
                local bits_in_msb = bits % 4
                local msb_mask = bit.lshift(1, bits_in_msb) - 1
                local msb_hex = f("%x", msb_mask)
                expected_max = msb_hex .. string.rep("f", hex_chars - 1)
            end
            expect.equal(result, expected_max,
                f("bnot zero for %d bits", bits))

            -- Test MSB set
            local msb_set = "8" .. string.rep("0", hex_chars - 1)
            result = hsb.bnot_hex_str(msb_set, bits)
            -- Expected: flip all bits
            -- For 32-bit 0x80000000 -> 0x7fffffff
        end

        print("\nTesting bnot_hex_str XOR identity: A XOR (NOT A) = all ones...")

        for bits = 4, 64, 4 do
            local hex = random_hex_str(bits)
            local not_hex = hsb.bnot_hex_str(hex, bits)
            local xor_result = hsb.bxor_hex_str(hex, not_hex, bits)

            -- Calculate expected all ones
            local hex_chars = math.ceil(bits / 4)
            local expected_ones
            if bits % 4 == 0 then
                expected_ones = string.rep("f", hex_chars)
            else
                local bits_in_msb = bits % 4
                local msb_mask = bit.lshift(1, bits_in_msb) - 1
                local msb_hex = f("%x", msb_mask)
                expected_ones = msb_hex .. string.rep("f", hex_chars - 1)
            end

            expect.equal(xor_result, expected_ones,
                f("A XOR (NOT A) = all ones for %d bits", bits))
        end

        print("\nTesting bnot_hex_str AND identity: A AND (NOT A) = 0...")

        for bits = 4, 64, 4 do
            local hex = random_hex_str(bits)
            local not_hex = hsb.bnot_hex_str(hex, bits)
            local and_result = hsb.band_hex_str(hex, not_hex, bits)

            local hex_chars = math.ceil(bits / 4)
            local expected_zeros = string.rep("0", hex_chars)

            expect.equal(and_result, expected_zeros,
                f("A AND (NOT A) = 0 for %d bits", bits))
        end

        print("\nTesting bnot_hex_str with bitwidth truncation...")

        -- Test input larger than bitwidth
        local truncation_tests = {
            { "1ff",  8,  "00" },  -- Input 0x1ff truncated to 8 bits (0xff), NOT 0xff = 0x00
            { "ffff", 8,  "00" },  -- Input 0xffff truncated to 8 bits (0xff), NOT 0xff = 0x00
            { "ffff", 12, "000" }, -- Input 0xffff truncated to 12 bits (0xfff), NOT 0xfff = 0x000
            { "1234", 8,  "cb" },  -- Input 0x1234 truncated to 8 bits (0x34), NOT 0x34 = 0xcb
            { "abcd", 12, "432" }, -- Input 0xabcd truncated to 12 bits (0xbcd), NOT 0xbcd = 0x432
        }

        for _, test in ipairs(truncation_tests) do
            local input, bitwidth, expected = test[1], test[2], test[3]
            local result = hsb.bnot_hex_str(input, bitwidth)
            expect.equal(result, expected,
                f("bnot_hex_str(%s, %d) with truncation", input, bitwidth))
        end

        print("\nTesting bnot_hex_str non-multiple of 4 bit widths...")

        -- Test bitwidths that are not multiples of 4
        local non_mult4_tests = {
            { "0",  1, "1" },  -- 1-bit: NOT 0 = 1
            { "1",  1, "0" },  -- 1-bit: NOT 1 = 0
            { "0",  2, "3" },  -- 2-bit: NOT 00 = 11
            { "3",  2, "0" },  -- 2-bit: NOT 11 = 00
            { "0",  3, "7" },  -- 3-bit: NOT 000 = 111
            { "7",  3, "0" },  -- 3-bit: NOT 111 = 000
            { "0",  5, "1f" }, -- 5-bit: NOT 00000 = 11111
            { "1f", 5, "00" }, -- 5-bit: NOT 11111 = 00000
            { "0",  6, "3f" }, -- 6-bit: NOT 000000 = 111111
            { "3f", 6, "00" }, -- 6-bit: NOT 111111 = 000000
            { "0",  7, "7f" }, -- 7-bit: NOT 0000000 = 1111111
            { "7f", 7, "00" }, -- 7-bit: NOT 1111111 = 0000000
            { "a",  3, "5" },  -- 3-bit: input 0xa (1010) masked to 3 bits (010), NOT 010 = 101
            { "f",  3, "0" },  -- 3-bit: input 0xf (1111) masked to 3 bits (111), NOT 111 = 000
        }

        for _, test in ipairs(non_mult4_tests) do
            local input, bitwidth, expected = test[1], test[2], test[3]
            local result = hsb.bnot_hex_str(input, bitwidth)
            expect.equal(result, expected,
                f("bnot_hex_str(%s, %d) non-multiple of 4", input, bitwidth))
        end

        print("\nTesting bnot_hex_str backward compatibility (inferred bitwidth)...")

        -- Test that without bitwidth parameter, result has leading zeros trimmed
        local compat_tests = {
            { "f",        "0" },        -- 4-bit inferred, result trimmed
            { "ff",       "0" },        -- 8-bit inferred, result trimmed
            { "fff",      "0" },        -- 12-bit inferred, result trimmed
            { "ffff",     "0" },        -- 16-bit inferred, result trimmed
            { "12345678", "edcba987" }, -- 32-bit inferred
            { "0",        "f" },        -- 4-bit: NOT 0 = f
            { "00",       "ff" },       -- 8-bit: NOT 00 = ff
        }

        for _, test in ipairs(compat_tests) do
            local input, expected = test[1], test[2]
            local result = hsb.bnot_hex_str(input)
            expect.equal(result, expected,
                f("bnot_hex_str(%s) inferred bitwidth", input))
        end

        print("\nAll bnot_hex_str tests passed!")
    end)

    it("should work properly for set_bitfield_hex_str()", function()
        -- Basic tests
        expect.equal(hsb.set_bitfield_hex_str("0", 0, 3, "f"), "f")
        expect.equal(hsb.set_bitfield_hex_str("0", 4, 7, "f"), "f0")
        expect.equal(hsb.set_bitfield_hex_str("ffff", 4, 7, "0"), "ff0f")
        expect.equal(hsb.set_bitfield_hex_str("ffff", 0, 3, "0"), "fff0")

        -- With width
        expect.equal(hsb.set_bitfield_hex_str("0", 0, 3, "f", 8), "0f")
        expect.equal(hsb.set_bitfield_hex_str("0", 4, 7, "f", 8), "f0")

        -- Auto-expand
        expect.equal(hsb.set_bitfield_hex_str("0", 8, 11, "f"), "f00")

        -- Cross-verification with bitfield64 for 0-64 bits
        print("\nTesting set_bitfield_hex_str with bitfield64 verification (0-64 bits)...")
        for bits = 1, 64 do
            for _ = 1, 5 do
                -- Generate random initial value
                local init_val = utils.urandom64_range(0, utils.bitmask(bits)) --[[@as integer]]
                local init_hex = utils.to_hex_str(init_val)

                -- Generate random range [s, e] within [0, bits-1]
                local s = math.random(0, bits - 1)
                local e = math.random(s, bits - 1)

                -- Generate random value to set
                local width = e - s + 1
                local set_val = utils.urandom64_range(0, utils.bitmask(width))
                local set_hex = utils.to_hex_str(set_val)

                -- Apply set_bitfield_hex_str
                -- We pass 'bits' as width to ensure consistent length
                local result_hex = hsb.set_bitfield_hex_str(init_hex, s, e, set_hex, bits)

                -- Safe hex to uint64_t conversion
                local function hex_to_ull(hex)
                    if #hex > 16 then hex = hex:sub(-16) end -- Truncate to 64 bits
                    local len = #hex
                    if len <= 12 then
                        return (tonumber(hex, 16) or 0) + 0ULL
                    else
                        local split = len - 12
                        local high_str = hex:sub(1, split)
                        local low_str = hex:sub(split + 1)
                        local high = (tonumber(high_str, 16) or 0) + 0ULL
                        local low = (tonumber(low_str, 16) or 0) + 0ULL
                        return bit.lshift(high, 48) + low
                    end
                end

                -- Verify with bitfield64
                -- 1. Check the set bits
                local result_val = hex_to_ull(result_hex) --[[@as integer]]
                local extracted = utils.bitfield64(s, e, result_val)
                expect.equal(extracted, set_val, f("Verification failed for bits=%d, s=%d, e=%d", bits, s, e))

                -- 2. Check other bits are unchanged
                -- We can check bits [0, s-1] and [e+1, bits-1]
                if s > 0 then
                    local low_part_orig = utils.bitfield64(0, s - 1, init_val)
                    local low_part_new = utils.bitfield64(0, s - 1, result_val)
                    expect.equal(low_part_new, low_part_orig, "Low part changed")
                end

                if e < bits - 1 then
                    local high_part_orig = utils.bitfield64(e + 1, bits - 1, init_val)
                    local high_part_new = utils.bitfield64(e + 1, bits - 1, result_val)
                    expect.equal(high_part_new, high_part_orig, "High part changed")
                end
            end
        end

        -- Test cases > 64 bits
        print("\nTesting set_bitfield_hex_str for > 64 bits...")
        local large_bits = 128
        local all_zeros = string.rep("0", large_bits / 4)
        local all_ones = string.rep("f", large_bits / 4)

        -- Set a bitfield in the middle of 128 bits
        -- s=60, e=67 (8 bits), crossing 64-bit boundary
        local result = hsb.set_bitfield_hex_str(all_zeros, 60, 67, "ff", large_bits)
        -- Expected: ...000000f000000000000000...
        -- bit 60-63 (4 bits) = f (lower part of ff) -> index len-60...
        -- bit 64-67 (4 bits) = f (upper part of ff)
        -- 60 is 0x3c. 67 is 0x43.
        -- 1ULL << 60 is 1000...000 (60 zeros) -> hex 1000000000000000
        -- We are setting 8 bits to 1s.
        -- Let's verify by reading back with bitfield_hex_str
        local read_back = hsb.bitfield_hex_str(result, 60, 67, large_bits)
        expect.equal(read_back, "ff")

        -- Verify other bits are 0
        expect.equal(hsb.trim_leading_zeros(hsb.bitfield_hex_str(result, 0, 59, large_bits)), "0")
        expect.equal(hsb.trim_leading_zeros(hsb.bitfield_hex_str(result, 68, 127, large_bits)), "0")

        -- Set bits in all_ones to 0
        result = hsb.set_bitfield_hex_str(all_ones, 100, 103, "0", large_bits)
        read_back = hsb.bitfield_hex_str(result, 100, 103, large_bits)
        expect.equal(read_back, "0")

        -- Verify surrounding bits are still 1 (f)
        expect.equal(hsb.bitfield_hex_str(result, 96, 99, large_bits), "f")
        expect.equal(hsb.bitfield_hex_str(result, 104, 107, large_bits), "f")

        -- Test 256 bits
        local huge_bits = 256
        local huge_zeros = string.rep("0", huge_bits / 4)
        result = hsb.set_bitfield_hex_str(huge_zeros, 250, 255, "3f", huge_bits)
        read_back = hsb.bitfield_hex_str(result, 250, 255, huge_bits)
        expect.equal(read_back, "3f")

        print("set_bitfield_hex_str tests passed!")
    end)
end)

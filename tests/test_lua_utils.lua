---@diagnostic disable: unnecessary-assert

local ffi = require "ffi"
local inspect = require "inspect"
local lester = require "lester"
local utils = require "verilua.LuaUtils"

local describe, it, expect = lester.describe, lester.it, lester.expect
local assert, f = assert, string.format

ffi.cdef [[
    int setenv(const char *name, const char *value, int overwrite);
    int unsetenv(const char *name);
]]

describe("LuaUtils test", function()
    it("should deep copy tables with cycles and metatables", function()
        local mt = { name = "meta" }
        local key = { id = "key" }
        local src = setmetatable({ nested = { value = 1 } }, mt)
        src[key] = { value = 2 }
        src.self = src

        local copied = utils.deepcopy(src)

        assert(copied ~= src)
        assert(getmetatable(copied) == mt)
        assert(copied.nested ~= src.nested)
        expect.equal(copied.nested.value, 1)
        assert(copied.self == copied)

        local copied_key = nil
        for k, v in pairs(copied) do
            if type(k) == "table" and k.id == "key" then
                copied_key = k
                expect.equal(v.value, 2)
            end
        end
        assert(copied_key ~= nil)
        assert(copied_key ~= key)
    end)

    it("should get environment values or generated defaults", function()
        ffi.C.unsetenv("VL_TEST_GENERATED_NUMBER")
        local calls = 0
        local generated = utils.get_env_or_else("VL_TEST_GENERATED_NUMBER", "number", function()
            calls = calls + 1
            return 12.5
        end)
        expect.equal(generated, 12.5)
        expect.equal(calls, 1)

        ffi.C.setenv("VL_TEST_GENERATED_NUMBER", "42", 1)
        local from_env = utils.get_env_or_else("VL_TEST_GENERATED_NUMBER", "number", function()
            assert(false, "default generator should not be called when env is set")
        end)
        expect.equal(from_env, 42)
        ffi.C.unsetenv("VL_TEST_GENERATED_NUMBER")
    end)

    it("should validate integer environment values and generated defaults", function()
        ffi.C.unsetenv("VL_TEST_GENERATED_INTEGER")
        expect.equal(utils.get_env_or_else("VL_TEST_GENERATED_INTEGER", "integer", function()
            return 7
        end), 7)

        ffi.C.setenv("VL_TEST_GENERATED_INTEGER", "11", 1)
        expect.equal(utils.get_env_or_else("VL_TEST_GENERATED_INTEGER", "integer", 0), 11)
        ffi.C.setenv("VL_TEST_GENERATED_INTEGER", "11.5", 1)
        local ok, err = pcall(function()
            local _ = utils.get_env_or_else("VL_TEST_GENERATED_INTEGER", "integer", 0)
        end)
        assert(not ok)
        local err_msg = tostring(err)
        assert(err_msg:find("environment value type mismatch", 1, true), err_msg)
        assert(err_msg:find("key=VL_TEST_GENERATED_INTEGER", 1, true), err_msg)
        assert(err_msg:find("expected=integer", 1, true), err_msg)
        assert(err_msg:find("value=11.5", 1, true), err_msg)
        assert(err_msg:find("actual=number", 1, true), err_msg)
        ffi.C.unsetenv("VL_TEST_GENERATED_INTEGER")

        ok, err = pcall(function()
            local _ = utils.get_env_or_else("VL_TEST_GENERATED_INTEGER", "integer", function()
                return 1.5
            end)
        end)
        assert(not ok)
        err_msg = tostring(err)
        assert(err_msg:find("generated default value type mismatch", 1, true), err_msg)
        assert(err_msg:find("key=VL_TEST_GENERATED_INTEGER", 1, true), err_msg)
        assert(err_msg:find("expected=integer", 1, true), err_msg)
        assert(err_msg:find("value=1.5", 1, true), err_msg)
        assert(err_msg:find("actual=number", 1, true), err_msg)
    end)

    it("should provide random helpers", function()
        for _ = 1, 100 do
            local v = utils.rand_int(3, 5)
            assert(v >= 3 and v <= 5)
            assert(v == math.floor(v))
        end

        local ok, err = pcall(function()
            local _ = utils.rand_int(5, 3)
        end)
        assert(not ok)
        local err_msg = tostring(err)
        assert(err_msg:find("[utils.rand_int] min must be <= max", 1, true), err_msg)

        expect.equal(utils.rand_bool(1), true)
        expect.equal(utils.rand_bool(0), false)
        assert(type(utils.rand_bool()) == "boolean")
        assert(type(utils.rand_bool(0.5)) == "boolean")
        ok, err = pcall(function()
            local _ = utils.rand_bool(false --[[@as any]])
        end)
        assert(not ok)
        err_msg = tostring(err)
        assert(err_msg:find("[utils.rand_bool] true_probability must be a number", 1, true), err_msg)

        local choices = { "a", "b", "c" }
        for _ = 1, 100 do
            local v = utils.rand_choice(choices)
            assert(v == "a" or v == "b" or v == "c")
        end

        for _ = 1, 100 do
            expect.equal(utils.rand_choice(choices, { 0, 1, 0 }), "b")
        end

        ok, err = pcall(function()
            local _ = utils.rand_choice({})
        end)
        assert(not ok)
        err_msg = tostring(err)
        assert(err_msg:find("[utils.rand_choice] choices must be a non-empty array", 1, true), err_msg)

        ok, err = pcall(function()
            local _ = utils.rand_choice(choices, {})
        end)
        assert(not ok)
        err_msg = tostring(err)
        assert(err_msg:find("[utils.rand_choice] weights length must match choices length", 1, true), err_msg)

        ok, err = pcall(function()
            local _ = utils.rand_choice(choices, { 1, -1, 1 })
        end)
        assert(not ok)
        err_msg = tostring(err)
        assert(err_msg:find("[utils.rand_choice] weight must be a non-negative number", 1, true), err_msg)

        ok, err = pcall(function()
            local _ = utils.rand_choice(choices, { 0, 0, 0 })
        end)
        assert(not ok)
        err_msg = tostring(err)
        assert(err_msg:find("[utils.rand_choice] total weight must be > 0", 1, true), err_msg)
    end)

    it("should work for bitfield32() and bitfiled64()", function()
        local tests = {
            { 0xffffffff, 0,  1,  3 },
            { 0xffffffff, 0,  3,  15 },
            { 0xffffffff, 0,  4,  31 },
            { 0xffffffff, 0,  7,  255 },
            { 0xffffffff, 0,  15, 65535 },
            { 0xffffffff, 16, 31, 65535 },
            { 0xffffffff, 0,  31, 2 ^ 32 - 1 },
        }
        for _, test in ipairs(tests) do
            local result = utils.bitfield32(test[2], test[3], test[1])
            assert(type(result) == "number", type(result))
            assert(result == test[4], tostring(result) .. " " .. tostring(test[4]))
        end

        for _, test in ipairs(tests) do
            local result = utils.bitfield64(test[2] --[[@as integer]], test[3] --[[@as integer]], test[1] --[[@as integer]])
            assert(type(result) == "cdata", type(result))
            assert(result == test[4], tostring(result) .. " " .. tostring(test[4]))
        end

        local cdata_tests = {
            { 0xffffffffffffffffULL, 0,  1,  3 },
            { 0xffffffffffffffffULL, 0,  3,  15 },
            { 0xffffffffffffffffULL, 0,  4,  31 },
            { 0xffffffffffffffffULL, 0,  7,  255 },
            { 0xffffffffffffffffULL, 0,  15, 65535 },
            { 0xffffffffffffffffULL, 16, 31, 65535 },
            { 0xffffffffffffffffULL, 0,  31, 2 ^ 32 - 1 },
            { 0xffffffffffffffffULL, 0,  63, 0xffffffffffffffffULL },
            { 0xffffffffffffffffULL, 62, 63, 3 },
            { 0xffffffffffffffffULL, 63, 63, 1 },
        }

        for _, test in ipairs(cdata_tests) do
            local result = utils.bitfield64(test[2] --[[@as integer]], test[3] --[[@as integer]], test[1] --[[@as integer]])
            assert(type(result) == "cdata", type(result))
            assert(result == test[4], tostring(result) .. " " .. tostring(test[4]))
        end
    end)

    it("should work properly for bitfield_str()", function()
        expect.equal(utils.bitfield_str("0000322", 8, 9, 10), "01")
        expect.equal(utils.bitfield_str("322", 0, 8), "101000010")
        expect.equal(utils.bitfield_str("322", 0, 9, 10), "0101000010")
        expect.equal(utils.bitfield_str("0x123", 0, 2), "011")
        expect.equal(utils.bitfield_str("0b0101", 0, 3), "0101")        -- get: 0101
        expect.equal(utils.bitfield_str("0b01  01", 0, 3), "0101")      -- get: 0101
        expect.equal(tonumber(utils.bitfield_str("123", 0, 6), 2), 123) -- get: 123
        expect.equal(tonumber(utils.bitfield_str("0x1000004", 0, 15), 2), 4)
        expect.equal(
            utils.bitfield_str("0x12345678_12345678 12345678 12345678 12345678 12345678 12345678 12345678", 0, 4),
            "11000")
        expect.equal(utils.bitfield_str("0xff", 7, 7), "1")
        expect.equal(utils.bitfield_str("0x8000000000000000", 63, 63), "1")
    end)

    it("should work properly for bitpat_to_hexstr()", function()
        assert(utils.bitpat_to_hex_str({
            { s = 0,  e = 1,  v = 2 },
            { s = 4,  e = 7,  v = 4 },
            { s = 63, e = 63, v = 1 }
        }, 64) == "8000000000000042")

        assert(utils.bitpat_to_hex_str({
            { s = 0,   e = 1,   v = 2 },
            { s = 4,   e = 7,   v = 4 },
            { s = 127, e = 127, v = 1 }
        }, 128) == "80000000000000000000000000000042")

        assert(utils.bitpat_to_hex_str({
            { s = 0,   e = 1,   v = 2 },
            { s = 4,   e = 7,   v = 4 },
            { s = 255, e = 255, v = 1 }
        }, 256) == "8000000000000000000000000000000000000000000000000000000000000042")

        assert(utils.bitpat_to_hex_str({
            { s = 0,   e = 1,   v = 2 },
            { s = 4,   e = 7,   v = 4 },
            { s = 109, e = 109, v = 1 }
        }, 110) == "00002000000000000000000000000042")

        assert(utils.bitpat_to_hex_str({
            { s = 0,  e = 1,   v = 2 },
            { s = 4,  e = 7,   v = 4 },
            { s = 65, e = 127, v = 0x11231 }
        }, 128) == "00000000000224620000000000000042")

        assert(utils.bitpat_to_hex_str({
                { s = 0, e = 63, v = 0xdead }
            }, 512) ==
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dead")

        assert(utils.bitpat_to_hex_str({
                { s = 0,   e = 63,       v = 0xdead },
                { s = 256, e = 255 + 63, v = 0xbeef },
            }, 512) ==
            "000000000000000000000000000000000000000000000000000000000000beef000000000000000000000000000000000000000000000000000000000000dead")

        assert(utils.bitpat_to_hex_str({
            { s = 16, e = 51, v = 0x600000000ULL },
            { s = 0,  e = 15, v = 0xdead }
        }, 64) == "000600000000dead")
    end)

    it("should work properly for urandom64() and urandom64_range()", function()
        local success = false
        for _ = 1, 10000 do
            local v = utils.urandom64()
            assert(type(v) == "cdata")
            if v >= 0xFFFFFFFULL then
                success = true
            end
        end
        assert(success)

        local tests = {
            { MIN = 0xFFFF,        MAX = 0xFFFFF },
            { MIN = 0xFFFFFFFFULL, MAX = 0xFFFFFFFFFULL },
            { MIN = 0,             MAX = 0xFFFFFFFFFFFFFFFFULL }
        }
        for _, v in ipairs(tests) do
            local MIN = v.MIN
            local MAX = v.MAX

            local random_count = 0
            ---@type table<string, uint64_t>
            local random_count_tbl = {}
            for _ = 1, 10000 do
                local vv = utils.urandom64_range(MIN --[[@as integer|uint64_t]], MAX --[[@as integer|uint64_t]])
                ---@diagnostic disable-next-line: duplicate-set-field
                random_count_tbl[utils.to_hex_str(vv)] = vv
                assert(type(vv) == "cdata")
                if vv > MAX or vv < MIN then
                    assert(false)
                end
            end

            for _, _ in pairs(random_count_tbl) do
                random_count = random_count + 1
            end
            assert(random_count > 100,
                f("MIN: %s, MAX: %s, random_count: %d, random_count_tbl: %s", utils.to_hex_str(MIN --[[@as integer|ffi.cdata*]]),
                    utils.to_hex_str(MAX --[[@as integer|ffi.cdata*]]), random_count, (inspect --[[@as fun(value: any, options?: table): string]])(random_count_tbl)))
        end
    end)

    it("should work properly for urandom64_range() with edge cases (overflow test)", function()
        -- Test edge cases that can cause overflow:
        -- 1. When max - min + 1 == 2^64 (full range), should not cause division by zero
        -- 2. When max is near the max uint64 value

        local edge_tests = {
            -- Test near max boundary: max - min + 1 should not overflow
            { MIN = 0,                         MAX = 0xFFFFFFFFFFFFFFFFULL },
            { MIN = 1,                         MAX = 0xFFFFFFFFFFFFFFFFULL },
            { MIN = 0xFFFFFFFFFFFFFFFEULL,     MAX = 0xFFFFFFFFFFFFFFFFULL },
            { MIN = 0xFFFFFFFFFFFFFF00ULL,     MAX = 0xFFFFFFFFFFFFFFFFULL },
            { MIN = 0x8000000000000000ULL,     MAX = 0xFFFFFFFFFFFFFFFFULL },
            -- Test when min == max (range of 1)
            { MIN = 0xFFFFFFFFFFFFFFFFULL,     MAX = 0xFFFFFFFFFFFFFFFFULL },
            { MIN = 0,                         MAX = 0 },
            { MIN = 12345ULL,                  MAX = 12345ULL },
        }

        for _, v in ipairs(edge_tests) do
            local MIN = v.MIN
            local MAX = v.MAX

            for _ = 1, 1000 do
                local result = utils.urandom64_range(MIN --[[@as integer|uint64_t]], MAX --[[@as integer|uint64_t]])
                assert(type(result) == "cdata",
                    f("Expected cdata, got %s for MIN=%s, MAX=%s", type(result),
                        utils.to_hex_str(MIN --[[@as integer|ffi.cdata*]]), utils.to_hex_str(MAX --[[@as integer|ffi.cdata*]])))
                assert(result >= MIN,
                    f("Result %s should >= MIN %s", utils.to_hex_str(result), utils.to_hex_str(MIN --[[@as integer|ffi.cdata*]])))
                assert(result <= MAX,
                    f("Result %s should <= MAX %s", utils.to_hex_str(result), utils.to_hex_str(MAX --[[@as integer|ffi.cdata*]])))
            end
        end

        -- Test min == max returns exactly that value
        for _ = 1, 100 do
            local v = utils.urandom64_range(0xABCDEF123456ULL, 0xABCDEF123456ULL)
            assert(v == 0xABCDEF123456ULL,
                f("Expected 0xABCDEF123456, got %s", utils.to_hex_str(v)))
        end
    end)

    it("should work properly for str_group_by() and str_sep()", function()
        local tests = {
            { "1234567890", 3, { "123", "456", "789", "0" } },
            { "1234567890", 4, { "1234", "5678", "90" } },
            { "1234567890", 5, { "12345", "67890" } },
            { "1234567890", 6, { "123456", "7890" } },
            { "1234567890", 7, { "1234567", "890" } },
        }
        for _, test in ipairs(tests) do
            local str = test[1]
            local nr_group = test[2]
            local result = test[3]
            expect.equal(utils.str_group_by(str, nr_group), result)
        end

        local sep_tests = {
            { "1234567890", 3, "123,456,789,0", "," },
            { "1234567890", 4, "1234,5678,90",  "," },
            { "1234567890", 5, "12345,67890",   "," },
            { "1234567890", 6, "123456,7890",   "," },
            { "1234567890", 7, "1234567,890",   "," },
        }
        for _, test in ipairs(sep_tests) do
            local str = test[1]
            local nr_group = test[2]
            local result = test[3]
            local separator = test[4]
            expect.equal(utils.str_sep(str, nr_group, separator), result)
        end
    end)

    it("should work properly for bitmask()", function()
        local tests = {
            { n = 0,  expected = 0 },
            { n = 1,  expected = 1 },
            { n = 2,  expected = 3 },
            { n = 4,  expected = 15 },
            { n = 8,  expected = 255 },
            { n = 16, expected = 65535 },
            { n = 32, expected = 0xFFFFFFFFULL },
            { n = 33, expected = 0x1FFFFFFFFULL },
            { n = 40, expected = 0xFFFFFFFFFFULL },
            { n = 48, expected = 0xFFFFFFFFFFFFULL },
            { n = 56, expected = 0xFFFFFFFFFFFFFFULL },
            { n = 64, expected = 0xFFFFFFFFFFFFFFFFULL }
        }

        for _, test in ipairs(tests) do
            local n = test.n
            local expected = test.expected
            local result = utils.bitmask(n)
            expect.equal(result, expected + 0ULL)
        end
    end)

    it("should work properly for to_hex_str()", function()
        local tests = {
            { 0x1234,                                                  "1234" },
            { 0x12345678,                                              "12345678" },
            { 0xFFFFFFFF,                                              "ffffffff" },
            { 0xFFFFFFFFFULL,                                          "0000000fffffffff" },
            { 0xFFFFFFFFFFFFFFFFULL,                                   "ffffffffffffffff" },
            { 0x1234567890123456ULL,                                   "1234567890123456" },
            { { 0x1234, 0x2445 },                                      "0000244500001234" },
            { { 0x1234, 0x2445 },                                      "00002445 00001234",         " " },
            { { 0x1234, 0x2445 },                                      "00002445_00001234",         "_" },
            { { 0x1234, 0x2445ULL },                                   "000000000000244500001234" },
            { { 0x1234, 0x2445ULL },                                   "0000000000002445_00001234", "_" },
            { { 0x1234, 0x2445, 0x244 },                               "000002440000244500001234" },
            { ffi.new("uint32_t[?]", 4, { 3, 0x1234, 0x2445, 0x244 }), "000002440000244500001234" },
        }

        for _, test in ipairs(tests) do
            local v = test[1]
            local expected = test[2]
            local separator = test[3]
            local result = utils.to_hex_str(v --[[@as integer|ffi.cdata*|table]], separator)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for reset_bits()", function()
        local tests = {
            { 0xFFFF,                0,  4,  0xFFF0 },
            { 0xFFFFFFFFFFFFFFFFULL, 0,  8,  0xFFFFFFFFFFFFFF00ULL },
            { 0xFFFFFFFFFFFFFFFFULL, 8,  8,  0xFFFFFFFFFFFF00FFULL },
            { 0xFFFFFFFFFFFFFFFFULL, 16, 16, 0xFFFFFFFF0000FFFFULL },
            { 0xFFFFFFFFFFFFFFFFULL, 32, 32, 0x00000000FFFFFFFFULL },
            { 0xFFFFFFFFFFFFFFFFULL, 0,  64, 0x0000000000000000ULL },
            { 0x123456789ABCDEF0ULL, 4,  8,  0x123456789ABCD000ULL },
            { 0x123456789ABCDEF0ULL, 16, 16, 0x123456780000DEF0ULL },
            { 0x123456789ABCDEF0ULL, 32, 32, 0x000000009ABCDEF0ULL },
            { 0x123456789ABCDEF0ULL, 48, 16, 0x000056789ABCDEF0ULL },
            { 0x123456789ABCDEF0ULL, 60, 4,  0x023456789ABCDEF0ULL },
        }

        for _, test in ipairs(tests) do
            local value = test[1]
            local start = test[2]
            local length = test[3]
            local expected = test[4]
            local result = utils.reset_bits(value --[[@as integer]], start --[[@as integer]], length --[[@as integer]])
            expect.equal(result, expected + 0ULL)
        end
    end)

    it("should work properly for cover_with_n()", function()
        local tests = {
            { 128, 32, 4 },
            { 127, 32, 4 },
            { 96,  32, 3 },
            { 31,  32, 1 },
            { 0,   32, 0 },
            { 15,  3,  5 },
            { 14,  3,  5 },
        }
        for _, test in ipairs(tests) do
            local value = test[1]
            local n = test[2]
            local expected = test[3]
            local result = utils.cover_with_n(value, n)
            expect.equal(result + 0ULL, expected + 0ULL)
        end
    end)

    it("should work properly for shuffle_bits_hex_str()", function()
        local test_shuffle_bits_hex_str = function(width, iter)
            local count = iter or 100
            local tbl = {}
            for _ = 1, count do
                local ret = utils.shuffle_bits_hex_str(width)
                expect.equal(utils.bitfield_str("0x" .. ret, width, width), "0")
                for j = 1, width do
                    local v = utils.bitfield_str("0x" .. ret, j - 1, j - 1)
                    if v == "1" and tbl[j] == nil then
                        tbl[j] = j
                        break
                    end
                end
            end
            return #tbl
        end

        for i = 1, 70 do
            expect.equal(test_shuffle_bits_hex_str(i), i)
        end

        local test_shuffle_bits = function(width, iter)
            local count = iter or 100
            local tbl = {}
            for _ = 1, count do
                local ret = utils.shuffle_bits(width)
                for j = 1, width do
                    local v = utils.bitfield_str("0x" .. utils.to_hex_str(ret), j - 1, j - 1, width)
                    if v == "1" and tbl[j] == nil then
                        tbl[j] = j
                        break
                    end
                end
            end
            return #tbl
        end

        for i = 1, 64 do
            expect.equal(test_shuffle_bits(i), i)
        end
    end)

    it("should work properly for expand_hex_str()", function()
        local tests = {
            { "1234", 8,   "1234" },
            { "1234", 16,  "1234" },
            { "1234", 17,  "01234" },
            { "1234", 32,  "00001234" },
            { "1234", 33,  "000001234" },
            { "1234", 48,  "000000001234" },
            { "1234", 64,  "0000000000001234" },
            { "1234", 256, "0000000000000000000000000000000000000000000000000000000000001234" },
        }

        for _, test in ipairs(tests) do
            local hex_str = test[1]
            local width = test[2]
            local expected = test[3]
            ---@diagnostic disable-next-line
            local result = utils.expand_hex_str(hex_str, width)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for hex_to_bin()", function()
        local tests = {
            { "0",      "0000" },
            { "F",      "1111" },
            { "A",      "1010" },
            { "a",      "1010" },
            { "1F",     "00011111" },
            { "FF",     "11111111" },
            { "1234",   "0001001000110100" },
            { "ABCD",   "1010101111001101" },
            { "abcd",   "1010101111001101" },
            { "1a2b3c", "000110100010101100111100" },
        }

        for _, test in ipairs(tests) do
            local hex_str = test[1]
            local expected = test[2]
            local result = utils.hex_to_bin(hex_str)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for bin_str_to_hex_str", function()
        local tests = {
            { "0",            "0" },
            { "1",            "1" },
            { "10",           "2" },
            { "010",          "2" },
            { "1000",         "8" },
            { "1111",         "f" },
            { "10000100",     "84" },
            { "000000000010", "002" },
        }
        for _, test in ipairs(tests) do
            local bin_str = test[1]
            local expected = test[2]
            local result = utils.bin_str_to_hex_str(bin_str)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for hex_str_to_ull()", function()
        local tests = {
            -- Basic cases
            { "0",                      0ULL },
            { "1",                      1ULL },
            { "f",                      15ULL },
            { "F",                      15ULL },
            { "10",                     16ULL },
            { "ff",                     255ULL },
            { "FF",                     255ULL },
            { "100",                    256ULL },
            { "1234",                   0x1234ULL },
            { "ABCD",                   0xABCDULL },
            { "abcd",                   0xabcdULL },

            -- 32-bit values
            { "ffffffff",               0xFFFFFFFFULL },
            { "FFFFFFFF",               0xFFFFFFFFULL },
            { "12345678",               0x12345678ULL },

            -- 64-bit values
            { "ffffffffffffffff",       0xFFFFFFFFFFFFFFFFULL },
            { "FFFFFFFFFFFFFFFF",       0xFFFFFFFFFFFFFFFFULL },
            { "1234567890abcdef",       0x1234567890abcdefULL },
            { "1234567890ABCDEF",       0x1234567890ABCDEFULL },
            { "8000000000000000",       0x8000000000000000ULL },
            { "7fffffffffffffff",       0x7fffffffffffffffULL },

            -- Edge cases - should truncate to 64 bits (last 16 hex chars)
            { "123456789abcdef0123456", 0x789abcdef0123456ULL }, -- Takes last 16 chars: 789abcdef0123456
            { "00000000000000001234",   0x1234ULL },

            -- Leading zeros
            { "00000001",               1ULL },
            { "0000ffff",               0xffffULL },
        }

        for _, test in ipairs(tests) do
            local hex_str = test[1]
            local expected = test[2]
            local result = utils.hex_str_to_ull(hex_str)
            expect.equal(result, expected)
        end
    end)

    it("should work properly for hex_str_to_ll()", function()
        local tests = {
            -- Positive values (MSB = 0)
            { "0",                      0LL },
            { "1",                      1LL },
            { "f",                      15LL },
            { "F",                      15LL },
            { "7f",                     127LL },
            { "7fff",                   32767LL },
            { "7fffffff",               0x7fffffffLL },
            { "7fffffffffffffff",       0x7fffffffffffffffLL },

            -- Negative values (MSB = 1, two's complement)
            { "8000000000000000",       ffi.cast("int64_t", 0x8000000000000000ULL) }, -- Most negative: -2^63
            { "ffffffffffffffff",       -1LL },
            { "fffffffffffffffe",       -2LL },
            { "fffffffffffffff0",       -16LL },
            { "ffffffffffffff00",       -256LL },
            { "ffffffffff000000",       ffi.cast("int64_t", 0xffffffffff000000ULL) },
            { "ff00000000000000",       ffi.cast("int64_t", 0xff00000000000000ULL) },
            { "8000000000000001",       ffi.cast("int64_t", 0x8000000000000001ULL) }, -- -2^63 + 1

            -- Mid-range values
            { "1234567890abcdef",       ffi.cast("int64_t", 0x1234567890abcdefULL) },
            { "fedcba9876543210",       ffi.cast("int64_t", 0xfedcba9876543210ULL) },

            -- Edge case around sign bit
            { "7ffffffffffffffe",       0x7ffffffffffffffeLL },
            { "7fffffffffffffff",       0x7fffffffffffffffLL },

            -- Truncation test (should take last 16 hex chars)
            { "123456789abcdef0123456", ffi.cast("int64_t", 0x789abcdef0123456ULL) },
        }

        for _, test in ipairs(tests) do
            local hex_str = test[1]
            local expected = test[2]
            local result = utils.hex_str_to_ll(hex_str)

            -- Compare as int64_t to handle negative values correctly
            local result_i64 = ffi.cast("int64_t", result)
            local expected_i64 = ffi.cast("int64_t", expected)

            expect.equal(result_i64, expected_i64)
        end
    end)

    it("should work properly for compare_hex_str()", function()
        -- Test the bug fix: ensure only leading zeros are removed, not all zeros
        local tests = {
            -- Different values should not be equal
            { "10", "01",    false, "0x10 (16) should not equal 0x01 (1)" },
            { "101", "11",   false, "0x101 (257) should not equal 0x11 (17)" },
            { "10001", "11", false, "0x10001 (65537) should not equal 0x11 (17)" },
            { "10", "00",    false, "0x10 (16) should not equal 0x00 (0)" },

            -- Same values should be equal (case insensitive)
            { "1a", "01a",   true, "0x1A (26) should equal 0x01a (26)" },
            { "ABC", "abc",   true, "0xABC should equal 0xabc (case insensitive)" },
            { "1234", "1234", true, "Same values should be equal" },

            -- Leading zeros should be ignored
            { "1", "001",     true, "0x1 should equal 0x001" },
            { "00a", "a",     true, "0x00a should equal 0xa" },

            -- Different hex values should not be equal
            { "ff", "fe",     false, "0xff (255) should not equal 0xfe (254)" },
            { "0", "1",       false, "0x0 should not equal 0x1" },
        }

        for _, test in ipairs(tests) do
            local str1 = test[1]
            local str2 = test[2]
            local expected = test[3]
            local result = utils.compare_hex_str(str1, str2)
            expect.equal(result, expected)
        end
    end)

    it("should work for get_scriptdir()", function()
        local dir = utils.get_scriptdir()
        -- This test file lives in <repo>/tests, so get_scriptdir() should return that directory
        ---@diagnostic disable-next-line: unresolved-require
        local path = require "pl.path"
        local expected = path.dirname(path.abspath(arg[0]))
        expect.equal(dir, expected)
    end)

    it("should produce correct 64-bit one-hot values for uint_to_onehot()", function()
        -- bit.lshift on a plain number is 32-bit signed; one-hot must use uint64 shift.
        local bit = require "bit"
        for i = 0, 63 do
            local got = utils.uint_to_onehot(i)
            local expected = bit.lshift(1ULL, i)
            assert(got == expected, f(
                "uint_to_onehot(%d): got %s, expected %s",
                i, tostring(got), tostring(expected)
            ))
        end
    end)

    it("should combine hi/lo halves into a 64-bit value for to64bit()", function()
        -- bit.lshift on plain numbers is 32-bit; hi must be promoted before << 32.
        local bit = require "bit"
        local cases = {
            { 1, 2 },
            { 0, 0xFFFFFFFF },
            { 1, 0 },
            { 0xAABBCCDD, 0x11223344 },
            { 0x80000000, 0 },
        }
        for _, c in ipairs(cases) do
            local hi, lo = c[1], c[2]
            local got = utils.to64bit(hi, lo)
            local expected = bit.lshift(hi + 0ULL, 32) + bit.band(lo + 0ULL, 0xFFFFFFFFULL)
            assert(type(got) == "cdata", f("to64bit(%s,%s) type=%s", hi, lo, type(got)))
            assert(got == expected, f(
                "to64bit(%s, %s): got %s, expected %s",
                hi, lo, tostring(got), tostring(expected)
            ))
        end
    end)

    it("should honor execute_after times including times=0", function()
        local function fire_count(opts, calls)
            local n = 0
            local f = utils.execute_after(1, function()
                n = n + 1
            end, opts)
            for _ = 1, calls do
                f()
            end
            return n
        end

        expect.equal(fire_count(nil, 10), 1)
        expect.equal(fire_count({ times = 1 }, 10), 1)
        expect.equal(fire_count({ times = 2 }, 10), 2)
        -- times=0 must not be treated as "unset" (0 is falsy in Lua).
        expect.equal(fire_count({ times = 0 }, 10), 0)
    end)

    it("should report clean enum_search errors without requiring t.name", function()
        expect.equal(utils.enum_search({ RUN = 1, STOP = 2 }, 1), "RUN")

        local ok1, err1 = pcall(function()
            utils.enum_search({ name = "State", RUN = 1 }, 99)
        end)
        assert(not ok1)
        assert(tostring(err1):find("Key not found", 1, true))

        local ok2, err2 = pcall(function()
            utils.enum_search({ RUN = 1, STOP = 2 }, 99)
        end)
        assert(not ok2)
        local msg = tostring(err2)
        assert(msg:find("Key not found", 1, true), msg)
        assert(not msg:find("attempt to concatenate field 'name'", 1, true), msg)
    end)
end)

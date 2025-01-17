local ffi = require "ffi"
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
            {MIN = 0xFFFFFFFFULL, MAX = 0xFFFFFFFFFULL}
        }
        for i, v in ipairs(tests) do
            local MIN = v.MIN
            local MAX = v.MAX
            for i = 1, 10000 do
                local v = utils.urandom64_range(MIN, MAX)
                assert(type(v) == "cdata")
                if v > MAX or v < MIN then
                    assert(false)
                end
            end
        end
    end)

end)
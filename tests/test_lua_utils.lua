local ffi = require "ffi"
local lester = require "lester"
local utils = require "LuaUtils"

local describe, it, expect = lester.describe, lester.it, lester.expect
local assert, print, f = assert, print, string.format

describe("LuaUtils test", function ()
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
    end)

end)
local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect

local WeightedRandom = require "WeightedRandom"
local assert, print, format = assert, print, string.format

lester.parse_args()

describe("WeightRandom test", function ()
    it("should work properly", function()
        local rand = WeightedRandom({
            {10, 0, 100},
            {20, 101, 200},
            {70, 201, 300}
        })

        local cnt_10 = 0
        local cnt_20 = 0
        local cnt_70 = 0

        for i = 1, 10000 do
            local v = rand:gen()
            assert(v ~= nil)

            -- print("[" .. i .. "]", v)

            if (v >= 0) and (v <= 100) then
                cnt_10 = cnt_10 + 1
            elseif (v >= 101) and (v <= 200) then
                cnt_20 = cnt_20 + 1
            elseif (v >= 201) and (v <= 300) then
                cnt_70 = cnt_70 + 1
            else
                assert(false, v)
            end
        end
        
        local cnt_total = cnt_10 + cnt_20 + cnt_70
        local cnt_10_freq = (cnt_10 / cnt_total) * 100
        local cnt_20_freq = (cnt_20 / cnt_total) * 100
        local cnt_70_freq = (cnt_70 / cnt_total) * 100
        -- print(format("10: %.2f  20: %.2f  70: %.2f", cnt_10_freq, cnt_20_freq, cnt_70_freq))

        assert(cnt_10_freq >= 5  and cnt_10_freq <= 15)
        assert(cnt_20_freq >= 15 and cnt_20_freq <= 25)
        assert(cnt_70_freq >= 65 and cnt_10_freq <= 75)
      end)
end)


local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect
local assert, print, format = assert, print, string.format

local CyclicRandom = require "CyclicRandom"

lester.parse_args()

describe("CyclicRandom test", function ()
    it("should work properly", function()
        local rand = CyclicRandom(1, 5)

        assert(rand.size == 5)

        local is_5 = 0
        local is_4 = 0
        local is_3 = 0
        local is_2 = 0
        local is_1 = 0
        for i = 1, rand.size * 2 do
            local v = rand:gen(0)
            -- print(v)
            assert(v ~= nil)
            assert(v >= 1 and v <= 5)
            if v == 5 then
                is_5 = is_5 + 1
            elseif v == 4 then
                is_4 = is_4 + 1
            elseif v == 3 then
                is_3 = is_3 + 1
            elseif v == 2 then
                is_2 = is_2 + 1
            elseif v == 1 then
                is_1 = is_1 + 1
            end
        end

        assert(is_5 == 2 and is_4 == 2 and is_3 == 2 and is_2 == 2 and is_1 == 2)



        local rand = CyclicRandom(3, 5)

        assert(rand.size == 3)

        local is_5 = 0
        local is_4 = 0
        local is_3 = 0
        local is_2 = 0
        local is_1 = 0

        -- print("-------------------")
        for i = 1, rand.size do
            local v = rand:gen(0)
            -- print(v)
            assert(v ~= nil)
            assert(v >= 3 and v <= 5)

            if v == 5 then
                is_5 = is_5 + 1
            elseif v == 4 then
                is_4 = is_4 + 1
            elseif v == 3 then
                is_3 = is_3 + 1
            end
        end

        assert(is_5 == 1)
        assert(is_4 == 1)
        assert(is_3 == 1)
        assert(is_2 == 0)
        assert(is_1 == 0)
    end)
end)
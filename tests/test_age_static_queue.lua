---@diagnostic disable: invisible

local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect

local AgeStaticQueue = require "AgeStaticQueue"

lester.parse_args()

describe("AgeStaticQueue test", function()
    it("should work properly for basic operations", function()
        local q = AgeStaticQueue(4)

        expect.truthy(q:is_empty())
        expect.fail(function() q:pop() end)

        assert(q:push(11) == 0)
        assert(q:push(22) == 0)

        expect.equal(q.count, 2)

        assert(q:push(33) == 0)
        assert(q:push(44) == 0)

        assert(q:push(55) == 1)

        expect.equal(q.count, 4)
        expect.truthy(q:is_full())

        expect.equal(q:pop(), 11)
        expect.equal(q:pop(), 22)
        expect.equal(q:pop(), 33)
        expect.equal(q:pop(), 44)
        expect.fail(function() q:pop() end)
    end)

    it("should work properly for front and last", function()
        local q = AgeStaticQueue(4)

        assert(q:push(11) == 0)
        assert(q:push(22) == 0)
        assert(q:push(33) == 0)

        expect.equal(q:front(), 11)
        expect.equal(q:last(), 33)

        q:pop()
        expect.equal(q:front(), 22)
        expect.equal(q:last(), 33)
    end)

    it("should work properly for reset", function()
        local q = AgeStaticQueue(4)

        assert(q:push(11) == 0)
        assert(q:push(22) == 0)
        assert(q:push(33) == 0)

        expect.equal(q.count, 3)

        q:reset()

        expect.equal(q.count, 0)
        expect.truthy(q:is_empty())
    end)

    it("should work properly for size and count", function()
        local q = AgeStaticQueue(10)

        expect.equal(q:size(), 0)
        expect.equal(q:used_count(), 0)
        expect.equal(q:free_count(), 10)

        assert(q:push(11) == 0)
        assert(q:push(22) == 0)
        assert(q:push(33) == 0)

        expect.equal(q:size(), 3)
        expect.equal(q:used_count(), 3)
        expect.equal(q:free_count(), 7)
    end)

    it("should work properly for shuffle", function()
        local q = AgeStaticQueue(10)

        for _i = 1, 10 do
            assert(q:push(_i) == 0)
        end

        local _data_before = q:get_all_data()

        q:shuffle()

        local data_after = q:get_all_data()

        -- Check that all elements are still present
        local count = 0
        for i = 1, 10 do
            for _j, val in ipairs(data_after) do
                if val == i then
                    count = count + 1
                    break
                end
            end
        end

        expect.equal(count, 10)
    end)

    it("should work properly for get_all_data", function()
        local q = AgeStaticQueue(5)

        assert(q:push(11) == 0)
        assert(q:push(22) == 0)
        assert(q:push(33) == 0)

        local data = q:get_all_data()

        expect.equal(#data, 3)
        expect.equal(data[1], 11)
        expect.equal(data[2], 22)
        expect.equal(data[3], 33)
    end)

    it("should work properly for circular buffer behavior", function()
        local q = AgeStaticQueue(3)

        assert(q:push(11) == 0)
        assert(q:push(22) == 0)
        assert(q:push(33) == 0)

        expect.equal(q:pop(), 11)
        expect.equal(q:pop(), 22)

        assert(q:push(44) == 0)
        assert(q:push(55) == 0)

        expect.equal(q:pop(), 33)
        expect.equal(q:pop(), 44)
        expect.equal(q:pop(), 55)
    end)

    it("should work properly for __len operator", function()
        local q = AgeStaticQueue(5)

        expect.equal(#q, 0)

        assert(q:push(11) == 0)
        assert(q:push(22) == 0)
        assert(q:push(33) == 0)

        expect.equal(#q, 3)
    end)

    it("should work properly for shuffle with age protection", function()
        local q = AgeStaticQueue(10, 5) -- MAX_AGE = 5

        -- Push elements
        for _i = 1, 5 do
            assert(q:push(_i) == 0)
        end

        -- Pop and push to age the first element
        -- Need 6 pops to make first element age >= 5 (MAX_AGE)
        -- After 6 pops: global_age = 6, front insertion_age = 0, age = 6
        for _i = 1, 6 do
            assert(q:pop() ~= nil)
            assert(q:push(99) == 0)
        end

        -- Run shuffle multiple times and verify front never changes
        -- Without age protection, probability of front staying at same position after 100 shuffles
        -- would be (1/5)^100 ≈ 7.9e-70 (practically impossible)
        for _i = 1, 100 do
            local front_before = q:front()
            q:shuffle()
            local front_after = q:front()
            expect.equal(front_before, front_after)
        end
    end)

    it("should work properly for custom max_age", function()
        local q = AgeStaticQueue(10, 2) -- MAX_AGE = 2

        for _i = 1, 5 do
            assert(q:push(_i) == 0)
        end

        -- Age the first element
        -- Need 3 pops to make first element age >= 2 (MAX_AGE)
        -- After 3 pops: global_age = 3, front insertion_age = 0, age = 3
        for _i = 1, 3 do
            assert(q:pop() ~= nil)
            assert(q:push(99) == 0)
        end

        -- Run shuffle multiple times and verify front never changes
        -- Without age protection, probability of front staying at same position after 100 shuffles
        -- would be (1/5)^100 ≈ 7.9e-70 (practically impossible)
        for _i = 1, 100 do
            local front_before = q:front()
            q:shuffle()
            local front_after = q:front()
            expect.equal(front_before, front_after)
        end
    end)

    it("should work properly for large queue", function()
        local q = AgeStaticQueue(1000)

        for _i = 1, 1000 do
            assert(q:push(_i) == 0)
        end

        expect.equal(q.count, 1000)
        expect.truthy(q:is_full())

        local data = q:get_all_data()
        expect.equal(#data, 1000)
        expect.equal(data[1], 1)
        expect.equal(data[1000], 1000)
    end)

    it("should work properly for empty queue operations", function()
        local q = AgeStaticQueue(5)

        expect.truthy(q:is_empty())
        expect.equal(q:front(), nil)
        expect.equal(q:last(), nil)
        expect.equal(#q:get_all_data(), 0)
    end)

    it("should work properly for multiple shuffles", function()
        local q = AgeStaticQueue(10)

        for _i = 1, 10 do
            assert(q:push(_i) == 0)
        end

        -- Perform multiple shuffles
        for _i = 1, 10 do
            q:shuffle()
        end

        -- Verify all elements are still present
        local data = q:get_all_data()
        local count = 0
        for i = 1, 10 do
            for _j, val in ipairs(data) do
                if val == i then
                    count = count + 1
                    break
                end
            end
        end

        expect.equal(count, 10)
    end)

    it("should work properly for shuffle followed by operations", function()
        local q = AgeStaticQueue(10)

        for _i = 1, 5 do
            assert(q:push(_i) == 0)
        end

        q:shuffle()

        -- Verify queue still works correctly after shuffle
        expect.equal(q.count, 5)
        expect.equal(#q:get_all_data(), 5)

        -- Pop and push should work
        local popped = q:pop()
        expect.truthy(popped)

        assert(q:push(100) == 0)

        expect.equal(q.count, 5)

        -- Verify age protection still works
        for _i = 1, 10 do
            assert(q:pop() ~= nil)
            assert(q:push(99) == 0)
        end

        local front_before = q:front()
        q:shuffle()
        local front_after = q:front()

        -- Age protection should still work after shuffle
        expect.equal(front_before, front_after)
    end)
end)

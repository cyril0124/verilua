---@diagnostic disable: invisible

local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect

local StaticQueue = require "verilua.utils.StaticQueue"

lester.parse_args()

describe("StaticQueue test", function()
    it("should create empty queue", function()
        local q = StaticQueue(4)
        expect.equal(q:size(), 0)
        expect.equal(q:used_count(), 0)
        expect.equal(q:free_count(), 4)
        expect.equal(#q, 0)
        expect.truthy(q:is_empty())
        expect.falsy(q:is_full())
    end)

    it("should reject non-positive size", function()
        expect.fail(function() StaticQueue(0) end)
        expect.fail(function() StaticQueue(-1) end)
    end)

    it("should push and pop elements", function()
        local q = StaticQueue(4)
        expect.equal(q:push(11), 0)
        expect.equal(q:push(22), 0)
        expect.equal(q.count, 2)
        expect.equal(q:size(), 2)
        expect.equal(q:used_count(), 2)
        expect.equal(q:free_count(), 2)
        expect.falsy(q:is_empty())
        expect.falsy(q:is_full())

        expect.equal(q:push(33), 0)
        expect.equal(q:push(44), 0)
        expect.equal(q:push(55), 1)

        expect.equal(q.count, 4)
        expect.truthy(q:is_full())
        expect.equal(q:free_count(), 0)

        expect.equal(q:pop(), 11)
        expect.equal(q:pop(), 22)
        expect.equal(q:pop(), 33)
        expect.equal(q:pop(), 44)
        expect.fail(function() q:pop() end)
    end)

    it("should return nil for front and last when empty", function()
        local q = StaticQueue(4)
        expect.equal(q:front(), nil)
        expect.equal(q:last(), nil)
        expect.equal(q:query_first(), nil)

        q:push(10)
        expect.equal(q:front(), 10)
        expect.equal(q:last(), 10)
        expect.equal(q:query_first(), 10)

        q:push(20)
        expect.equal(q:front(), 10)
        expect.equal(q:last(), 20)

        q:pop()
        q:pop()
        expect.equal(q:front(), nil)
        expect.equal(q:last(), nil)
    end)

    it("should wrap around ring buffer", function()
        local q = StaticQueue(4)
        q:push(1)
        q:push(2)
        q:push(3)
        q:push(4)
        expect.equal(q:pop(), 1)
        expect.equal(q:pop(), 2)
        -- Now first_ptr is at 3, push should wrap to slot 1
        expect.equal(q:push(5), 0)
        expect.equal(q:push(6), 0)
        expect.equal(q:pop(), 3)
        expect.equal(q:pop(), 4)
        expect.equal(q:pop(), 5)
        expect.equal(q:pop(), 6)
    end)

    it("should reset correctly", function()
        local q = StaticQueue(4, "ResetQ")
        q:push(1)
        q:push(2)
        expect.equal(q:size(), 2)
        q:reset()
        expect.equal(q:size(), 0)
        expect.truthy(q:is_empty())
        expect.equal(q:front(), nil)
        expect.equal(q:last(), nil)
    end)

    it("should shuffle elements", function()
        local q = StaticQueue(10)
        for i = 1, 5 do
            q:push(i)
        end
        q:shuffle()
        -- After shuffle, size should remain the same and all elements still present
        expect.equal(q:size(), 5)
        local arr = q:get_all_data()
        local seen = {}
        for _, v in ipairs(arr) do
            seen[v] = true
        end
        for i = 1, 5 do
            expect.truthy(seen[i])
        end
    end)

    it("should get_all_data in queue order", function()
        local q = StaticQueue(4)
        q:push(10)
        q:push(20)
        q:push(30)
        local arr = q:get_all_data()
        expect.equal(#arr, 3)
        expect.equal(arr[1], 10)
        expect.equal(arr[2], 20)
        expect.equal(arr[3], 30)
    end)

    it("should return empty array for get_all_data when empty", function()
        local q = StaticQueue(4)
        local arr = q:get_all_data()
        expect.equal(#arr, 0)
    end)

    it("should list_data without error", function()
        local q = StaticQueue(4, "ListQ")
        q:push(42)
        q:push(99)
        -- list_data prints to stdout; just ensure it doesn't error
        q:list_data()
    end)

    it("should list_data when empty without error", function()
        local q = StaticQueue(4, "EmptyQ")
        q:list_data()
    end)
end)

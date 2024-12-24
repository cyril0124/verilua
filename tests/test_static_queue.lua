local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect

local StaticQueue = require "StaticQueue"

lester.parse_args()

describe("StaticQueue test", function ()
    it("should work properly", function()
        local q = StaticQueue(4)
        
        expect.truthy(q:is_empty())
        expect.fail(function () q:pop() end)
        
        q:push(11)
        q:push(22)
        
        expect.equal(q.count, 2)

        expect.equal(q:push(33), 0)
        expect.equal(q:push(44), 0)

        expect.equal(q:push(55), 1)

        expect.equal(q.count, 4)
        expect.truthy(q:is_full())

        expect.equal(q:pop(), 11)
        expect.equal(q:pop(), 22)
        expect.equal(q:pop(), 33)
        expect.equal(q:pop(), 44)
        expect.fail(function () q:pop() end)
    end)
end)
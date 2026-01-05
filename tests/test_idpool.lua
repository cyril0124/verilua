---@diagnostic disable: access-invisible

local lester = require "lester"
local IDPool = require "verilua.utils.IDPool"

local describe, it, expect = lester.describe, lester.it, lester.expect

lester.parse_args()

describe("IDPool test", function()
    it("should create pool with size", function()
        local pool = IDPool(10)
        expect.equal(pool.POOL_SIZE, 10)
        expect.equal(pool:free_count(), 10)
        expect.equal(pool:used_count(), 0)
    end)

    it("should create pool with start_value", function()
        local pool = IDPool({ size = 10, start_value = 100 })
        expect.equal(pool.POOL_SIZE, 10)
        expect.equal(pool.START_VALUE, 100)
        expect.equal(pool.END_VALUE, 109)
    end)

    it("should allocate and release IDs", function()
        local pool = IDPool(10)
        local id = pool:alloc()
        expect.equal(type(id), "number")
        expect.equal(pool:free_count(), 9)
        expect.equal(pool:used_count(), 1)

        pool:release(id)
        expect.equal(pool:free_count(), 10)
        expect.equal(pool:used_count(), 0)
    end)

    it("should allocate all IDs", function()
        local pool = IDPool(5)
        local ids = {}
        for i = 1, 5 do
            ids[i] = pool:alloc()
        end
        expect.equal(pool:free_count(), 0)
        expect.equal(pool:used_count(), 5)
    end)

    it("should fail when pool is empty", function()
        local pool = IDPool(2)
        local _ = pool:alloc()
        local _ = pool:alloc()
        expect.fail(function()
            local _ = pool:alloc()
        end, "table index is nil")
    end)

    it("should fail on duplicate release", function()
        local pool = IDPool(5)
        local id = pool:alloc()
        pool:release(id)
        expect.fail(function()
            pool:release(id)
        end, "id is not allocated or already in the pool")
    end)

    it("should fail on out of range ID", function()
        local pool = IDPool(5, false)
        expect.fail(function()
            pool:release(10)
        end, "[IDPool] id is out of range")
    end)

    it("should reset pool", function()
        local pool = IDPool(5)
        local _ = pool:alloc()
        local _ = pool:alloc()
        expect.equal(pool:free_count(), 3)
        pool:reset()
        expect.equal(pool:free_count(), 5)
        expect.equal(pool:used_count(), 0)
    end)

    it("should work with shuffle", function()
        local pool = IDPool(10, true)
        local ids = {}
        for i = 1, 10 do
            ids[i] = pool:alloc()
        end
        -- All IDs should be unique
        for i = 1, 10 do
            for j = i + 1, 10 do
                assert(ids[i] ~= ids[j], "IDs should be unique")
            end
        end
    end)

    it("should return correct length", function()
        local pool = IDPool(100)
        expect.equal(#pool, 100)
    end)

    it("should support multiple alloc/release cycles", function()
        local pool = IDPool(5)
        local id1 = pool:alloc()
        local _ = pool:alloc()
        pool:release(id1)
        local _ = pool:alloc()
        expect.equal(pool:used_count(), 2)
        expect.equal(pool:free_count(), 3)
    end)

    it("should work with large pool", function()
        local pool = IDPool(10000)
        local id = pool:alloc()
        expect.equal(type(id), "number")
        assert(id >= 0)
        assert(id < 10000)
        pool:release(id)
        expect.equal(pool:free_count(), 10000)
    end)

    it("should maintain ID range with start_value", function()
        local pool = IDPool({ size = 10, start_value = 1000 })
        local id = pool:alloc()
        assert(id >= 1000)
        assert(id <= 1009)
    end)

    it("should handle edge case: pool size 1", function()
        local pool = IDPool(1)
        expect.equal(pool:free_count(), 1)
        local id = pool:alloc()
        expect.equal(pool:free_count(), 0)
        pool:release(id)
        expect.equal(pool:free_count(), 1)
    end)
end)
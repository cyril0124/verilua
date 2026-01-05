---@diagnostic disable: access-invisible

local lester = require "lester"
local Queue = require "verilua.utils.Queue"

local describe, it, expect = lester.describe, lester.it, lester.expect

lester.parse_args()

describe("Queue test", function()
    it("should create queue with default options", function()
        local q = Queue()
        expect.equal(q:size(), 0)
        expect.equal(q:is_empty(), true)
    end)

    it("should create queue with name", function()
        local q = Queue({ name = "TestQueue" })
        expect.equal(q:size(), 0)
        expect.equal(q:is_empty(), true)
    end)

    it("should create queue with compact_threshold", function()
        local q = Queue({ compact_threshold = 10 })
        expect.equal(q:size(), 0)
        expect.equal(q:is_empty(), true)
    end)

    it("should create queue with leak_check enabled", function()
        local q = Queue({ leak_check = true, leak_check_threshold = 5 })
        expect.equal(q:size(), 0)
        expect.equal(q:is_empty(), true)
    end)

    it("should push and pop elements", function()
        local q = Queue()
        q:push(1)
        q:push(2)
        q:push(3)
        expect.equal(q:size(), 3)
        expect.equal(q:pop(), 1)
        expect.equal(q:pop(), 2)
        expect.equal(q:size(), 1)
    end)

    it("should return first element with query_first_ptr", function()
        local q = Queue()
        q:push(10)
        q:push(20)
        q:push(30)
        expect.equal(q:query_first_ptr(), 10)
        expect.equal(q:size(), 3)
    end)

    it("should return first element with front", function()
        local q = Queue()
        q:push(100)
        q:push(200)
        expect.equal(q:front(), 100)
        expect.equal(q:size(), 2)
    end)

    it("should return last element", function()
        local q = Queue()
        q:push(1)
        q:push(2)
        q:push(3)
        expect.equal(q:last(), 3)
    end)

    it("should return nil for last when queue is empty", function()
        local q = Queue()
        expect.equal(q:last(), nil)
    end)

    it("should check if queue is empty", function()
        local q = Queue()
        expect.equal(q:is_empty(), true)
        q:push(1)
        expect.equal(q:is_empty(), false)
        local _ = q:pop()
        expect.equal(q:is_empty(), true)
    end)

    it("should return correct size", function()
        local q = Queue()
        expect.equal(q:size(), 0)
        q:push(1)
        expect.equal(q:size(), 1)
        q:push(2)
        q:push(3)
        expect.equal(q:size(), 3)
        local _ = q:pop()
        expect.equal(q:size(), 2)
    end)

    it("should work with # operator", function()
        local q = Queue()
        expect.equal(#q, 0)
        q:push(1)
        q:push(2)
        expect.equal(#q, 2)
        local _ = q:pop()
        expect.equal(#q, 1)
    end)

    it("should reset queue", function()
        local q = Queue()
        q:push(1)
        q:push(2)
        q:push(3)
        expect.equal(q:size(), 3)
        q:reset()
        expect.equal(q:size(), 0)
        expect.equal(q:is_empty(), true)
    end)

    it("should handle string elements", function()
        local q = Queue()
        q:push("hello")
        q:push("world")
        expect.equal(q:pop(), "hello")
        expect.equal(q:pop(), "world")
    end)

    it("should handle table elements", function()
        local q = Queue()
        q:push({ name = "Alice", age = 30 })
        q:push({ name = "Bob", age = 25 })
        local result = q:pop()
        expect.equal(result.name, "Alice")
        expect.equal(result.age, 30)
    end)

    it("should handle mixed types", function()
        local q = Queue()
        q:push(1)
        q:push("string")
        q:push({ key = "value" })
        q:push(true)
        expect.equal(q:pop(), 1)
        expect.equal(q:pop(), "string")
        local result = q:pop()
        expect.equal(result.key, "value")
        expect.equal(q:pop(), true)
    end)

    it("should fail when popping from empty queue", function()
        local q = Queue()
        expect.fail(function()
            q:pop()
        end, "queue is empty")
    end)

    it("should work with large number of elements", function()
        local q = Queue()
        local count = 1000
        for i = 1, count do
            q:push(i)
        end
        expect.equal(q:size(), count)
        for i = 1, count do
            expect.equal(q:pop(), i)
        end
        expect.equal(q:is_empty(), true)
    end)

    it("should handle push after pop", function()
        local q = Queue()
        q:push(1)
        q:push(2)
        local _ = q:pop()
        q:push(3)
        expect.equal(q:size(), 2)
        expect.equal(q:pop(), 2)
        expect.equal(q:pop(), 3)
    end)

    it("should handle multiple push/pop cycles", function()
        local q = Queue()
        for cycle = 1, 10 do
            q:push(cycle)
            q:push(cycle + 100)
            expect.equal(q:pop(), cycle)
            expect.equal(q:pop(), cycle + 100)
        end
        expect.equal(q:is_empty(), true)
    end)

    it("should trigger compaction after threshold", function()
        local q = Queue({ compact_threshold = 5 })
        -- Push 10 elements
        for i = 1, 10 do
            q:push(i)
        end
        -- Pop 5 elements to create gap
        for i = 1, 5 do
            expect.equal(q:pop(), i)
        end
        -- Push 5 more elements
        for i = 11, 15 do
            q:push(i)
        end
        -- Pop remaining elements
        for i = 6, 15 do
            expect.equal(q:pop(), i)
        end
        expect.equal(q:is_empty(), true)
    end)

    it("should reset leak check counter on pop when leak_check enabled", function()
        local q = Queue({ leak_check = true, leak_check_threshold = 10 })
        q:push(1)
        q:push(2)
        -- Call do_leak_check multiple times
        for _i = 1, 5 do
            q:do_leak_check()
        end
        -- Pop should reset counter
        local _ = q:pop()
        -- Should not trigger leak check
        for _i = 1, 5 do
            q:do_leak_check()
        end
        expect.equal(q:size(), 1)
    end)

    it("should detect leak when leak_check enabled", function()
        local q = Queue({ leak_check = true, leak_check_threshold = 3 })
        q:push(1)
        q:push(2)
        q:push(3)
        -- Call do_leak_check to reach threshold
        q:do_leak_check()
        q:do_leak_check()
        q:do_leak_check()
        -- Next call should trigger leak check
        expect.fail(function()
            q:do_leak_check()
        end, "Queue leak check failed")
    end)

    it("should convert to string correctly", function()
        local q = Queue({ name = "TestQueue" })
        local str = tostring(q)
        expect.equal(string.find(str, "TestQueue") ~= nil, true)
        expect.equal(string.find(str, "Queue is empty") ~= nil, true)
    end)

    it("should convert to string with elements", function()
        local q = Queue({ name = "TestQueue" })
        q:push(1)
        q:push(2)
        local str = tostring(q)
        expect.equal(string.find(str, "TestQueue") ~= nil, true)
        expect.equal(string.find(str, "2 elements") ~= nil, true)
    end)

    it("should convert to string with leak_check info", function()
        local q = Queue({ name = "TestQueue", leak_check = true })
        q:push(1)
        local str = tostring(q)
        expect.equal(string.find(str, "Leak check:") ~= nil, true)
    end)

    it("should handle nil elements", function()
        local q = Queue()
        q:push(nil)
        q:push(1)
        q:push(nil)
        expect.equal(q:size(), 3)
        expect.equal(q:pop(), nil)
        expect.equal(q:pop(), 1)
        expect.equal(q:pop(), nil)
    end)

    it("should maintain FIFO order", function()
        local q = Queue()
        local elements = { "first", "second", "third", "fourth", "fifth" }
        for _, elem in ipairs(elements) do
            q:push(elem)
        end
        for _, elem in ipairs(elements) do
            expect.equal(q:pop(), elem)
        end
    end)

    it("should work with custom compact_threshold", function()
        local q = Queue({ compact_threshold = 2 })
        q:push(1)
        q:push(2)
        local _ = q:pop()
        q:push(3)
        local _ = q:pop()
        q:push(4)
        expect.equal(q:size(), 2)
        expect.equal(q:pop(), 3)
        expect.equal(q:pop(), 4)
    end)

    it("should reset leak_check_cnt on reset", function()
        local q = Queue({ leak_check = true, leak_check_threshold = 10 })
        q:push(1)
        q:push(2)
        q:do_leak_check()
        q:do_leak_check()
        q:do_leak_check()
        q:reset()
        -- After reset, leak_check_cnt should be 0
        -- We can call do_leak_check up to threshold times without error
        for _i = 1, 10 do
            q:do_leak_check()
        end
        expect.equal(q:is_empty(), true)
    end)

    it("should handle queue with single element", function()
        local q = Queue()
        q:push(42)
        expect.equal(q:size(), 1)
        expect.equal(q:front(), 42)
        expect.equal(q:last(), 42)
        expect.equal(q:pop(), 42)
        expect.equal(q:is_empty(), true)
    end)

    it("should work with boolean elements", function()
        local q = Queue()
        q:push(true)
        q:push(false)
        q:push(true)
        expect.equal(q:pop(), true)
        expect.equal(q:pop(), false)
        expect.equal(q:pop(), true)
    end)

    it("should work with function elements", function()
        local q = Queue()
        local func1 = function() return 1 end
        local func2 = function() return 2 end
        q:push(func1)
        q:push(func2)
        local result1 = q:pop()
        local result2 = q:pop()
        expect.equal(result1(), 1)
        expect.equal(result2(), 2)
    end)

    it("should generate unique names for anonymous queues", function()
        local q1 = Queue()
        local q2 = Queue()
        local q3 = Queue()
        local str1 = tostring(q1)
        local str2 = tostring(q2)
        local str3 = tostring(q3)
        -- Names should be different
        expect.equal(str1 ~= str2, true)
        expect.equal(str2 ~= str3, true)
        expect.equal(str1 ~= str3, true)
    end)
end)
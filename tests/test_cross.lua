---@diagnostic disable: access-invisible
local lester = require "lester"
local describe, it, _expect = lester.describe, lester.it, lester.expect
local assert = assert
local sort = table.sort
local concat = table.concat
local tostring = tostring

local Cross = require "verilua.Cross"

lester.parse_args()

-- Helper: compare two arrays element-by-element
local function array_eq(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- Helper: check if a table of arrays contains a specific array
local function contains(tbl, arr)
    for _, v in ipairs(tbl) do
        if array_eq(v, arr) then return true end
    end
    return false
end

describe("Cross.product", function()
    it("should produce correct cartesian product for 2 lists", function()
        local lists = { { 1, 2 }, { "a", "b" } }
        local result = Cross.product_table(lists)

        assert(#result == 4, "expected 4 combos, got " .. #result)
        assert(contains(result, { 1, "a" }))
        assert(contains(result, { 1, "b" }))
        assert(contains(result, { 2, "a" }))
        assert(contains(result, { 2, "b" }))
    end)

    it("should produce correct cartesian product for 3 lists", function()
        local lists = { { 1, 2 }, { "a", "b" }, { true, false } }
        local result = Cross.product_table(lists)

        assert(#result == 8, "expected 8 combos, got " .. #result)
    end)

    it("should handle single list", function()
        local lists = { { 1, 2, 3 } }
        local result = Cross.product_table(lists)

        assert(#result == 3)
        assert(contains(result, { 1 }))
        assert(contains(result, { 2 }))
        assert(contains(result, { 3 }))
    end)

    it("should work with iterator", function()
        local lists = { { 1, 2 }, { 3, 4 } }
        local count = 0
        for combo in Cross.product_iter(lists) do
            count = count + 1
            assert(#combo == 2)
        end
        assert(count == 4)
    end)

    it("should apply filter", function()
        local lists = { { 1, 2, 3 }, { 1, 2, 3 } }
        local result = Cross.product_table(lists, {
            filter = function(combo) return combo[1] ~= combo[2] end,
        })

        -- 3x3=9 total, minus 3 where a==b = 6
        assert(#result == 6, "expected 6, got " .. #result)
        for _, combo in ipairs(result) do
            assert(combo[1] ~= combo[2], "filter failed: " .. combo[1] .. "==" .. combo[2])
        end
    end)

    it("should apply filter in iterator mode", function()
        local lists = { { 1, 2, 3 }, { 1, 2, 3 } }
        local count = 0
        for combo in Cross.product_iter(lists, { filter = function(c) return c[1] > c[2] end }) do
            count = count + 1
            assert(combo[1] > combo[2])
        end
        -- Pairs where a > b: (2,1), (3,1), (3,2) = 3
        assert(count == 3, "expected 3, got " .. count)
    end)

    it("should handle empty lists input", function()
        local iter = Cross.product_iter({})
        assert(iter() == nil)
    end)
end)

describe("Cross.product sampling", function()
    it("should sample the requested number", function()
        math.randomseed(42)
        local lists = { { 1, 2, 3, 4, 5 }, { "a", "b", "c", "d", "e" } }
        local result = Cross.product_table(lists, { sample = 5 })
        assert(#result == 5, "expected 5 samples, got " .. #result)
    end)

    it("should respect unique constraint", function()
        math.randomseed(42)
        local lists = { { 1, 2, 3 }, { "a", "b" } }
        local result = Cross.product_table(lists, { sample = 6, unique = true })
        assert(#result == 6, "expected 6 unique samples, got " .. #result)

        -- Verify all are unique
        local seen = {}
        for _, combo in ipairs(result) do
            local key = tostring(combo[1]) .. "\0" .. tostring(combo[2])
            assert(not seen[key], "duplicate found: " .. key)
            seen[key] = true
        end
    end)

    it("should error when sample > space with unique", function()
        local lists = { { 1, 2 }, { "a", "b" } } -- space = 4
        local ok, err = pcall(function()
            Cross.product_table(lists, { sample = 5, unique = true })
        end)
        assert(not ok, "expected error")
        assert(err:find("exceeds"), "expected 'exceeds' in error: " .. tostring(err))
    end)

    it("should support weighted sampling", function()
        math.randomseed(123)
        -- Heavily weight first element
        local lists = { { "rare", "common" }, { 1, 2, 3 } }
        local weights = { { 1, 99 }, { 1, 1, 1 } }
        local result = Cross.product_table(lists, { sample = 100, weights = weights })
        assert(#result == 100)

        -- Count how many times "common" appears vs "rare"
        local common_count = 0
        for _, combo in ipairs(result) do
            if combo[1] == "common" then common_count = common_count + 1 end
        end
        -- With weight 99:1, "common" should dominate
        assert(common_count > 80, "expected common > 80, got " .. common_count)
    end)

    it("should apply filter during sampling", function()
        math.randomseed(42)
        local lists = { { 1, 2, 3 }, { 1, 2, 3 } }
        local result = Cross.product_table(lists, {
            sample = 3,
            filter = function(c) return c[1] ~= c[2] end,
        })
        assert(#result == 3)
        for _, combo in ipairs(result) do
            assert(combo[1] ~= combo[2])
        end
    end)
end)

describe("Cross.permutations", function()
    it("should produce all permutations of 3 elements", function()
        local result = Cross.permutations_table({ 1, 2, 3 })
        assert(#result == 6, "expected 6 permutations, got " .. #result)

        assert(contains(result, { 1, 2, 3 }))
        assert(contains(result, { 1, 3, 2 }))
        assert(contains(result, { 2, 1, 3 }))
        assert(contains(result, { 2, 3, 1 }))
        assert(contains(result, { 3, 1, 2 }))
        assert(contains(result, { 3, 2, 1 }))
    end)

    it("should produce 1 permutation for single element", function()
        local result = Cross.permutations_table({ 42 })
        assert(#result == 1)
        assert(result[1][1] == 42)
    end)

    it("should produce 24 permutations for 4 elements", function()
        local result = Cross.permutations_table({ 1, 2, 3, 4 })
        assert(#result == 24, "expected 24, got " .. #result)
    end)

    it("should work with iterator", function()
        local count = 0
        for perm in Cross.permutations_iter({ "a", "b", "c" }) do
            count = count + 1
            assert(#perm == 3)
        end
        assert(count == 6)
    end)

    it("should apply filter", function()
        -- Only permutations where first element is 1
        local result = Cross.permutations_table({ 1, 2, 3 }, {
            filter = function(p) return p[1] == 1 end,
        })
        assert(#result == 2, "expected 2, got " .. #result) -- {1,2,3} and {1,3,2}
        for _, p in ipairs(result) do
            assert(p[1] == 1)
        end
    end)

    it("should handle empty list", function()
        local iter = Cross.permutations_iter({})
        assert(iter() == nil)
    end)
end)

describe("Cross.permutations sampling", function()
    it("should sample random permutations", function()
        math.randomseed(42)
        local result = Cross.permutations_table({ 1, 2, 3, 4 }, { sample = 5 })
        assert(#result == 5)
        -- Each should be a valid permutation of {1,2,3,4}
        for _, perm in ipairs(result) do
            local sorted = { perm[1], perm[2], perm[3], perm[4] }
            sort(sorted)
            assert(array_eq(sorted, { 1, 2, 3, 4 }))
        end
    end)

    it("should respect unique in sampling", function()
        math.randomseed(42)
        local result = Cross.permutations_table({ 1, 2, 3 }, { sample = 6, unique = true })
        assert(#result == 6, "expected 6, got " .. #result)

        local seen = {}
        for _, perm in ipairs(result) do
            local key = concat({ tostring(perm[1]), tostring(perm[2]), tostring(perm[3]) }, ",")
            assert(not seen[key], "duplicate: " .. key)
            seen[key] = true
        end
    end)

    it("should error when sample > n! with unique", function()
        local ok, err = pcall(function()
            Cross.permutations_table({ 1, 2, 3 }, { sample = 7, unique = true })
        end)
        assert(not ok)
        assert(err:find("exceeds"))
    end)
end)

describe("Cross.combinations", function()
    it("should produce C(4,2) = 6 combinations", function()
        local result = Cross.combinations_table({ 1, 2, 3, 4 }, 2)
        assert(#result == 6, "expected 6, got " .. #result)

        assert(contains(result, { 1, 2 }))
        assert(contains(result, { 1, 3 }))
        assert(contains(result, { 1, 4 }))
        assert(contains(result, { 2, 3 }))
        assert(contains(result, { 2, 4 }))
        assert(contains(result, { 3, 4 }))
    end)

    it("should produce C(5,3) = 10 combinations", function()
        local result = Cross.combinations_table({ 1, 2, 3, 4, 5 }, 3)
        assert(#result == 10, "expected 10, got " .. #result)
    end)

    it("should produce C(n,0) = 1 (empty set)", function()
        local result = Cross.combinations_table({ 1, 2, 3 }, 0)
        assert(#result == 1)
        assert(#result[1] == 0)
    end)

    it("should apply filter when k is 0", function()
        local result = Cross.combinations_table({ 1, 2, 3 }, 0, {
            filter = function()
                return false
            end,
        })
        assert(#result == 0, "expected filter to reject empty combination")
    end)

    it("should produce C(n,n) = 1 (full set)", function()
        local result = Cross.combinations_table({ 1, 2, 3 }, 3)
        assert(#result == 1)
        assert(array_eq(result[1], { 1, 2, 3 }))
    end)

    it("should work with iterator", function()
        local count = 0
        for combo in Cross.combinations_iter({ 1, 2, 3, 4, 5 }, 2) do
            count = count + 1
            assert(#combo == 2)
            assert(combo[1] < combo[2]) -- combinations are in order
        end
        assert(count == 10)
    end)

    it("should apply filter", function()
        -- Only combinations where sum > 5
        local result = Cross.combinations_table({ 1, 2, 3, 4, 5 }, 2, {
            filter = function(c) return c[1] + c[2] > 5 end,
        })
        for _, combo in ipairs(result) do
            assert(combo[1] + combo[2] > 5)
        end
        -- Pairs with sum > 5: (1,5),(2,4),(2,5),(3,4),(3,5),(4,5) = 6
        assert(#result == 6, "expected 6, got " .. #result)
    end)

    it("should error when k > n", function()
        local ok, err = pcall(function()
            Cross.combinations_iter({ 1, 2 }, 3)
        end)
        assert(not ok)
        assert(err:find("k"))
    end)
end)

describe("Cross.combinations sampling", function()
    it("should sample random combinations", function()
        math.randomseed(42)
        local result = Cross.combinations_table({ 1, 2, 3, 4, 5 }, 2, { sample = 4 })
        assert(#result == 4)
        for _, combo in ipairs(result) do
            assert(#combo == 2)
        end
    end)

    it("should respect unique (set equality)", function()
        math.randomseed(42)
        local result = Cross.combinations_table({ 1, 2, 3, 4, 5 }, 2, { sample = 10, unique = true })
        assert(#result == 10, "expected 10, got " .. #result)

        -- Verify uniqueness using set keys
        local seen = {}
        for _, combo in ipairs(result) do
            local sorted = { combo[1], combo[2] }
            sort(sorted)
            local key = tostring(sorted[1]) .. "," .. tostring(sorted[2])
            assert(not seen[key], "duplicate: " .. key)
            seen[key] = true
        end
    end)

    it("should error when sample > C(n,k) with unique", function()
        local ok, err = pcall(function()
            -- C(4,2) = 6, requesting 7
            Cross.combinations_table({ 1, 2, 3, 4 }, 2, { sample = 7, unique = true })
        end)
        assert(not ok)
        assert(err:find("exceeds"))
    end)
end)

describe("Cross edge cases", function()
    it("product_iter reuses table (verify copy needed)", function()
        local lists = { { 1, 2 }, { 3, 4 } }
        local refs = {}
        for combo in Cross.product_iter(lists) do
            -- All iterations return the same table reference
            refs[#refs + 1] = combo
        end
        -- They should all be the same reference
        for i = 2, #refs do
            assert(refs[i] == refs[1], "expected same table reference for performance")
        end
    end)

    it("permutations_iter reuses table", function()
        local refs = {}
        for perm in Cross.permutations_iter({ 1, 2, 3 }) do
            refs[#refs + 1] = perm
        end
        for i = 2, #refs do
            assert(refs[i] == refs[1], "expected same table reference for performance")
        end
    end)

    it("combinations_iter reuses table", function()
        local refs = {}
        for combo in Cross.combinations_iter({ 1, 2, 3, 4 }, 2) do
            refs[#refs + 1] = combo
        end
        for i = 2, #refs do
            assert(refs[i] == refs[1], "expected same table reference for performance")
        end
    end)
end)

describe("Cross bug regression", function()
    it("sample_combinations should preserve input-list index order", function()
        math.randomseed(42)
        local input = { 1, 2, 10, 20 }
        local pos = {}
        for i, v in ipairs(input) do pos[v] = i end

        local results = Cross.combinations_table(input, 2, { sample = 6, unique = true })
        assert(#results == 6)
        for _, combo in ipairs(results) do
            assert(
                pos[combo[1]] < pos[combo[2]],
                "bad order: " .. tostring(combo[1]) .. " before " .. tostring(combo[2])
            )
        end
    end)

    it("weighted_pick should error on all-zero weights", function()
        local ok, err = pcall(function()
            Cross.product_table({ { 1, 2, 3 }, { 4, 5, 6 } }, {
                sample = 5,
                weights = { { 0, 0, 0 }, { 1, 1, 1 } },
            })
        end)
        assert(not ok, "expected error with all-zero weights")
        assert(tostring(err):find("zero"), "expected 'zero' in error: " .. tostring(err))
    end)
end)

describe("Cross bug regression: cross-check fixes", function()
    it("should error when weights array length mismatches list length (longer)", function()
        local lists = { { 1, 2, 3 }, { 4, 5, 6 } }
        local ok, err = pcall(function()
            Cross.product_table(lists, {
                sample = 5,
                weights = { { 1, 2, 3, 4 }, { 1, 1, 1 } }, -- weights[1] has 4 elements, list[1] has 3
            })
        end)
        assert(not ok, "expected error for weights length mismatch")
        assert(tostring(err):find("weights"), "expected 'weights' in error: " .. tostring(err))
    end)

    it("should error when weights array length mismatches list length (shorter)", function()
        local lists = { { 1, 2, 3 }, { 4, 5, 6 } }
        local ok, err = pcall(function()
            Cross.product_table(lists, {
                sample = 5,
                weights = { { 1, 2 }, { 1, 1, 1 } }, -- weights[1] has 2 elements, list[1] has 3
            })
        end)
        assert(not ok, "expected error for weights length mismatch")
        assert(tostring(err):find("weights"), "expected 'weights' in error: " .. tostring(err))
    end)

    it("should error in _sample_combinations when k > n", function()
        local ok, err = pcall(function()
            Cross.combinations_table({ 1, 2 }, 3, { sample = 1 })
        end)
        assert(not ok, "expected error for k > n in sample path")
        assert(tostring(err):find("k"), "expected 'k' in error: " .. tostring(err))
    end)

    it("weighted_pick should never select zero-weight elements", function()
        -- Test with many seeds to ensure zero-weight elements are never picked
        local lists = { { "never1", "never2", "always" }, { 1 } }
        for seed = 0, 99 do
            math.randomseed(seed)
            local result = Cross.product_table(lists, {
                sample = 10,
                weights = { { 0, 0, 10 }, { 1 } },
            })
            for _, combo in ipairs(result) do
                assert(
                    combo[1] == "always",
                    "seed=" .. seed .. ": zero-weight element selected: " .. tostring(combo[1])
                )
            end
        end
    end)

    it("unique dedup should handle values containing NUL bytes", function()
        -- Two distinct tuples that would collide with bare \0 separator:
        -- ("a\0b", "c") and ("a", "b\0c") must be treated as different
        local lists = { { "a\0b", "a" }, { "c", "b\0c" } }
        -- Total space = 4 distinct combos. Enumerate all.
        local result = Cross.product_table(lists)
        assert(#result == 4, "expected 4 combos, got " .. #result)

        -- Now sample all 4 with unique=true
        math.randomseed(42)
        local sampled = Cross.product_table(lists, { sample = 4, unique = true })
        assert(#sampled == 4, "expected 4 unique combos, got " .. #sampled)
    end)

    it("unique dedup should distinguish values with different Lua types", function()
        local product = Cross.product_table({ { 1, "1" } }, { sample = 2, unique = true })
        assert(#product == 2, "expected 2 unique product samples, got " .. #product)

        local permutations = Cross.permutations_table({ 1, "1" }, { sample = 2, unique = true })
        assert(#permutations == 2, "expected 2 unique permutation samples, got " .. #permutations)

        local combinations = Cross.combinations_table({ 1, "1" }, 1, { sample = 2, unique = true })
        assert(#combinations == 2, "expected 2 unique combination samples, got " .. #combinations)
    end)

    it("should reject non-integer sample counts", function()
        ---@type any
        local opts = { sample = 1.5 }
        local ok, err = pcall(function()
            Cross.product_table({ { 1, 2 }, { 3, 4 } }, opts)
        end)
        assert(not ok, "expected error for non-integer sample")
        assert(tostring(err):find("integer"), "expected integer-related error: " .. tostring(err))
    end)

    it("should reject non-integer combination k", function()
        ---@type any
        local k = 1.5
        local ok, err = pcall(function()
            Cross.combinations_table({ 1, 2, 3 }, k)
        end)
        assert(not ok, "expected error for non-integer k")
        assert(tostring(err):find("integer"), "expected integer-related error: " .. tostring(err))
    end)

    it("should error on negative weights", function()
        local lists = { { 1, 2, 3 }, { 4, 5, 6 } }
        local ok, err = pcall(function()
            Cross.product_table(lists, {
                sample = 5,
                weights = { { -1, 2, 3 }, { 1, 1, 1 } },
            })
        end)
        assert(not ok, "expected error for negative weight")
        assert(tostring(err):find("negative") or tostring(err):find("weight"),
            "expected weight-related error: " .. tostring(err))
    end)

    it("product_iter should give clear error for non-table list element", function()
        local ok, err = pcall(function()
            local iter = Cross.product_iter({ { 1, 2 }, "not_a_table" }) ---@diagnostic disable-line: assign-type-mismatch
            iter()
        end)
        assert(not ok, "expected error for non-table element")
        assert(tostring(err):find("table"), "expected 'table' in error: " .. tostring(err))
    end)

    it("product n=0 should be consistent between iter and sample", function()
        -- product_iter({}) returns nil immediately (0 results)
        local iter_count = 0
        for _ in Cross.product_iter({}) do
            iter_count = iter_count + 1
        end

        -- _sample_product({}, {sample=1}) should also produce 0 results (error)
        -- OR both should produce 1 empty product. They must agree.
        if iter_count == 0 then
            local ok = pcall(function()
                Cross.product_table({}, { sample = 1 })
            end)
            -- If iter gives 0, sample should error (can't sample from empty space)
            assert(not ok, "sample path should error for empty input when iter gives 0 results")
        end
    end)

    it("permutations_table sample path should validate input type", function()
        local ok, err = pcall(function()
            Cross.permutations_table("not_a_table", { sample = 1 }) ---@diagnostic disable-line: param-type-mismatch
        end)
        assert(not ok, "expected error for non-table input")
        assert(tostring(err):find("table"), "expected 'table' in error: " .. tostring(err))
    end)

    it("combinations_table sample path should validate k <= n", function()
        local ok, err = pcall(function()
            Cross.combinations_table({ 1, 2 }, 5, { sample = 1 })
        end)
        assert(not ok, "expected error for k > n in sample path")
        assert(tostring(err):find("k"), "expected 'k' in error: " .. tostring(err))
    end)

    it("permutations n=0 should be consistent between iter and sample", function()
        -- permutations_iter({}) returns nil immediately (0 results)
        local iter_count = 0
        for _ in Cross.permutations_iter({}) do
            iter_count = iter_count + 1
        end

        -- _sample_permutations({}, {sample=1}) should also produce 0 results (error)
        -- OR both should produce 1 empty permutation. They must agree.
        if iter_count == 0 then
            local ok = pcall(function()
                Cross.permutations_table({}, { sample = 1 })
            end)
            -- If iter gives 0, sample should error (can't sample from empty space)
            assert(not ok, "sample path should error for empty input when iter gives 0 results")
        end
    end)

    it("_sample_combinations should be fast for k close to n", function()
        math.randomseed(42)
        -- C(50, 45) = C(50, 5) = 2118760. Sample 100 unique.
        -- With Fisher-Yates this should be fast; with rejection it would be slow.
        local input = {}
        for i = 1, 50 do input[i] = i end

        local start = os.clock()
        local result = Cross.combinations_table(input, 45, { sample = 100, unique = true })
        local elapsed = os.clock() - start

        assert(#result == 100, "expected 100, got " .. #result)
        -- Should complete in well under 1 second
        assert(elapsed < 1.0, "too slow: " .. elapsed .. "s (expected < 1s)")
    end)
end)


describe("Cross.product_call", function()
    local function assert_order(actual, expected)
        assert(#actual == #expected, "expected " .. #expected .. " executions, got " .. #actual)
        for i = 1, #expected do
            assert(actual[i] == expected[i], "at " .. i .. ": expected " .. expected[i] .. ", got " .. tostring(actual[i]))
        end
    end

    it("should execute cartesian combinations in dimension order", function()
        local order = {}

        Cross.product_call {
            {
                function() order[#order + 1] = "A1" end,
                function() order[#order + 1] = "A2" end,
            },
            {
                function() order[#order + 1] = "B1" end,
                function() order[#order + 1] = "B2" end,
            },
        }

        assert_order(order, { "A1", "B1", "A1", "B2", "A2", "B1", "A2", "B2" })
    end)

    it("should execute 3D combinations in the legacy order", function()
        local order = {}

        Cross.product_call {
            {
                function() order[#order + 1] = "A1" end,
                function() order[#order + 1] = "A2" end,
            },
            {
                function() order[#order + 1] = "B1" end,
                function() order[#order + 1] = "B2" end,
            },
            {
                function() order[#order + 1] = "C1" end,
                function() order[#order + 1] = "C2" end,
            },
        }

        assert_order(order, {
            "A1", "B1", "C1",
            "A1", "B1", "C2",
            "A1", "B2", "C1",
            "A1", "B2", "C2",
            "A2", "B1", "C1",
            "A2", "B1", "C2",
            "A2", "B2", "C1",
            "A2", "B2", "C2",
        })
    end)

    it("should no-op for empty input or empty dimensions", function()
        local count = 0

        Cross.product_call {}
        Cross.product_call {
            {
                function() count = count + 1 end,
            },
            {},
        }

        assert(count == 0, "expected no executions, got " .. count)
    end)

    it("should execute single dimension entries", function()
        local order = {}

        Cross.product_call {
            {
                function() order[#order + 1] = "A1" end,
                function() order[#order + 1] = "A2" end,
                function() order[#order + 1] = "A3" end,
            },
        }

        assert_order(order, { "A1", "A2", "A3" })
    end)

    it("should execute sequential function blocks", function()
        local order = {}
        local function mark(name)
            return function() order[#order + 1] = name end
        end

        Cross.product_call {
            {
                { mark("a"), mark("b") },
                mark("c"),
            },
            {
                mark("d"),
                { mark("e"), mark("f") },
            },
        }

        assert_order(order, { "a", "b", "d", "a", "b", "e", "f", "c", "d", "c", "e", "f" })
    end)

    it("should execute argument blocks, multi-argument blocks, and hooks", function()
        local order = {}
        local function mark(name)
            order[#order + 1] = name
        end

        Cross.product_call {
            {
                {
                    before = function() mark("before_a") end,
                    func = function(a, b) mark("a" .. (a + b)) end,
                    args = { 1, 2 },
                    after = function() mark("after_a") end,
                },
                {
                    before = function() mark("before_b") end,
                    func = function(v) mark("b" .. v) end,
                    multi_args = { { 1 }, { 2 } },
                    after = function() mark("after_b") end,
                },
            },
            {
                function() mark("tail") end,
            },
        }

        assert_order(order, {
            "before_a", "a3", "after_a", "tail",
            "before_b", "b1", "after_b", "before_b", "b2", "after_b", "tail",
        })
    end)

    it("should execute up to 8 arguments without table.unpack", function()
        local sum = 0

        Cross.product_call {
            {
                {
                    func = function(a1, a2, a3, a4, a5, a6, a7, a8)
                        sum = a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8
                    end,
                    args = { 1, 2, 3, 4, 5, 6, 7, 8 },
                },
            },
        }

        assert(sum == 36, "expected sum 36, got " .. sum)
    end)

    it("should report explicit error when argument blocks exceed 8 arguments", function()
        local ok, err = pcall(function()
            Cross.product_call {
                {
                    {
                        func = function() end,
                        args = { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
                    },
                },
            }
        end)

        assert(not ok, "expected product_call to reject more than 8 args")
        assert(tostring(err):find("exceeds supported maximum 8"), "unexpected error: " .. tostring(err))
    end)
end)

-- Hardware verification scenario tests
describe("Cross hardware verification scenarios", function()
    it("should generate signal cross product for AXI-like bus", function()
        local addr = { 0x00, 0x04, 0x08, 0x0C }
        local size = { 1, 2, 4 }
        local burst = { "FIXED", "INCR", "WRAP" }

        local result = Cross.product_table({ addr, size, burst })
        assert(#result == 4 * 3 * 3, "expected 36, got " .. #result)
    end)

    it("should filter illegal combinations", function()
        local addr = { 0x00, 0x04, 0x08 }
        local size = { 1, 2, 4 }

        -- Constraint: addr must be aligned to size
        local result = Cross.product_table({ addr, size }, {
            filter = function(c)
                return c[1] % c[2] == 0
            end,
        })

        for _, combo in ipairs(result) do
            assert(combo[1] % combo[2] == 0, "alignment violated")
        end
    end)

    it("should sample from large space efficiently", function()
        math.randomseed(99)
        -- 10 x 10 x 10 x 10 = 10000 combinations
        local lists = {}
        for i = 1, 4 do
            lists[i] = {}
            for j = 1, 10 do
                lists[i][j] = j
            end
        end

        local result = Cross.product_table(lists, { sample = 50, unique = true })
        assert(#result == 50)
    end)
end)

describe("Cross opts.max_attempts", function()
    it("should respect user-provided max_attempts", function()
        math.randomseed(42)
        local ok, err = pcall(function()
            Cross.product_table({ { 1, 2 }, { 3, 4 } }, {
                sample = 1,
                max_attempts = 10,
                filter = function() return false end,
            })
        end)
        assert(not ok)
        assert(tostring(err):find("10"), "expected 10 in error: " .. tostring(err))
    end)

    it("should use default when max_attempts not set", function()
        math.randomseed(42)
        local ok, err = pcall(function()
            Cross.product_table({ { 1, 2 }, { 3, 4 } }, {
                sample = 5,
                filter = function() return false end,
            })
        end)
        assert(not ok)
        -- default is sample * 100 = 500
        assert(tostring(err):find("500"), "expected 500 in error: " .. tostring(err))
    end)
end)

--- Combinatorics utilities for hardware verification.
-- Provides cartesian product, permutations, and combinations with
-- optional constraint filtering, weighted random sampling, and uniqueness.
--
-- Usage:
--
--   local cross = require("verilua.Cross")
--
--   -- Cartesian product of signal value domains
--   for combo in cross.product_iter({ {0x00, 0x04, 0x08}, {1, 2, 4} }) do
--       local addr, size = combo[1], combo[2]
--   end
--
--   -- Random sampling with constraint filtering
--   local samples = cross.product_table(
--       { {0x00, 0x04, 0x08}, {1, 2, 4}, {"FIXED", "INCR"} },
--       { sample = 10, unique = true, filter = function(c) return c[1] % c[2] == 0 end }
--   )
--

local random = math.random
local floor = math.floor
local insert = table.insert
local type = type
local assert = assert
local error = error
local tostring = tostring

---@class verilua.Cross.Options
---@field filter? fun(combo: any[]): boolean Filter function, return true to keep
---@field sample? integer Number of random samples to draw
---@field weights? number[][] Per-list weight arrays for biased sampling
---@field unique? boolean Ensure sampled results are unique (default: false)
---@field max_attempts? integer Maximum sampling attempts before error (default: sample * 100)

---@class verilua.Cross
local Cross = {}

-- ============================================================================
-- Internal helpers
-- ============================================================================

--- Shallow copy a table (array portion).
---@param t any[]
---@return any[]
local function array_copy(t)
    local out = {}
    for i = 1, #t do
        out[i] = t[i]
    end
    return out
end

--- Build a string key for a single value.
--- Includes the Lua type to avoid collisions such as 1 vs "1".
---@param value any
---@return string
local function value_key(value)
    local s = tostring(value)
    return type(value) .. ":" .. #s .. ":" .. s
end

--- Build a string key for a combo (ordered tuple).
--- Uses length-prefixed encoding to avoid separator collisions.
---@param combo any[]
---@return string
local function tuple_key(combo)
    local n = #combo
    if n == 0 then return "" end
    local key = value_key(combo[1])
    for i = 2, n do
        key = key .. "|" .. value_key(combo[i])
    end
    return key
end

--- Build a string key for a combo (unordered set).
--- Uses insertion sort (faster than table.sort for small n, and avoids NYI).
---@param combo any[]
---@return string
local function set_key(combo)
    local n = #combo
    if n == 0 then return "" end
    -- Convert to typed strings and insertion-sort in place (small n, avoids table.sort NYI)
    local strs = {} ---@type string[]
    for i = 1, n do
        strs[i] = value_key(combo[i])
    end
    for i = 2, n do
        local val = strs[i]
        local j = i - 1
        while j >= 1 and strs[j] > val do
            strs[j + 1] = strs[j]
            j = j - 1
        end
        strs[j + 1] = val
    end
    local key = strs[1]
    for i = 2, n do
        key = key .. "|" .. strs[i]
    end
    return key --[[@as string]]
end

--- Weighted random index selection for a single list.
--- weights[i] is the relative weight for element i.
---@param weights number[]
---@return integer
local function weighted_pick(weights)
    local total = 0.0
    for i = 1, #weights do
        assert(weights[i] >= 0, "weighted_pick: negative weight at index " .. i)
        total = total + weights[i]
    end
    assert(total > 0, "weighted_pick: all weights are zero")
    local r = random() * total
    local cumulative = 0.0
    for i = 1, #weights do
        cumulative = cumulative + weights[i]
        if r < cumulative then
            return i
        end
    end
    -- Fallback for floating-point edge case (r == total)
    return #weights
end

--- Uniform random index for a list of given size.
---@param size integer
---@return integer
local function uniform_pick(size)
    return random(1, size)
end

-- ============================================================================
-- Cartesian Product
-- ============================================================================

--- Iterator over the cartesian product of multiple lists.
--- Each iteration yields a table representing one combination (ordered tuple).
--- The same table is reused across iterations for performance; copy if needed.
---
--- Example:
---   local addr = {0x00, 0x04, 0x08}
---   local size = {1, 2, 4}
---   for combo in Cross.product_iter({addr, size}) do
---       print(combo[1], combo[2])  -- 0x00,1 / 0x00,2 / ... / 0x08,4
---   end
---
---   -- With filter: only aligned combinations
---   for combo in Cross.product_iter({addr, size}, {
---       filter = function(c) return c[1] % c[2] == 0 end
---   }) do
---       -- addr is always aligned to size here
---   end
---
---@param lists any[][] Array of lists to combine
---@param opts? verilua.Cross.Options
---@return fun(): any[]|nil
function Cross.product_iter(lists, opts)
    assert(type(lists) == "table", "product_iter: lists must be a table")
    local n = #lists
    if n == 0 then
        return function() return nil end
    end

    local filter = opts and opts.filter
    local sizes = {} ---@type integer[]
    for i = 1, n do
        assert(type(lists[i]) == "table", "product_iter: lists[" .. i .. "] must be a table")
        local list = lists[i] ---@diagnostic disable-line: assign-type-mismatch
        sizes[i] = #list
        assert(sizes[i] > 0, "product_iter: list " .. i .. " is empty")
    end

    local indices = {}
    for i = 1, n do
        indices[i] = 1
    end

    local combo = {}
    local done = false

    return function()
        while not done do
            -- Build current combo
            for i = 1, n do
                local list = lists[i] ---@diagnostic disable-line: assign-type-mismatch
                combo[i] = list[indices[i]] ---@diagnostic disable-line: undefined-field, need-check-nil
            end

            -- Advance indices (odometer style, rightmost increments first)
            local carry = true
            for i = n, 1, -1 do
                if carry then
                    indices[i] = indices[i] + 1
                    if indices[i] > sizes[i] then
                        indices[i] = 1
                    else
                        carry = false
                    end
                end
            end
            if carry then
                done = true
            end

            -- Apply filter
            if filter then
                if filter(combo) then
                    return combo
                end
            else
                return combo
            end
        end
        return nil
    end
end

--- Return a table containing all cartesian product combinations.
---
--- Example:
---   -- All combinations
---   local all = Cross.product_table({ {1,2}, {"a","b"} })
---   -- => {{1,"a"}, {1,"b"}, {2,"a"}, {2,"b"}}
---
---   -- Random sampling with weights (bias toward boundary values)
---   local samples = Cross.product_table(
---       { {0x00, 0x04, 0xFF}, {1, 2, 4} },
---       { sample = 20, unique = true, weights = { {10, 1, 10}, {1, 1, 1} } }
---   )
---
---@param lists any[][] Array of lists to combine
---@param opts? verilua.Cross.Options
---@return any[][]
function Cross.product_table(lists, opts)
    local sample = opts and opts.sample
    if sample then
        return Cross._sample_product(lists, opts --[[@as verilua.Cross.Options]])
    end

    local result = {}
    for combo in Cross.product_iter(lists, opts) do
        insert(result, array_copy(combo))
    end
    return result
end

--- Internal: random sampling from cartesian product space.
---@private
---@param lists any[][]
---@param opts verilua.Cross.Options
---@return any[][]
function Cross._sample_product(lists, opts)
    assert(type(lists) == "table", "_sample_product: lists must be a table")
    local n = #lists
    local sample = opts.sample
    local filter = opts.filter
    local weights = opts.weights
    local unique = opts.unique or false

    assert(type(sample) == "number" and sample > 0 and floor(sample) == sample, "sample must be a positive integer")

    -- Consistent with product_iter: empty input yields nothing.
    if n == 0 then
        error("_sample_product: input lists is empty, no product combinations to sample")
    end

    for i = 1, n do
        assert(type(lists[i]) == "table", "_sample_product: lists[" .. i .. "] must be a table")
        assert(#lists[i] > 0, "_sample_product: list " .. i .. " is empty")
    end

    -- Validate weights dimensions
    if weights then
        for i = 1, n do
            if weights[i] then
                assert(
                    #weights[i] == #lists[i],
                    "weights[" .. i .. "] length (" .. #weights[i] .. ") must match lists[" .. i .. "] length (" .. #lists[i] .. ")"
                )
            end
        end
    end

    -- Compute total space size (for unique validation)
    local total_space = 1
    for i = 1, n do
        total_space = total_space * #lists[i]
    end

    if unique and sample > total_space then
        error("sample (" .. sample .. ") exceeds total combination space (" .. total_space .. ")")
    end

    local results = {}
    local seen = {}
    local attempts = 0
    local max_attempts = opts.max_attempts or (sample * 100)

    while #results < sample do
        attempts = attempts + 1
        if attempts > max_attempts then
            error("Cross.product_table: exceeded max attempts (" .. max_attempts ..
                ") to find " .. sample .. " unique samples")
        end

        -- Generate one random combo
        local combo = {}
        for i = 1, n do
            local list = lists[i] ---@diagnostic disable-line: assign-type-mismatch
            local idx
            if weights and weights[i] then
                idx = weighted_pick(weights[i])
            else
                idx = uniform_pick(#list)
            end
            combo[i] = list[idx] ---@diagnostic disable-line: need-check-nil
        end

        -- Apply filter
        local pass = true
        if filter then
            pass = filter(combo)
        end

        if pass then
            if unique then
                local key = tuple_key(combo)
                if not seen[key] then
                    seen[key] = true
                    insert(results, combo)
                end
            else
                insert(results, combo)
            end
        end
    end

    return results
end

-- ============================================================================
-- Permutations
-- ============================================================================

--- Iterator over all permutations of a list (n! total).
--- The same table is reused across iterations for performance; copy if needed.
---
--- Example:
---   for perm in Cross.permutations_iter({1, 2, 3}) do
---       print(perm[1], perm[2], perm[3])
---   end
---   -- Output (6 permutations): 1,2,3 / 2,1,3 / 3,1,2 / 1,3,2 / 2,3,1 / 3,2,1
---
---   -- Only permutations starting with 1
---   for perm in Cross.permutations_iter({1, 2, 3}, {
---       filter = function(p) return p[1] == 1 end
---   }) do
---       -- {1,2,3} and {1,3,2}
---   end
---
---@param a any[] Input list
---@param opts? verilua.Cross.Options
---@return fun(): any[]|nil
function Cross.permutations_iter(a, opts)
    assert(type(a) == "table", "permutations_iter: input must be a table")
    local n = #a
    if n == 0 then
        return function() return nil end
    end

    local filter = opts and opts.filter

    -- Heap's algorithm (iterative, 0-indexed i and c)
    local arr = array_copy(a)
    local c = {} ---@type table<integer, integer>
    for idx = 0, n - 1 do
        c[idx] = 0
    end
    local i = 0
    local first = true

    return function()
        if first then
            first = false
            if filter then
                if filter(arr) then return arr end
            else
                return arr
            end
        end

        while i < n do
            if c[i] < i then
                if i % 2 == 0 then
                    arr[1], arr[i + 1] = arr[i + 1], arr[1]
                else
                    local ci = c[i] + 1
                    arr[ci], arr[i + 1] = arr[i + 1], arr[ci]
                end
                c[i] = c[i] + 1
                i = 0

                if filter then
                    if filter(arr) then return arr end
                else
                    return arr
                end
            else
                c[i] = 0
                i = i + 1
            end
        end

        return nil
    end
end

--- Return a table containing all permutations of a list.
---
--- Example:
---   local all = Cross.permutations_table({1, 2, 3})
---   -- => 6 permutations
---
---   -- Sample 3 unique random permutations from {1,2,3,4}
---   local samples = Cross.permutations_table({1, 2, 3, 4}, { sample = 3, unique = true })
---
---@param a any[] Input list
---@param opts? verilua.Cross.Options
---@return any[][]
function Cross.permutations_table(a, opts)
    assert(type(a) == "table", "permutations_table: input must be a table")
    local sample = opts and opts.sample
    if sample then
        return Cross._sample_permutations(a, opts --[[@as verilua.Cross.Options]])
    end

    local result = {}
    for perm in Cross.permutations_iter(a, opts) do
        insert(result, array_copy(perm))
    end
    return result
end

--- Internal: random sampling from permutation space.
---@private
---@param a any[]
---@param opts verilua.Cross.Options
---@return any[][]
function Cross._sample_permutations(a, opts)
    local n = #a
    local sample = opts.sample
    local filter = opts.filter
    local unique = opts.unique or false

    assert(type(sample) == "number" and sample > 0 and floor(sample) == sample, "sample must be a positive integer")

    -- Consistent with permutations_iter: empty input yields nothing
    if n == 0 then
        error("_sample_permutations: input list is empty, no permutations to sample")
    end

    -- Compute n!
    local factorial = 1
    for i = 2, n do
        factorial = factorial * i
    end

    if unique and sample > factorial then
        error("sample (" .. sample .. ") exceeds total permutation count (" .. factorial .. ")")
    end

    local results = {}
    local seen = {}
    local attempts = 0
    local max_attempts = opts.max_attempts or (sample * 100)

    while #results < sample do
        attempts = attempts + 1
        if attempts > max_attempts then
            error("Cross.permutations_table: exceeded max attempts (" .. max_attempts ..
                ") to find " .. sample .. " unique samples")
        end

        -- Fisher-Yates shuffle to generate random permutation
        local perm = array_copy(a)
        for i = n, 2, -1 do
            local j = random(1, i)
            perm[i], perm[j] = perm[j], perm[i]
        end

        local pass = true
        if filter then
            pass = filter(perm)
        end

        if pass then
            if unique then
                local key = tuple_key(perm)
                if not seen[key] then
                    seen[key] = true
                    insert(results, perm)
                end
            else
                insert(results, perm)
            end
        end
    end

    return results
end

-- ============================================================================
-- Combinations C(n, k)
-- ============================================================================

--- Iterator over all combinations of k elements from a list.
--- Each iteration yields a table of k elements. The same table is reused.
---
--- Example:
---   -- C(5,2) = 10 combinations
---   for combo in Cross.combinations_iter({1, 2, 3, 4, 5}, 2) do
---       print(combo[1], combo[2])  -- 1,2 / 1,3 / ... / 4,5
---   end
---
---   -- Only pairs whose sum > 5
---   for combo in Cross.combinations_iter({1, 2, 3, 4, 5}, 2, {
---       filter = function(c) return c[1] + c[2] > 5 end
---   }) do
---       -- {1,5}, {2,4}, {2,5}, {3,4}, {3,5}, {4,5}
---   end
---
---@param a any[] Input list
---@param k integer Number of elements to choose
---@param opts? verilua.Cross.Options
---@return fun(): any[]|nil
function Cross.combinations_iter(a, k, opts)
    assert(type(a) == "table", "combinations_iter: input must be a table")
    assert(type(k) == "number" and k >= 0 and floor(k) == k, "combinations_iter: k must be a non-negative integer")
    local n = #a
    assert(k <= n, "combinations_iter: k (" .. k .. ") > n (" .. n .. ")")

    local filter = opts and opts.filter

    if k == 0 then
        local yielded = false
        local combo = {}
        return function()
            if not yielded then
                yielded = true
                if not filter or filter(combo) then
                    return combo
                end
            end
            return nil
        end
    end

    -- Initialize indices
    local indices = {}
    for i = 1, k do
        indices[i] = i
    end

    local combo = {}
    local first = true

    return function()
        while true do
            if first then
                first = false
            else
                -- Find rightmost index that can be incremented
                local i = k
                while i >= 1 and indices[i] == n - k + i do
                    i = i - 1
                end
                if i < 1 then
                    return nil
                end
                indices[i] = indices[i] + 1
                for j = i + 1, k do
                    indices[j] = indices[j - 1] + 1
                end
            end

            -- Build combo
            for i = 1, k do
                combo[i] = a[indices[i]] ---@diagnostic disable-line: undefined-field
            end

            if filter then
                if filter(combo) then return combo end
            else
                return combo
            end
        end
    end
end

--- Return a table containing all combinations of k elements from a list.
---
--- Example:
---   local all = Cross.combinations_table({1, 2, 3, 4}, 2)
---   -- => {{1,2}, {1,3}, {1,4}, {2,3}, {2,4}, {3,4}}
---
---   -- Sample 5 unique random combinations from C(10,3)
---   local samples = Cross.combinations_table(
---       {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, 3,
---       { sample = 5, unique = true }
---   )
---
---@param a any[] Input list
---@param k integer Number of elements to choose
---@param opts? verilua.Cross.Options
---@return any[][]
function Cross.combinations_table(a, k, opts)
    assert(type(a) == "table", "combinations_table: input must be a table")
    assert(type(k) == "number" and k >= 0 and floor(k) == k, "combinations_table: k must be a non-negative integer")
    assert(k <= #a, "combinations_table: k (" .. k .. ") > n (" .. #a .. ")")
    local sample = opts and opts.sample
    if sample then
        return Cross._sample_combinations(a, k, opts --[[@as verilua.Cross.Options]])
    end

    local result = {}
    for combo in Cross.combinations_iter(a, k, opts) do
        insert(result, array_copy(combo))
    end
    return result
end

--- Internal: random sampling from combination space.
---@private
---@param a any[]
---@param k integer
---@param opts verilua.Cross.Options
---@return any[][]
function Cross._sample_combinations(a, k, opts)
    local n = #a
    local sample = opts.sample
    local filter = opts.filter
    local unique = opts.unique or false

    assert(type(sample) == "number" and sample > 0 and floor(sample) == sample, "sample must be a positive integer")
    assert(k <= n, "_sample_combinations: k (" .. k .. ") > n (" .. n .. ")")

    -- Compute C(n, k)
    local total = 1.0
    for i = 1, k do
        total = total * (n - k + i) / i
    end
    total = floor(total + 0.5) ---@type integer -- round to integer

    if unique and sample > total then
        error("sample (" .. sample .. ") exceeds total combination count (" .. total .. ")")
    end

    local results = {}
    local seen = {}
    local attempts = 0
    local max_attempts = opts.max_attempts or (sample * 100)

    while #results < sample do
        attempts = attempts + 1
        if attempts > max_attempts then
            error("Cross.combinations_table: exceeded max attempts (" .. max_attempts ..
                ") to find " .. sample .. " unique samples")
        end

        -- Generate random combination via Fisher-Yates partial shuffle.
        -- This is O(k) for k <= n/2, or O(n-k) when using the complement strategy.
        local combo_indices = {}
        local use_complement = k > n / 2
        local pick_count = use_complement and (n - k) or k

        -- Fisher-Yates partial shuffle: pick pick_count indices from 1..n
        local pool = {} ---@type integer[]
        for i = 1, n do
            pool[i] = i
        end
        for i = 1, pick_count do
            local j = random(i, n)
            pool[i], pool[j] = pool[j], pool[i]
        end

        if use_complement then
            -- We picked (n-k) indices to EXCLUDE; the rest are our combination
            local excluded = {}
            for i = 1, pick_count do
                excluded[pool[i]] = true
            end
            local ci = 0
            for i = 1, n do
                if not excluded[i] then
                    ci = ci + 1
                    combo_indices[ci] = i
                end
            end
        else
            -- Collect picked indices and sort them
            for i = 1, pick_count do
                combo_indices[i] = pool[i]
            end
            -- Insertion sort (small pick_count, avoids table.sort NYI)
            for si = 2, pick_count do
                local val = combo_indices[si]
                local sj = si - 1
                while sj >= 1 and combo_indices[sj] > val do
                    combo_indices[sj + 1] = combo_indices[sj]
                    sj = sj - 1
                end
                combo_indices[sj + 1] = val
            end
        end

        -- Build combo from sorted indices
        local combo = {}
        for ci = 1, k do
            combo[ci] = a[combo_indices[ci]] ---@diagnostic disable-line: undefined-field
        end

        local pass = true
        if filter then
            pass = filter(combo)
        end

        if pass then
            if unique then
                local key = set_key(combo)
                if not seen[key] then
                    seen[key] = true
                    insert(results, combo)
                end
            else
                insert(results, combo)
            end
        end
    end

    return results
end

return Cross

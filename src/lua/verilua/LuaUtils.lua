local io = require "io"
local os = require "os"
local bit = require "bit"
local ffi = require "ffi"
local math = require "math"
local path = require "pl.path"
local table_new = require "table.new"

local type = type
local next = next
local pairs = pairs
local print = print
local error = error
local string = string
local ipairs = ipairs
local assert = assert
local rawset = rawset
local f = string.format
local tonumber = tonumber
local tostring = tostring
local bit_bnot = bit.bnot
local bit_band = bit.band
local math_ceil = math.ceil
local bit_tohex = bit.tohex
local bit_rshift = bit.rshift
local bit_lshift = bit.lshift
local math_floor = math.floor
local ffi_istype = ffi.istype
local math_random = math.random
local table_insert = table.insert
local table_concat = table.concat
local setmetatable = setmetatable

local utils = {}
local this = utils

---@param t table The table to be serialized
---@param conn string The connector for the serialization, defaults to "_"
---@return string The serialized string
function utils.serialize(t, conn)
    local serialized = t
    local conn = conn or "_"
    -- for k, v in pairs(t) do
    --     table.insert(serialized, tostring(k) .. "=" .. tostring(v))
    -- end
    -- table.sort(serialized)
    return table_concat(serialized, conn)
end

---@param tab table<any> The table to be reversed
---@return table<any> The reversed table
function utils.reverse_table(tab)
    local size = #tab
    local new_tab = table_new(size, 0)

    for i, v in ipairs(tab) do
        new_tab[size - i + 1] = v
    end

    return new_tab
end

do
    local function get_result(t_len, t, separator)
        local t_copy = table_new(t_len, 0)

        if t_len == 1 then
            t_copy[1] = bit_tohex(t[1])
        else
            for i = 1, t_len do
                t_copy[t_len - i + 1] = bit_tohex(t[i])
            end
        end

        return table_concat(t_copy, separator)
    end

    ---@param t number|ffi.cdata*|table The value to be converted to hexadecimal string
    ---@param separator? string The separator for the hexadecimal string, defaults to ""
    ---@return string -- The hexadecimal string, MSB <=> LSB
    function utils.to_hex_str(t, separator)
        local separator = separator or ""
        local result = ""
        local t_len = 0
        local t_type = type(t)

        if t_type == "number" then
            result = f("%x", t)
        elseif t_type == "cdata" then
            if ffi_istype("uint64_t", t) then
                result = bit_tohex(t)
            else
                -- 
                -- if <t> is a LuaBundle multibeat data, then <t[0]> (type of <t> is uint64_t or cdata in LuaJIT) is the beat len of the multibeat data(i.e. beat len).
                -- Otherwise, if <t> is a normal cdata, there is no such concept of beat len, hence t_len == 1
                -- 
                t_len = t[0]
                result = get_result(t_len, t, separator)
            end
        else
            if t_type ~= "table" then
                assert(false, f("Invalid type: %s", t_type))
            end
            
            t_len = #t

            result = get_result(t_len, t, separator)
        end

        return result
    end
end

---@param n number The value to calculate the logarithm base 2
---@return number The ceiling of the logarithm base 2
function utils.log2Ceil(n)
    if n < 1 then
        return 0
    else
        local log_val = math.log(n) / math.log(2)
        local ceil_val = math_ceil(log_val)
        return ceil_val
    end
end

---@param begin number The start bit
---@param endd number The end bit
---@param val number The value to be processed
---@return number The processed value
function utils.bitfield32(begin, endd, val)
    local mask = bit_lshift(1ULL, endd - begin + 1) - 1
    return tonumber(bit.band(bit_rshift(val + 0ULL, begin), mask)) --[[@as number]]
end

---@param begin number The start bit
---@param endd number The end bit
---@param val number The value to be processed
---@return number The processed value
function utils.bitfield64(begin, endd, val)
    return bit_rshift( bit_lshift(val + 0ULL, 64 - endd - 1), begin + 64- endd - 1 )
end

---@param hi number The higher 32 bits
---@param lo number The lower 32 bits
---@return number The combined 64-bit value
function utils.to64bit(hi, lo)
    return bit_lshift(hi, 32) + lo
end

-- 
-- LSB <==> MSB
--
---@param hex_table number|table The value or table to be converted to hexadecimal
---@return string The hexadecimal string
function utils.to_hex(hex_table)
    local ret = ""
    if type(hex_table) == "table" then
        for index, value in ipairs(hex_table) do
            ret = ret .. f("%x ", value)
        end
    else
        ret = ret .. f("%x", hex_table)
    end
    return ret
end

---@param hex_table number|table The value or table to be printed as hexadecimal
function utils.print_hex(hex_table)
    io.write(this.to_hex(hex_table).."\n")
end

---@param num number The number to be converted to binary string
---@return string The binary string
function utils.num_to_binstr(num)
    local num = tonumber(num)
    if num == 0 then return "0" end
    local binstr = ""
    while num > 0 do
        local bit = num % 2
        binstr = tostring(bit) .. binstr
        num = math_floor(num / 2)
    end
    return binstr
end

---@param progress number The progress, ranges from (0, 1)
---@param length number The length of the progress bar
---@return string The string representation of the progress bar
function utils.get_progress_bar(progress, length)
    -- https://cn.piliapp.com/symbol/
    local completed = math_floor(progress * length)
    local remaining = length - completed
    local progressBar = "┃" .. string.rep("█", completed) .. "▉" .. string.rep(" ", remaining) .. "┃"
    return progressBar
end

---@param progress number The progress, ranges from (0, 1)
---@param length number The length of the progress bar
function utils.print_progress_bar(progress, length)
    print(utils.get_progress_bar(progress, length))
end


-- 
-- Usage Example:
--   Direction = setmetatable({
--       name = "Direction",
--       INPUT = 0,
--       OUTPUT = 1
--   }, { __call = utils.enum_search })
-- 
---@param t table The enumeration table
---@param v number The value to be searched
---@return string The found key name, or throws an error if not found
function utils.enum_search(t, v)
    for name, value in pairs(t) do
        if value == v then
            return name
        end
    end

    ---@diagnostic disable-next-line: missing-return
    assert(false, "Key no found: " .. v .. " in " .. t.name)
end


-- 
-- Usage Example:
--      local State = utils.enum_define({
--            name = "State",
-- 
--            RUN = 1,
--            STOP = 2,
--            RUNNING = 3,
--      })
--      local state_value = State.RUN
--      print("current state is " .. State(state_value)) -- print: current state is RUN
-- 
--      local State = utils.enum_define {
--            name = "State",
--
--            RUN = 1,
--            STOP = 2,
--            RUNNING = 3,
--      }
-- 
---@generic T: table
---@param enum_table T The enumeration table to be defined
---@return T The defined enumeration table
function utils.enum_define(enum_table)
    assert(type(enum_table) == "table")

    if enum_table.name == nil then
        enum_table.name = "Undefined"
    end

    enum_table.__reverse__ = {}
    for k, v in pairs(enum_table) do
        if k ~= "name" then
            local rev = enum_table.__reverse__[v]
            assert(rev == nil or rev ~= k, f("Duplicate value: %s in %s", v, enum_table.name))
            rawset(enum_table.__reverse__, v, k)
        end
    end

    return setmetatable(enum_table, {
        __call = function(t, v)
            local key = t.__reverse__[v]
            if key == nil then
                error("Key not found: " .. v .. " in " .. t.name)
            end
            return key
        end,

        __index = function(t, v)
            assert(false, f("Unknown enum value => %s  enum name => %s", tostring(v), t.name))
        end,

        __newindex = function(t, k, v)
            rawset(t, k, v)
            rawset(t.__reverse__, v, k)
        end,

        __pairs = function(t)
            return function(_, k)
                k = next(t, k)
                while k do
                    if k ~= "name" and k ~= "__reverse__" then
                        return k, t[k]
                    end
                    k = next(t, k)
                end
            end, nil
        end,
    })
end


-- 
-- format: <Year><Month><Day>_<Hour><Minute>
-- Example:
--   local str = utils.get_datetime_str()
--         str == "20240124_2301" 
-- 
---@return string|osdate The string representation of the current date and time in the format <Year><Month><Day>_<Hour><Minute>
function utils.get_datetime_str()
    local datetime = os.date("%Y%m%d_%H%M")
    return datetime
end

---@param filename string The file name to be read
---@return string The content of the file
function utils.read_file_str(filename)
    local file = io.open(path.abspath(filename), "r") 
    if not file then
        assert(false, "cannot open " .. path.abspath(filename))
    end
    ---@diagnostic disable-next-line: need-check-nil
    local content = file:read("*a")

    ---@diagnostic disable-next-line: need-check-nil
    file:close()

    return content
end


local function dec_to_bin(dec)
    local num = tonumber(dec)
    if not num then
        error("Invalid decimal number.")
    end
    local bin = ""
    repeat
        local rem = num % 2
        bin = rem .. bin
        num = math_floor(num / 2)
    until num == 0
    return bin
end


local function hex_to_bin(hex)
    local bin = ""
    local hex_to_bin_map = {
        ["0"] = "0000", ["1"] = "0001", ["2"] = "0010", ["3"] = "0011",
        ["4"] = "0100", ["5"] = "0101", ["6"] = "0110", ["7"] = "0111",
        ["8"] = "1000", ["9"] = "1001", ["A"] = "1010", ["B"] = "1011",
        ["C"] = "1100", ["D"] = "1101", ["E"] = "1110", ["F"] = "1111",
        ["a"] = "1010", ["b"] = "1011", ["c"] = "1100", ["d"] = "1101",
        ["e"] = "1110", ["f"] = "1111"
    }
    for i = 3, #hex do
        local nibble = hex:sub(i, i)
        bin = bin .. (hex_to_bin_map[nibble] or error("Invalid hex character: " .. nibble))
    end
    return bin
end

---@param str string The input string (binary starts with "0b", hexadecimal starts with "0x", decimal has no prefix)
---@param s number The start bit
---@param e number The end bit
---@param width number The width of the input string (optional)
---@return string The binary string
function utils.bitfield_str(str, s, e, width)
    local prefix = str:sub(1, 2)
    local bin_str

    if prefix == "0x" then
        bin_str = hex_to_bin(str:gsub(" ", ""):gsub("_", ""))
    elseif prefix == "0b" then
        bin_str = str:gsub(" ", ""):gsub("_", ""):sub(3)
    else
        bin_str = dec_to_bin(str:gsub(" ", ""):gsub("_", ""))
    end

    -- Ensure the binary string meets the desired width by padding with leading zeros
    if width and width > #bin_str then
        bin_str = string.rep("0", width - #bin_str) .. bin_str
    end

    local len = #bin_str
    if s < 0 or e < 0 or s > len or e > len or s > e then
        error(f("Invalid bitfield range. s:%d, e:%d, len:%d", s, e, len))
    end

    local ret = bin_str:sub(len - e, len - s)
    return ret == "" and "0" or ret
end

---@param bitpat_tbl table<number, {s: number, e: number, v: number|uint64_t}> The bit pattern table
---@param width number The width of the bit pattern (optional)
---@return string The hexadecimal string
function utils.bitpat_to_hexstr(bitpat_tbl, width)
    assert(type(bitpat_tbl) == "table", "bitpat_tbl must be a table")
    assert(type(bitpat_tbl[1]) == "table", "bitpat_tbl must contain tables")
    if width ~= nil then
        assert(type(width) == "number" and width > 0, "width must be a positive number")
    else
        width = 64 
    end

    -- Calculate the number of 64-bit blocks required to handle the specified width
    local num_blocks = math_ceil(width / 64)

    -- Initialize the value as a table of zeros (each element represents a 64-bit block)
    local v = table_new(num_blocks, 0)
    for i = 1, num_blocks do
        v[i] = 0ULL
    end

    for i, bitpat in ipairs(bitpat_tbl) do
        assert(bitpat.s ~= nil, "bitpat.s is required")
        assert(bitpat.e ~= nil, "bitpat.e is required")
        assert(bitpat.v ~= nil, "bitpat.v is required")

        assert(bitpat.s < width)
        assert(bitpat.e < width)

        -- Calculate the number of bits
        local num_bits = bitpat.e - bitpat.s + 1
        assert(num_bits > 0, "bitpat.e must be greater than or equal to bitpat.s")

        -- Calculate the maximum value that can be represented with `num_bits` bits
        local max_val
        if num_bits == 64 then
            max_val = 0xFFFFFFFFFFFFFFFFULL
        else
            max_val = bit_lshift(1ULL, num_bits) - 1
        end
        assert(bitpat.v <= max_val, f("bitpat.v (%d) exceeds the maximum value (%d) for the specified bit range [%d, %d]", bitpat.v, max_val, bitpat.s, bitpat.e))

        -- Determine which block and position within the block to apply the bit pattern
        local start_block = math_floor(bitpat.s / 64) + 1
        local end_block = math_floor(bitpat.e / 64) + 1
        local start_pos = bitpat.s % 64
        local end_pos = bitpat.e % 64

        if start_block == end_block then
            -- The bit pattern fits within a single block
            local mask
            if num_bits == 64 then
                mask = 0xFFFFFFFFFFFFFFFFULL
            else
                mask = bit_lshift(1ULL, num_bits) - 1
            end
            local shifted_value = bit_lshift(bit.band(bitpat.v --[[@as number]], mask), start_pos)
            v[start_block] = bit.bor(v[start_block], shifted_value)
        else
            -- The bit pattern spans across multiple blocks
            local lower_bits = 64 - start_pos
            local upper_bits = num_bits - lower_bits

            -- Lower part in the start block
            local lower_mask = bit_lshift(1ULL, lower_bits) - 1
            local lower_value = bit.band(bitpat.v --[[@as number]], lower_mask)
            v[start_block] = bit.bor(v[start_block], bit_lshift(lower_value, start_pos))

            -- Upper part in the end block
            local upper_value = bit_rshift(bitpat.v --[[@as number]], lower_bits)
            v[end_block] = bit.bor(v[end_block], upper_value)
        end
    end

    -- Convert the result to a hexadecimal string
    local hexstr = ""
    for i = num_blocks, 1, -1 do
        hexstr = hexstr .. bit_tohex(v[i])
    end

    return hexstr
end

---@param uint_value number The unsigned integer value to be converted to one-hot encoding
---@return number The one-hot encoded value
function utils.uint_to_onehot(uint_value)
    return bit_lshift(1, uint_value) + 0ULL
end

---@param t table<any> The table to be shuffled
---@return table The shuffled table
function utils.shuffle(t)
    local n = #t
    local k = 0

    while n >= 2 do
      k = math_random(1, n)
      t[n], t[k] = t[k], t[n]
      n = n - 1
    end
    
    return t
end

do
    local function normalize_hex(hex)
        -- remove prefix and leading zeros and convert to lower case
        return hex:lower():gsub("^0x0*", "0x")
    end

    local function normalize_bin(bin)
        -- remove prefix and leading zeros
        return bin:gsub("^0b0*", "0b")
    end

    local function normalize_dec(decimal)
        -- remove leading zeros
        return decimal:gsub("^0*", "")
    end

    ---@param str1 string The first string to be compared
    ---@param str2 string The second string to be compared
    ---@return boolean Whether the two strings are equal
    -- ! NOTICE: prefix is required, e.g. "0x" for hex, "0b" for binary, "" for decimal
    function utils.compare_value_str(str1, str2)
        if str1:sub(1, 2) == "0x" and str2:sub(1, 2) == "0x" then
            -- process hex strings
            return normalize_hex(str1) == normalize_hex(str2)
        elseif str1:sub(1, 2) == "0b" and str2:sub(1, 2) == "0b" then
            -- process binary strings
            return normalize_bin(str1) == normalize_bin(str2)
        else
            -- process decimal strings
            return normalize_dec(str1) == normalize_dec(str2)
        end
    end
end

---@return uint64_t
function utils.urandom64()
    return (math_random(0, 0xFFFFFFFF) * 0x100000000ULL + math_random(0, 0xFFFFFFFF)) --[[@as uint64_t]]
end

---@param min number|uint64_t
---@param max number|uint64_t
---@return uint64_t
function utils.urandom64_range(min, max)
    local random_value = math_random(0, 0xFFFFFFFF) * 0x100000000ULL + math_random(0, 0xFFFFFFFF)

    local range = 0ULL
    if max == 0xFFFFFFFFFFFFFFFFULL then
        range = 0xFFFFFFFFFFFFFFFFULL
    else
        range = max - min + 1ULL
    end

    local result = min + (random_value % (range))

    return result --[[@as uint64_t]]
end

---@param str string
---@param nr_group number
---@return table<string>, number
function utils.str_group_by(str, nr_group)
    local group_size = math_ceil(#str / nr_group)
    local result = table_new(group_size, 0)
    for i = 1, #str, nr_group do
        local chunk = str:sub(i, i + nr_group - 1)
        table_insert(result, chunk)
    end
    return result, group_size
end

---@param str string
---@param step number
---@param separator string
---@return string
function utils.str_sep(str, step, separator)
    local result = ""
    local separator = separator or " "
    for i = 1, #str, step do
        local chunk = str:sub(i, i + step - 1)
        result = result .. chunk .. separator
    end

    result = result:sub(1, -#separator - 1)
    return result
end

---@param n number
---@return uint64_t
function utils.bitmask(n)
    assert(n <= 64, "n must be less than or equal to 64")
    if n == 64 then
        return (0xFFFFFFFFFFFFFFFFULL) --[[@as uint64_t]]
    else
        return (bit_lshift(1ULL, n) - 1ULL) --[[@as uint64_t]]
    end
end

---@param value number
---@param start number
---@param length number
---@return uint64_t
function utils.reset_bits(value, start, length)
    assert(start < 64)
    assert(length <= 64)
    local mask = bit_lshift(utils.bitmask(length) --[[@as number]], start)
    return bit_band(value, bit_bnot(mask)) --[[@as uint64_t]]
end

---@param value number
---@param n number
---@return number
function utils.cover_with_n(value, n)
    return math_ceil(value / n)
end

---@param bitwidth number
---@return uint64_t
function utils.shuffle_bits(bitwidth)
    assert(bitwidth <= 64, "bitwidth must be less than or equal to 64")
    if bitwidth <= 32 then
        return math_random(0, tonumber(utils.bitmask(bitwidth)) --[[@as number]]) --[[@as uint64_t]]
    else
        return utils.urandom64_range(0, utils.bitmask(bitwidth))
    end
end

---@param bitwidth number
---@return string
function utils.shuffle_bits_hex_str(bitwidth)
    if bitwidth <= 32 then
        return bit_tohex(utils.shuffle_bits(bitwidth) --[[@as number]])
    else
        local u32_chunk = utils.cover_with_n(bitwidth, 32)
        local result = ""
        local total_bits = bitwidth
        for i = 1, u32_chunk do
            if total_bits >= 32 then
                result = bit_tohex(utils.shuffle_bits(32) --[[@as number]]) .. result
            else
                result = bit_tohex(utils.shuffle_bits(total_bits) --[[@as number]]) .. result
            end
            total_bits = total_bits - 32
        end
        return result
    end
end

---@param value_hex_str string
---@param bitwidth number
---@return string
function utils.expand_hex_str(value_hex_str, bitwidth)
    local len = #value_hex_str
    local target_len = utils.cover_with_n(bitwidth, 4)
    return string.rep("0", target_len - len) .. value_hex_str
end

local hex_to_bin_map = {
    ["0"] = "0000", ["1"] = "0001", ["2"] = "0010", ["3"] = "0011",
    ["4"] = "0100", ["5"] = "0101", ["6"] = "0110", ["7"] = "0111",
    ["8"] = "1000", ["9"] = "1001", ["A"] = "1010", ["B"] = "1011",
    ["C"] = "1100", ["D"] = "1101", ["E"] = "1110", ["F"] = "1111",
    ["a"] = "1010", ["b"] = "1011", ["c"] = "1100", ["d"] = "1101",
    ["e"] = "1110", ["f"] = "1111"
}
---@param hex_str string
---@return string
function utils.hex_to_bin(hex_str)
    local bin_parts = table_new(#hex_str, 0)
    for i = 1, #hex_str do
        local nibble = hex_str:sub(i, i)
        bin_parts[i] = (hex_to_bin_map[nibble] or error("Invalid hex character: " .. nibble))
    end
    return table_concat(bin_parts)
end

-- Example usage:
-- 1. Basic matrix call (2D):
--     matrix_call {
--         {
--             function() print("First dimension, option 1") end,
--             function() print("First dimension, option 2") end,
--         },
--         {
--             function() print("Second dimension, option 1") end,
--             function() print("Second dimension, option 2") end,
--         }
--     }
--     This will generate all combinations and execute them:
--     First dimension, option 1 -> Second dimension, option 1
--     First dimension, option 1 -> Second dimension, option 2
--     First dimension, option 2 -> Second dimension, option 1
--     First dimension, option 2 -> Second dimension, option 2
-- 
-- 2. Sequential functions (seq_funcs):
--      matrix_call {
--          {
--              {function() io.write("a") end, function() io.write(" b\n") end}
--          },
--          {
--              function() print("c") end
--          }
--      }
-- 
--      Output:
--      a b
--      c
-- 
-- 3. Single function with arguments (single_func_with_args):
--         matrix_call {
--             {
--                 {func = function(a, b) print("Sum:", a + b) end, args = {2, 3}},
--                 {func = function(a, b) print("Product:", a * b) end, args = {2, 3}},
--             }
--         }
--         Output:
--         Sum: 5
--         Product: 6

---@class matrix_call.single_func: function
---@class matrix_call.seq_funcs: { [number]: function }
---@class matrix_call.single_func_with_args: { func: function, args: table }
---@class matrix_call.func_blocks: { [number]: matrix_call.single_func | matrix_call.seq_funcs | matrix_call.single_func_with_args }
---@class matrix_call.params: { [number]: matrix_call.func_blocks }

---@param func_table matrix_call.params
function utils.matrix_call(func_table)
    local dimensions = #func_table
    local max_indices = {}

    -- Initialize index arrays and maximum index arrays
    for i = 1, dimensions do
        max_indices[i] = #func_table[i]
    end

    -- Recursive function to generate all combinations
    local function generate_combinations(current_dim, combination)
        if current_dim > dimensions then
            -- Execute the current combination of functions
            for i = 1, #combination do
                local dim = combination[i][1]
                local idx = combination[i][2]
                local func_or_funcs = func_table[dim][idx]

                -- Check if it's a table of functions to execute sequentially
                if type(func_or_funcs) == "table" then
                    if #func_or_funcs == 0 then
                       local func = func_or_funcs.func
                       local args = func_or_funcs.args
                       func(table.unpack(args))
                    else
                        for _, func in ipairs(func_or_funcs) do
                            if type(func) == "function" then
                                func()
                            end
                        end
                    end
                -- Or a single function
                elseif type(func_or_funcs) == "function" then
                    func_or_funcs()
                end
            end
            return
        end

        -- For each function in the current dimension
        for i = 1, max_indices[current_dim] do
            -- Create a new combination by copying the current one
            local new_combination = {}
            for j = 1, #combination do
                new_combination[j] = combination[j]
            end
            -- Add the current dimension and index to the combination
            new_combination[#new_combination + 1] = {current_dim, i}
            -- Recursively process the next dimension
            generate_combinations(current_dim + 1, new_combination)
        end
    end

    -- Start generating combinations from the first dimension
    generate_combinations(1, {})
end

return utils
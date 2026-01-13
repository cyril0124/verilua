---@diagnostic disable: unnecessary-assert, unnecessary-if

local io = require "io"
local os = require "os"
local bit = require "bit"
local ffi = require "ffi"
local math = require "math"
local path = require "pl.path"
local table_new = require "table.new"
local logger = require("verilua.utils.Logger").new("verilua.LuaUtils")

local type = type
local next = next
local pairs = pairs
local error = error
local string = string
local ipairs = ipairs
local assert = assert
local rawset = rawset
local f = string.format
local tonumber = tonumber
local tostring = tostring
local math_ceil = math.ceil
local math_floor = math.floor
local ffi_istype = ffi.istype
local math_random = math.random
local table_insert = table.insert
local table_concat = table.concat
local setmetatable = setmetatable

local bit_bor = bit.bor
local bit_bnot = bit.bnot
local bit_band = bit.band
local bit_tohex = bit.tohex
local bit_rshift = bit.rshift
local bit_lshift = bit.lshift

local srep = string.rep
local ssub = string.sub

local bin_to_hex_map = {
    ["0000"] = "0",
    ["0001"] = "1",
    ["0010"] = "2",
    ["0011"] = "3",
    ["0100"] = "4",
    ["0101"] = "5",
    ["0110"] = "6",
    ["0111"] = "7",
    ["1000"] = "8",
    ["1001"] = "9",
    ["1010"] = "a",
    ["1011"] = "b",
    ["1100"] = "c",
    ["1101"] = "d",
    ["1110"] = "e",
    ["1111"] = "f"
}

local hex_to_bin_map = {
    ["0"] = "0000",
    ["1"] = "0001",
    ["2"] = "0010",
    ["3"] = "0011",
    ["4"] = "0100",
    ["5"] = "0101",
    ["6"] = "0110",
    ["7"] = "0111",
    ["8"] = "1000",
    ["9"] = "1001",
    ["A"] = "1010",
    ["B"] = "1011",
    ["C"] = "1100",
    ["D"] = "1101",
    ["E"] = "1110",
    ["F"] = "1111",
    ["a"] = "1010",
    ["b"] = "1011",
    ["c"] = "1100",
    ["d"] = "1101",
    ["e"] = "1110",
    ["f"] = "1111"
}

---@class (exact) verilua.LuaUtils
local utils = {}

---@param t table The table to be serialized
---@param conn? string The connector for the serialization, defaults to "_"
---@return string The serialized string
function utils.serialize(t, conn)
    local serialized = t
    conn = conn or "_"
    -- for k, v in pairs(t) do
    --     table.insert(serialized, tostring(k) .. "=" .. tostring(v))
    -- end
    -- table.sort(serialized)
    return table_concat(serialized, conn)
end

---@nodiscard Return value should not be discarded
---@param tab any[] The table to be reversed
---@return any[] The reversed table
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

    ---@nodiscard Return value should not be discarded
    ---@param t integer|ffi.cdata*|table The value to be converted to hexadecimal string
    ---@param separator? string The separator for the hexadecimal string, defaults to ""
    ---@return string -- The hexadecimal string, MSB <=> LSB
    function utils.to_hex_str(t, separator)
        separator = separator or ""
        local result = ""
        local t_len = 0
        local t_type = type(t)

        if t_type == "number" then
            result = f("%x", t)
        elseif t_type == "cdata" then
            if ffi_istype("uint64_t", t) then
                result = bit_tohex(t --[[@as integer]])
            else
                --
                -- if <t> is a LuaBundle multibeat data, then <t[0]> (type of <t> is uint64_t or cdata in LuaJIT) is the beat len of the multibeat data(i.e. beat len).
                -- Otherwise, if <t> is a normal cdata, there is no such concept of beat len, hence t_len == 1
                --
                t_len = t[0] --[[@as integer]]
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

---@nodiscard Return value should not be discarded
---@param n integer The value to calculate the logarithm base 2
---@return integer The ceiling of the logarithm base 2
function utils.log2Ceil(n)
    if n < 1 then
        return 0
    else
        local log_val = math.log(n) / math.log(2)
        local ceil_val = math_ceil(log_val)
        return ceil_val
    end
end

---@nodiscard Return value should not be discarded
---@param begin integer The start bit
---@param endd integer The end bit
---@param val integer The value to be processed
---@return integer The processed value
function utils.bitfield32(begin, endd, val)
    local mask = bit_lshift(1ULL, endd - begin + 1) - 1
    return tonumber(bit_band(bit_rshift(val + 0ULL, begin), mask)) --[[@as integer]]
end

---@nodiscard Return value should not be discarded
---@param begin integer The start bit
---@param endd integer The end bit
---@param val integer The value to be processed
---@return integer The processed value
function utils.bitfield64(begin, endd, val)
    return bit_rshift(bit_lshift(val + 0ULL, 64 - endd - 1), begin + 64 - endd - 1)
end

---@param hi integer The higher 32 bits
---@param lo integer The lower 32 bits
---@return integer The combined 64-bit value
function utils.to64bit(hi, lo)
    return bit_lshift(hi, 32) + lo
end

--
-- LSB <==> MSB
--
---@nodiscard Return value should not be discarded
---@param hex_table number|table The value or table to be converted to hexadecimal
---@return string The hexadecimal string
function utils.to_hex(hex_table)
    local ret = ""
    if type(hex_table) == "table" then
        for _index, value in ipairs(hex_table) do
            ret = ret .. f("%x ", value)
        end
    else
        ret = ret .. f("%x", hex_table)
    end
    return ret
end

---@param hex_table number|table The value or table to be printed as hexadecimal
function utils.print_hex(hex_table)
    io.write(utils.to_hex(hex_table) .. "\n")
end

--- Convert a hexadecimal string to an unsigned long long
---@param hex_str string The hexadecimal string to be converted to unsigned long long
---@return integer
function utils.hex_str_to_ull(hex_str)
    if #hex_str > 16 then hex_str = hex_str:sub(-16) end -- Truncate to 64 bits
    local len = #hex_str
    if len <= 12 then
        return (tonumber(hex_str, 16) or 0) + 0ULL
    else
        local split = len - 12
        local high_str = hex_str:sub(1, split)
        local low_str = hex_str:sub(split + 1)
        local high = (tonumber(high_str, 16) or 0) + 0ULL
        local low = (tonumber(low_str, 16) or 0) + 0ULL
        return bit_lshift(high, 48) + low
    end
end

--- Convert a hexadecimal string to a signed long long
---@nodiscard Return value should not be discarded
---@param hex_str string The hexadecimal string to be converted to signed long long
---@return integer
function utils.hex_str_to_ll(hex_str)
    local ull = utils.hex_str_to_ull(hex_str)
    -- Convert to signed by casting through ffi
    return ffi.cast("int64_t", ull) --[[@as integer]]
end

---@nodiscard Return value should not be discarded
---@param num integer The number to be converted to binary string
---@return string The binary string
function utils.num_to_binstr(num)
    num = tonumber(num) --[[@as integer]]
    if num == 0 then return "0" end
    local binstr = ""
    while num > 0 do
        ---@diagnostic disable-next-line: need-check-nil
        local bit_v = num % 2
        binstr = tostring(bit_v) .. binstr
        ---@diagnostic disable-next-line: need-check-nil
        num = math_floor(num / 2)
    end
    return binstr
end

---@param progress integer The progress, ranges from (0, 1)
---@param length integer The length of the progress bar
---@return string The string representation of the progress bar
function utils.get_progress_bar(progress, length)
    -- https://cn.piliapp.com/symbol/
    local completed = math_floor(progress * length)
    local remaining = length - completed
    local progressBar = "┃" .. srep("█", completed) .. "▉" .. srep("▒", remaining) .. "┃"
    return progressBar
end

---@param progress integer The progress, ranges from (0, 1)
---@param length integer The length of the progress bar
function utils.print_progress_bar(progress, length)
    print(utils.get_progress_bar(progress, length))
end

--- Usage Example:
--- ```lua
---   Direction = setmetatable({
---       name = "Direction",
---       INPUT = 0,
---       OUTPUT = 1
---   }, { __call = utils.enum_search })
--- ```
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

--- Usage Example:
--- ```lua
---      local State = utils.enum_define({
---            name = "State",
---
---            RUN = 1,
---            STOP = 2,
---            RUNNING = 3,
---      })
---      local state_value = State.RUN
---      print("current state is " .. State(state_value)) -- print: current state is RUN
---
---      local State = utils.enum_define {
---            name = "State",
---
---            RUN = 1,
---            STOP = 2,
---            RUNNING = 3,
---      }
--- ```
---@nodiscard Return value should not be discarded
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

--- Get the current date and time in the format <Year><Month><Day>_<Hour><Minute>
--- e.g.
--- ```lua
---     local str = utils.get_datetime_str()
---     assert(str == "20240124_2301")
--- ```
---@nodiscard Return value should not be discarded
---@return string The string representation of the current date and time in the format <Year><Month><Day>_<Hour><Minute>
function utils.get_datetime_str()
    local datetime = os.date("%Y%m%d_%H%M") --[[@as string]]
    return datetime
end

---@nodiscard Return value should not be discarded
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
    for i = 3, #hex do
        local nibble = hex:sub(i, i)
        bin = bin .. (hex_to_bin_map[nibble] or error("Invalid hex character: " .. nibble))
    end
    return bin
end

---@nodiscard Return value should not be discarded
---@param str string The input string (binary starts with "0b", hexadecimal starts with "0x", decimal has no prefix)
---@param s integer The start bit
---@param e integer The end bit
---@param width integer? The width of the input string (optional)
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
        bin_str = srep("0", width - #bin_str) .. bin_str
    end

    local len = #bin_str
    if s < 0 or e < 0 or s > len or e > len or s > e then
        error(f("Invalid bitfield range. s:%d, e:%d, len:%d", s, e, len))
    end

    local ret = bin_str:sub(len - e, len - s)
    return ret == "" and "0" or ret
end

---@class (exact) verilua.LuaUtils.BitPattern
---@field s integer
---@field e integer
---@field v integer|uint64_t

---@param bitpat_tbl verilua.LuaUtils.BitPattern[] The bit pattern table
---@param width number The width of the bit pattern (optional)
---@return string The hexadecimal string
local function bitpat_to_hex_str(bitpat_tbl, width)
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

    for _i, bitpat in ipairs(bitpat_tbl) do
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
        assert(bitpat.v <= max_val,
            f("bitpat.v (%d) exceeds the maximum value (%d) for the specified bit range [%d, %d]", bitpat.v, max_val,
                bitpat.s, bitpat.e))

        -- Determine which block and position within the block to apply the bit pattern
        local start_block = math_floor(bitpat.s / 64) + 1
        local end_block = math_floor(bitpat.e / 64) + 1
        local start_pos = bitpat.s % 64
        -- local end_pos = bitpat.e % 64

        if start_block == end_block then
            -- The bit pattern fits within a single block
            local mask
            if num_bits == 64 then
                ---@diagnostic disable-next-line
                mask = 0xFFFFFFFFFFFFFFFFULL
            else
                mask = bit_lshift(1ULL, num_bits) - 1
            end
            local shifted_value = bit_lshift(bit_band(bitpat.v --[[@as integer]], mask), start_pos)
            v[start_block] = bit_bor(v[start_block], shifted_value)
        else
            -- The bit pattern spans across multiple blocks
            local lower_bits = 64 - start_pos
            -- local upper_bits = num_bits - lower_bits

            -- Lower part in the start block
            local lower_mask = bit_lshift(1ULL, lower_bits) - 1
            local lower_value = bit_band(bitpat.v --[[@as integer]], lower_mask)
            v[start_block] = bit_bor(v[start_block], bit_lshift(lower_value, start_pos))

            -- Upper part in the end block
            local upper_value = bit_rshift(bitpat.v --[[@as integer]], lower_bits)
            v[end_block] = bit_bor(v[end_block], upper_value)
        end
    end

    -- Convert the result to a hexadecimal string
    local hexstr = ""
    for i = num_blocks, 1, -1 do
        hexstr = hexstr .. bit_tohex(v[i])
    end

    return hexstr
end

---@deprecated use <utils.bitpat_to_hex_str>
---@param bitpat_tbl verilua.LuaUtils.BitPattern[] The bit pattern table
---@param width number The width of the bit pattern (optional)
---@return string The hexadecimal string
function utils.bitpat_to_hexstr(bitpat_tbl, width)
    return bitpat_to_hex_str(bitpat_tbl, width)
end

utils.bitpat_to_hex_str = bitpat_to_hex_str

---@nodiscard Return value should not be discarded
---@param uint_value integer The unsigned integer value to be converted to one-hot encoding
---@return integer The one-hot encoded value
function utils.uint_to_onehot(uint_value)
    return bit_lshift(1, uint_value) + 0ULL
end

---@param t any[] The table to be shuffled
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

    ---@param str1 string The first hexadecimal string to be compared.(e.g. "1A"), any `0` prefix will be removed
    ---@param str2 string The second hexadecimal string to be compared.(e.g. "02b"), any `0` prefix will be removed
    function utils.compare_hex_str(str1, str2)
        return str1:lower():gsub("^0*", "") == str2:lower():gsub("^0*", "")
    end

    ---@nodiscard Return value should not be discarded
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

---@nodiscard Return value should not be discarded
---@param min integer|uint64_t
---@param max integer|uint64_t
---@return uint64_t
function utils.urandom64_range(min, max)
    local random_value = math_random(0, 0xFFFFFFFF) * 0x100000000ULL + math_random(0, 0xFFFFFFFF)

    local range = 0ULL --[[@as integer]]
    if max == 0xFFFFFFFFFFFFFFFFULL then
        range = 0xFFFFFFFFFFFFFFFFULL
    else
        range = (max - min) --[[@as integer]] + 1ULL
    end

    local result = min + (random_value % (range))

    return result --[[@as uint64_t]]
end

--- Splits a string into groups of a specified size.
---@nodiscard Return value should not be discarded
---@param str string The input string
---@param nr_group integer The number of groups to split the string into
---@return table<integer, string> The grouped string table
---@return integer The size of each group
function utils.str_group_by(str, nr_group)
    local group_size = math_ceil(#str / nr_group)
    local result = table_new(group_size, 0)
    for i = 1, #str, nr_group do
        local chunk = str:sub(i, i + nr_group - 1)
        table_insert(result, chunk)
    end
    return result, group_size
end

--- Separates a string with a separator at every step characters.
---@nodiscard Return value should not be discarded
---@param str string The input string to be separated
---@param step integer The number of characters between each separator
---@param separator string The separator to insert between chunks
---@return string The separated string
function utils.str_sep(str, step, separator)
    local result = ""
    separator = separator or " "

    for i = 1, #str, step do
        local chunk = str:sub(i, i + step - 1)
        result = result .. chunk .. separator
    end

    result = result:sub(1, - #separator - 1)
    return result
end

--- Returns a bitmask of n bits
--- e.g.
--- ```lua
--- local mask = utils.bitmask(4)
--- assert(mask == 0b1111)
--- ```
---@nodiscard Return value should not be discarded
---@param n integer
---@return uint64_t
function utils.bitmask(n)
    assert(n <= 64, "n must be less than or equal to 64")
    if n == 64 then
        return (0xFFFFFFFFFFFFFFFFULL) --[[@as uint64_t]]
    else
        return (bit_lshift(1ULL, n) - 1ULL) --[[@as uint64_t]]
    end
end

--- Resets a range of bits in a value to zero.
---@nodiscard Return value should not be discarded
---@param value integer The input value
---@param start integer The starting bit position
---@param length integer The number of bits to reset
---@return uint64_t The value with the specified bits reset to zero
function utils.reset_bits(value, start, length)
    assert(start < 64)
    assert(length <= 64)
    local mask = bit_lshift(utils.bitmask(length) --[[@as integer]], start)
    return bit_band(value, bit_bnot(mask)) --[[@as uint64_t]]
end

--- Calculates how many groups of n are needed to cover the value.
---@nodiscard Return value should not be discarded
---@param value number|integer The value to be covered
---@param n integer The size of each group
---@return integer The number of groups needed to cover the value
function utils.cover_with_n(value, n)
    return math_ceil(value / n)
end

--- Generates a random value within the specified bit width.
---@nodiscard Return value should not be discarded
---@param bitwidth integer The bit width of the random value (must be <= 64)
---@return uint64_t A random value within the specified bit width
function utils.shuffle_bits(bitwidth)
    assert(bitwidth <= 64, "bitwidth must be less than or equal to 64")
    if bitwidth <= 32 then
        return math_random(0, tonumber(utils.bitmask(bitwidth)) --[[@as integer]]) --[[@as uint64_t]]
    else
        return utils.urandom64_range(0, utils.bitmask(bitwidth))
    end
end

--- Generates a random hexadecimal string within the specified bit width.
---@nodiscard Return value should not be discarded
---@param bitwidth integer The bit width of the random value
---@return string The hexadecimal string representation of the random value
function utils.shuffle_bits_hex_str(bitwidth)
    if bitwidth <= 32 then
        return bit_tohex(utils.shuffle_bits(bitwidth) --[[@as integer]])
    else
        local u32_chunk = utils.cover_with_n(bitwidth, 32)
        local result = ""
        local total_bits = bitwidth
        for _i = 1, u32_chunk do
            if total_bits >= 32 then
                result = bit_tohex(utils.shuffle_bits(32) --[[@as integer]]) .. result
            else
                result = bit_tohex(utils.shuffle_bits(total_bits) --[[@as integer]]) .. result
            end
            total_bits = total_bits - 32
        end
        return result
    end
end

---@deprecated prefer use <adjust_hex_bitwidth> in StrBitsUtils.lua
--- e.g.
--- ```lua
--- local sbu = require "verilua.utils.StrBitsUtils"
--- local v = sbu.adjust_hex_bitwidth("1234", 10)
--- ```
---@nodiscard Return value should not be discarded
---@param value_hex_str string
---@param bitwidth integer
---@return string
function utils.expand_hex_str(value_hex_str, bitwidth)
    local len = #value_hex_str
    local target_len = utils.cover_with_n(bitwidth, 4)
    return srep("0", target_len - len) .. value_hex_str
end

--- Converts a hexadecimal string to a binary string.
---@nodiscard Return value should not be discarded
---@param hex_str string The hexadecimal string to convert
---@return string The binary string representation
function utils.hex_to_bin(hex_str)
    local bin_parts = table_new(#hex_str, 0)
    for i = 1, #hex_str do
        local nibble = hex_str:sub(i, i)
        bin_parts[i] = (hex_to_bin_map[nibble] or error("Invalid hex character: " .. nibble))
    end
    return table_concat(bin_parts)
end

--- Converts a binary string to a hexadecimal string.
---@nodiscard Return value should not be discarded
---@param bin_str string The binary string to convert
---@return string The hexadecimal string representation
function utils.bin_str_to_hex_str(bin_str)
    local remainder = #bin_str % 4
    if remainder ~= 0 then
        bin_str = srep("0", 4 - remainder) .. bin_str
    end

    local len = #bin_str
    local output_len = len / 4
    local hex_parts = {}

    for i = 1, output_len do
        local start_pos = (i - 1) * 4 + 1
        local four_bits = ssub(bin_str, start_pos, start_pos + 3)
        hex_parts[i] = bin_to_hex_map[four_bits]
    end

    return table_concat(hex_parts)
end

local truth_values = {
    ["true"] = true,
    ["True"] = true,
    ["TRUE"] = true,
    ["1"] = true,
    ["ENABLE"] = true,
    ["ON"] = true,
    ["enable"] = true,
    ["on"] = true,
}
local false_values = {
    ["false"] = true,
    ["False"] = true,
    ["FALSE"] = true,
    ["0"] = true,
    ["DISABLE"] = true,
    ["OFF"] = true,
    ["disable"] = true,
    ["off"] = true,
}
---@nodiscard Return value should not be discarded
---@generic T: string|number|integer|boolean
---@param key string Environment variable name
---@param value_type "string" | "boolean" | "number" | "integer"
---@param default T Default value if the environment variable is not set
---@return T The value of the environment variable or the default value
function utils.get_env_or_else(key, value_type, default)
    assert(type(key) == "string")
    local v = os.getenv(key)
    if v == nil then
        local default_type = type(default)
        if default_type == "nil" then
            assert(false, "[utils.get_env_or_else] default value must be provided")
        end

        if value_type == "string" then
            assert(
                default_type == "string",
                "[utils.get_env_or_else] default value must be `string`" ..
                " not `" .. default_type .. "` since value_type is `string`"
            )
        elseif value_type == "boolean" then
            assert(
                default_type == "boolean",
                "[utils.get_env_or_else] default value must be `boolean`" ..
                " not `" .. default_type .. "` since value_type is `boolean`"
            )
        elseif value_type == "number" or value_type == "integer" then
            local should_check_cdata = default_type == "cdata"
            local cdata_is_uint64 = ffi_istype("uint64_t", default)
            local cdata_is_int64 = ffi_istype("int64_t", default)
            assert(
                default_type == "number" or (should_check_cdata and (cdata_is_int64 or cdata_is_uint64)),
                "[utils.get_env_or_else] default value must be `number`/ `cdata(uint64_t)`" ..
                " not `" .. default_type .. "` since value_type is `number`"
            )
        end

        logger:warning("[get_env_or_else] '" .. key .. "' is not set, use default value: " .. tostring(default))
        return default --[[@as string|number|boolean]]
    end

    local value = nil
    if value_type == "string" then
        value = v
    elseif value_type == "boolean" then
        if truth_values[v] then
            value = true
        elseif false_values[v] then
            value = false
        else
            assert(false, "[utils.get_env_or_else] unknown value type! " .. key .. " => " .. v)
        end
    elseif value_type == "number" then
        local number_v = tonumber(v)
        assert(number_v ~= nil, "[utils.get_env_or_else] invald number value! " .. key .. " => " .. v)
        value = number_v
    else
        assert(false, "[utils.get_env_or_else] unknown value type")
    end

    assert(value ~= nil)
    logger:info("[get_env_or_else] '" .. key .. "' => " .. tostring(value))
    return value --[[@as string|number|boolean]]
end

---@class verilua.LuaUtils.matrix_call.single_func: function
---@class verilua.LuaUtils.matrix_call.seq_funcs: { [integer]: function }
---@class verilua.LuaUtils.matrix_call.single_func_with_args: { func: function, args: table, before?: function, after?: function }
---@class verilua.LuaUtils.matrix_call.single_func_with_muti_args: { func: function, multi_args: table[], before?: function, after?: function }
---@class verilua.LuaUtils.matrix_call.func_blocks: { [integer]: verilua.LuaUtils.matrix_call.single_func | verilua.LuaUtils.matrix_call.seq_funcs | verilua.LuaUtils.matrix_call.single_func_with_args | verilua.LuaUtils.matrix_call.single_func_with_muti_args }
---@class verilua.LuaUtils.matrix_call.params: { [integer]: verilua.LuaUtils.matrix_call.func_blocks }

--- Example usage:
--- 1. Basic matrix call (2D):
--- ```lua
---     matrix_call {
---         {
---             function() print("First dimension, option 1") end,
---             function() print("First dimension, option 2") end,
---         },
---         {
---             function() print("Second dimension, option 1") end,
---             function() print("Second dimension, option 2") end,
---         }
---     }
--- ```
--- This will generate all combinations and execute them:
--- ```shell
---     First dimension, option 1 -> Second dimension, option 1
---     First dimension, option 1 -> Second dimension, option 2
---     First dimension, option 2 -> Second dimension, option 1
---     First dimension, option 2 -> Second dimension, option 2
--- ```
---
--- 2. Sequential functions (seq_funcs):
--- ```lua
---      matrix_call {
---          {
---              {function() io.write("a") end, function() io.write(" b\n") end}
---          },
---          {
---              function() print("c") end
---          }
---      }
--- ```
--- Output:
--- ```shell
---     a b
---     c
--- ```
---
--- 3. Single function with arguments (single_func_with_args):
--- ```lua
---         matrix_call {
---             {
---                 {func = function(a, b) print("Sum:", a + b) end, args = {2, 3}},
---                 {func = function(a, b) print("Product:", a * b) end, args = {2, 3}},
---             }
---         }
--- ```
--- Output:
--- ```shell
---     Sum: 5
---     Product: 6
--- ```
---
--- 4. Single function with multiple arguments (single_func_with_muti_args):
--- ```lua
---         matrix_call {
---             {
---                 {func = function(a, b) print("Sum:", a + b) end, multi_args = {{2, 3}, {4, 5}}},
---                 {func = function(a, b) print("Product:", a * b) end, multi_args = {{2, 3}, {4, 5}}},
---             }
---         }
--- ```
--- Output:
--- ```shell
---     Sum: 5
---     Sum: 9
---     Product: 6
---     Product: 20
--- ```
---@param func_table verilua.LuaUtils.matrix_call.params
function utils.matrix_call(func_table)
    local dimensions = #func_table

    ---@type table<number, number>
    local max_indices = {}

    -- Initialize index arrays and maximum index arrays
    for i = 1, dimensions do
        max_indices[i] = #func_table[i]
    end

    ---@alias verilua.LuaUtils.matrix_call.func_block_type
    ---| "single_func"
    ---| "seq_funcs"
    ---| "single_func_with_args"
    ---| "single_func_with_muti_args"

    ---@type table<number, table<number, verilua.LuaUtils.matrix_call.func_block_type>>
    local func_table_meta = {}
    for i = 1, dimensions do
        for j = 1, max_indices[i] do
            if not func_table_meta[i] then
                func_table_meta[i] = {}
            end

            local entry = func_table[i][j]
            local typ = type(entry)

            if typ == "table" then
                if #entry == 0 then
                    if entry.args ~= nil then
                        assert(type(entry.args) == "table")
                        func_table_meta[i][j] = "single_func_with_args"
                    elseif entry.multi_args ~= nil then
                        assert(type(entry.multi_args) == "table")
                        assert(type(entry.multi_args[1]) == "table")
                        func_table_meta[i][j] = "single_func_with_muti_args"
                    else
                        assert(false, f("func_table[%d][%d] must have `args` or `multi_args` field", i, j))
                    end
                else
                    for k = 1, #entry do
                        assert(
                            type(entry[k]) == "function",
                            f(
                                "func_table[%d][%d][%d] must be a function, but %s",
                                i,
                                j,
                                k,
                                type(entry[k])
                            )
                        )
                    end
                    func_table_meta[i][j] = "seq_funcs"
                end
            elseif typ == "function" then
                func_table_meta[i][j] = "single_func"
            else
                assert(false, f("func_table[%d][%d] must be a function or a table", i, j))
            end
        end
    end

    ---@alias verilua.LuaUtils.matrix_call.current_dim integer
    ---@alias verilua.LuaUtils.matrix_call.dim_and_idx { [1]: verilua.LuaUtils.matrix_call.current_dim, [2]: integer }
    ---@alias verilua.LuaUtils.matrix_call.combination { [integer]: verilua.LuaUtils.matrix_call.dim_and_idx }

    -- Recursive function to generate all combinations
    ---@param current_dim verilua.LuaUtils.matrix_call.current_dim
    ---@param combination verilua.LuaUtils.matrix_call.combination
    local function generate_combinations(current_dim, combination)
        if current_dim > dimensions then
            -- Execute the current combination of functions
            for i = 1, #combination do
                local dim = combination[i][1]
                local idx = combination[i][2]
                local func_type = func_table_meta[dim][idx]
                local func_or_funcs = func_table[dim][idx]

                if func_type == "single_func" then
                    func_or_funcs()
                elseif func_type == "seq_funcs" then
                    for j = 1, #func_or_funcs do
                        ---@diagnostic disable-next-line: need-check-nil
                        func_or_funcs[j]()
                    end
                elseif func_type == "single_func_with_args" then
                    if func_or_funcs.before and type(func_or_funcs.before) == "function" then
                        func_or_funcs.before()
                    end
                    ---@diagnostic disable-next-line: need-check-nil
                    func_or_funcs.func(table.unpack(func_or_funcs.args))
                    if func_or_funcs.after and type(func_or_funcs.after) == "function" then
                        func_or_funcs.after()
                    end
                elseif func_type == "single_func_with_muti_args" then
                    for j = 1, #func_or_funcs.multi_args do
                        if func_or_funcs.before and type(func_or_funcs.before) == "function" then
                            func_or_funcs.before()
                        end
                        ---@diagnostic disable-next-line: need-check-nil
                        func_or_funcs.func(table.unpack(func_or_funcs.multi_args[j]))
                        if func_or_funcs.after and type(func_or_funcs.after) == "function" then
                            func_or_funcs.after()
                        end
                    end
                else
                    assert(false, f("func_table_meta[%d][%d] must be a function or a table", dim, idx))
                end
            end
            return
        end

        -- For each function in the current dimension
        for i = 1, max_indices[current_dim] do
            -- Create a new combination by copying the current one
            ---@type verilua.LuaUtils.matrix_call.combination
            local new_combination = table_new(#combination + 1, 0)
            for j = 1, #combination do
                new_combination[j] = combination[j]
            end

            -- Add the current dimension and index to the combination
            ---@type verilua.LuaUtils.matrix_call.dim_and_idx
            local dim_and_idx = { current_dim, i }
            new_combination[#new_combination + 1] = dim_and_idx

            -- Recursively process the next dimension
            generate_combinations(current_dim + 1, new_combination)
        end
    end

    -- Start generating combinations from the first dimension
    generate_combinations(1, {})
end

--- Execute a function after a specified number of calls
---@nodiscard Return value should not be discarded
---@param count number The number of calls to wait before executing the function
---@param func fun(): any? The function to execute
---@param options? { _repeat?: boolean, times?: number } If `options._repeat` is `true`, the function will be executed after every `count` calls
---@return fun(): any?
function utils.execute_after(count, func, options)
    local _count = 0
    local _target_count = count

    local _finish = false

    local _repeat = options and options._repeat or false

    local _times = options and options.times or nil
    local _times_count = 0

    if _repeat then
        return function()
            _count = _count + 1
            if _count >= _target_count then
                _count = 0
                return func()
            end
        end
    elseif _times then
        return function()
            if _finish then
                return
            end

            _count = _count + 1

            if _count >= _target_count then
                _count = 0

                _times_count = _times_count + 1
                if _times_count >= _times then
                    _finish = true
                end

                return func()
            end
        end
    else
        return function()
            if _finish then
                return
            end

            _count = _count + 1

            if _count >= _target_count then
                _finish = true
                return func()
            end
        end
    end
end

--- Loads and executes a Lua code string.
---@nodiscard Return value should not be discarded
---@param code string The Lua code string to load and execute
---@param env? table Optional environment table to set for the loaded function
---@param chunkname? string Optional name for the chunk (used in error messages)
---@return function
function utils.loadcode(code, env, chunkname)
    local ret = loadstring(code, chunkname) --[[@as function]]
    if not ret then
        assert(false, "[utils.loadcode] loadstring failed, code:\n" .. code)
    end

    if env then setfenv(ret, env) end
    return ret()
end

local unique_lock_file_idx = 0
--- Execute a function in an exclusive environment. (i.e. only one thread can execute the function at the same time)
---@param func fun() The function to execute exclusively
---@param lock_file_name string? Optional lock file name, auto-generated if not provided
function utils.exclusive_call(func, lock_file_name)
    if not lock_file_name then
        lock_file_name = "exclusive_call.lock." .. unique_lock_file_idx
        unique_lock_file_idx = unique_lock_file_idx + 1
    end

    assert(type(func) == "function", "[utils.exclusive_call] `func` must be a function")
    assert(type(lock_file_name) == "string", "[utils.exclusive_call] `lock_file_name` must be a string")

    ffi.cdef [[
        void *acquire_lock(const char *path);
        void release_lock(void *lock);
    ]]

    local lock = ffi.C.acquire_lock(lock_file_name)
    if not lock then
        assert(false, "[utils.exclusive_call] failed to acquire lock, lock_file_name: " .. lock_file_name)
    end

    func()

    ffi.C.release_lock(lock)
end

--- Generate `luacov.stats.out` file using `luacov`
--- Here is an example of how to generate coverage report using `luacov` in verilua:
--- ```lua
---      -- First, require luacov
---      require "luacov"
---
---      -- Second, run your code
---      -- <Your code here>
---
---      -- Third, generate coverage report at the end of the simulation
---      final {
---          function ()
---              local utils = require "LuaUtils"
---              utils.report_luacov()
---          end
---      }
--- ```
function utils.report_luacov()
    if not package.loaded.luacov then
        assert(
            false,
            "[utils.report_luacov] luacov is not loaded! Please make sure you have inserted `require('luacov')` in your code."
        )
    end

    -- Needs exclusive call to avoid multiple threads generating the same report file
    utils.exclusive_call(function()
        local runner = require("luacov.runner")
        runner.save_stats()
    end, "luacov.report.lock")
end

--- Attempts to get a function pointer through FFI cast or declaration.
---@nodiscard Return value should not be discarded
---@param func_ptr_str string The function pointer type string, e.g. "void (*)(const char*)"
---@param ffi_func_decl_str string The FFI function declaration string, e.g. "void my_func(const char*);"
---@param func_name string The function name to search for, e.g. "my_func"
---@return fun(any, ...): any The function pointer
function utils.try_ffi_cast(func_ptr_str, ffi_func_decl_str, func_name)
    local SymbolHelper = require("SymbolHelper")
    if SymbolHelper.get_global_symbol_addr(func_name) ~= 0 then
        return SymbolHelper.ffi_cast(func_ptr_str, func_name) --[[@as fun(any, ...): any]]
    else
        ffi.cdef(ffi_func_decl_str)
        assert(ffi.C[func_name], "[utils.try_ffi_cast] Failed to get symbol: " .. ffi_func_decl_str)
        return ffi.C[func_name] --[[@as fun(any, ...): any]]
    end
end

---@type fun(cmd: string): string?
local iorun_cfunc
--- Run a command and return the output(stdout or stderr if stdout is empty)
---@nodiscard Return value should not be discarded
---@param cmd string The command to execute
---@return string The command output from stdout or stderr
function utils.iorun(cmd)
    if not iorun_cfunc then
        local _iorun = utils.try_ffi_cast(
            "const char*(*)(const char*)",
            "const char* iorun(const char*);",
            "iorun"
        )
        iorun_cfunc = _iorun
    end

    local ret = iorun_cfunc(cmd)
    if ret == nil then
        assert(false, "[utils.iorun] Failed to run command: " .. cmd)
    end

    return ffi.string(ret)
end

return utils

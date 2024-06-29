local ffi = require "ffi"
local utils = {}
local this = utils

local bit, io, math, string, os = bit, io, math, string, os
local tostring, tonumber, ipairs, type, pairs, assert, print = tostring, tonumber, ipairs, type, pairs, assert, print
local format = string.format
local tconcat = table.concat
local tohex = bit.tohex
local ffi_new = ffi.new

--
---@param t table The table to be serialized
---@param conn string|char The connector for the serialization, defaults to "_"
---@return string The serialized string
--
function utils.serialize(t, conn)
    local serialized = t
    local conn = conn or "_"
    -- for k, v in pairs(t) do
    --     table.insert(serialized, tostring(k) .. "=" .. tostring(v))
    -- end
    -- table.sort(serialized)
    return tconcat(serialized, conn)
end

--
---@param tab table The table to be reversed
---@return table The reversed table
--
function utils.reverse_table(tab)
    local size = #tab
    local new_tab = {}

    for i, v in ipairs(tab) do
        new_tab[size - i + 1] = v
    end

    return new_tab
end

-- 
-- reverse == true(Default)
--     MSB <=> LSB
-- reverse == false
--     LSB <=> MSB
--
---@param t number|cdata|table The value to be converted to hexadecimal string
---@param reverse boolean Whether to reverse the byte order, defaults to true
---@return string The hexadecimal string
--
function utils.to_hex_str(t, reverse)
    reverse = reverse or true
    
    local t_type = type(t)

    if t_type == "number" then
        return format("%x", t)
    end

    local t_len
    if t_type == "cdata" then
        local ok, len = pcall(function (t)
            -- 
            -- if <t> is a LuaBundle multibeat data, then <t[0]> (type of <t> is uint64_t or cdata in LuaJIT) is the beat len of the multibeat data(i.e. beat len).
            -- Otherwise, if <t> is a normal cdata, there is no such concept of beat len, hence t_len == 1
            -- 
            return t[0]
        end, t)
        
        if ok then
            t_len = len
        else
            t_len = 1
        end
    else
        assert(t_type == "table")
        t_len = #t
    end

    local t_copy = {}
    if t_len == 1 and t_type == "cdata" then
         t_copy[1] = tohex(tonumber(t))
    else
        for i = 1, t_len do
            t_copy[i] = tohex(t[i])
        end
    end

    if reverse then
        local i, n = 1, t_len
        while i < n do
            t_copy[i], t_copy[n] = t_copy[n], t_copy[i]
            i, n = i + 1, n - 1
        end
    end

    return tconcat(t_copy, " ")
end

--
---@param n number The value to calculate the logarithm base 2
---@return number The ceiling of the logarithm base 2
--
function utils.log2Ceil(n)
    if n < 1 then
        return 0
    else
        local log_val = math.log(n) / math.log(2)
        local ceil_val = math.ceil(log_val)
        return ceil_val
    end
end

--
---@param begin number The start bit
---@param endd number The end bit
---@param val number The value to be processed
---@return number The processed value
--
function utils.bitfield32(begin, endd, val)
    return bit.rshift( bit.lshift(val, 32 - endd), begin + 32- endd )
end

--
---@param begin number The start bit
---@param endd number The end bit
---@param val number The value to be processed
---@return number The processed value
--
function utils.bitfield64(begin, endd, val)
    local val64 = ffi_new('uint64_t', val)
    return bit.rshift( bit.lshift(val64, 64 - endd), begin + 64- endd )
end

--
---@param hi number The higher 32 bits
---@param lo number The lower 32 bits
---@return number The combined 64-bit value
--
function utils.to64bit(hi, lo)
    return bit.lshift(hi, 32) + lo
end

-- 
-- LSB <==> MSB
--
---@param hex_table number|table The value or table to be converted to hexadecimal
---@return string The hexadecimal string
--
function utils.to_hex(hex_table)
    local ret = ""
    if type(hex_table) == "table" then
        for index, value in ipairs(hex_table) do
            ret = ret .. string.format("%x ", value)
        end
    else
        ret = ret .. string.format("%x", hex_table)
    end
    return ret
end

--
---@param hex_table number|table The value or table to be printed as hexadecimal
--
function utils.print_hex(hex_table)
    io.write(this.to_hex(hex_table).."\n")
end

--
---@param num number The number to be converted to binary string
---@return string The binary string
--
function utils.num_to_binstr(num)
    local num = tonumber(num)
    if num == 0 then return "0" end
    local binstr = ""
    while num > 0 do
        local bit = num % 2
        binstr = tostring(bit) .. binstr
        num = math.floor(num / 2)
    end
    return binstr
end

--
---@param progress number The progress, ranges from (0, 1)
---@param length number The length of the progress bar
---@return string The string representation of the progress bar
--
function utils.get_progress_bar(progress, length)
    -- https://cn.piliapp.com/symbol/
    local completed = math.floor(progress * length)
    local remaining = length - completed
    local progressBar = "┃" .. string.rep("█", completed) .. "▉" .. string.rep(" ", remaining) .. "┃"
    return progressBar
end

--
---@param progress number The progress, ranges from (0, 1)
---@param length number The length of the progress bar
--
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
--
function utils.enum_search(t, v)
    for name, value in pairs(t) do
        if value == v then
            return name
        end
    end
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
---@param enum_table table The enumeration table to be defined
---@return table The defined enumeration table
--
function utils.enum_define(enum_table)
    assert(type(enum_table) == "table")
    
    if enum_table.name == nil then
        enum_table.name = "Undefined"
    end

    return setmetatable(enum_table, 
        {
            __call = utils.enum_search,

            __index = function(t, v)
                assert(false, format("Unknown enum value => %s  enum name => %s", tostring(v), t.name))
            end
        }
    )
end


-- 
-- format: <Year><Month><Day>_<Hour><Minute>
-- Example:
--   local str = utils.get_datetime_str()
--         str == "20240124_2301" 
-- 
--
---@return string The string representation of the current date and time in the format <Year><Month><Day>_<Hour><Minute>
--
function utils.get_datetime_str()
    local datetime = os.date("%Y%m%d_%H%M")
    return datetime
end


local path = require "pl.path"
--
---@param ... string The file name or directory name to get the absolute path
---@return string The absolute path
--
function utils.abspath(...)
    return path.abspath(...)
end

--
---@param filename string The file name to be read
---@return string The content of the file
--
function utils.read_file_str(filename)
    local file = io.open(utils.abspath(filename), "r") 
    if not file then
        assert(false, "cannot open " .. utils.abspath(filename))
    end
    local content = file:read("*a")
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
        num = math.floor(num / 2)
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


--
---@param str string The input string (binary starts with "0b", hexadecimal starts with "0x", decimal has no prefix)
---@param s number The start bit
---@param e number The end bit
---@param width number The width of the input string (optional)
---@return string The binary string
--
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
    if s < 0 or e < 0 or s >= len or e >= len or s > e then
        error("Invalid bitfield range.")
    end

    return bin_str:sub(len - e, len - s)
end

--
---@param bitpat_tbl table The bit pattern table
---@param width number The width of the bit pattern (optional)
---@return string The hexadecimal string
--
function utils.bitpat_to_hexstr(bitpat_tbl, width)
    assert(type(bitpat_tbl) == "table", "bitpat_tbl must be a table")
    assert(type(bitpat_tbl[1]) == "table", "bitpat_tbl must contain tables")
    if width ~= nil then
        assert(type(width) == "number" and width > 0, "width must be a positive number")
    else
        width = 64 
    end

    -- Calculate the number of 64-bit blocks required to handle the specified width
    local num_blocks = math.ceil(width / 64)
    
    -- Initialize the value as a table of zeros (each element represents a 64-bit block)
    local v = {}
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
            max_val = bit.lshift(1ULL, num_bits) - 1
        end
        assert(bitpat.v <= max_val, string.format("bitpat.v (%d) exceeds the maximum value (%d) for the specified bit range [%d, %d]", bitpat.v, max_val, bitpat.s, bitpat.e))

        -- Determine which block and position within the block to apply the bit pattern
        local start_block = math.floor(bitpat.s / 64) + 1
        local end_block = math.floor(bitpat.e / 64) + 1
        local start_pos = bitpat.s % 64
        local end_pos = bitpat.e % 64

        if start_block == end_block then
            -- The bit pattern fits within a single block
            local mask
            if num_bits == 64 then
                mask = 0xFFFFFFFFFFFFFFFFULL
            else
                mask = bit.lshift(1ULL, num_bits) - 1
            end
            local shifted_value = bit.lshift(bit.band(bitpat.v, mask), start_pos)
            v[start_block] = bit.bor(v[start_block], shifted_value)
        else
            -- The bit pattern spans across multiple blocks
            local lower_bits = 64 - start_pos
            local upper_bits = num_bits - lower_bits

            -- Lower part in the start block
            local lower_mask = bit.lshift(1ULL, lower_bits) - 1
            local lower_value = bit.band(bitpat.v, lower_mask)
            v[start_block] = bit.bor(v[start_block], bit.lshift(lower_value, start_pos))

            -- Upper part in the end block
            local upper_value = bit.rshift(bitpat.v, lower_bits)
            v[end_block] = bit.bor(v[end_block], upper_value)
        end
    end

    -- Convert the result to a hexadecimal string
    local hexstr = "0x"
    for i = num_blocks, 1, -1 do
        hexstr = hexstr .. bit.tohex(v[i])
    end

    return hexstr
end

-- 
-- simple test
-- 
-- assert(utils.bitfield_str("0000322", 8, 9, 10) == "01")
-- assert(utils.bitfield_str("322", 0, 8) == "101000010")
-- assert(utils.bitfield_str("322", 0, 9, 10) == "0101000010")
-- assert(utils.bitfield_str("0x123", 0, 2) == "011")
-- assert(utils.bitfield_str("0b0101", 0, 3) == "0101") -- get: 0101
-- assert(utils.bitfield_str("0b01  01", 0, 3) == "0101") -- get: 0101
-- assert(tonumber(utils.bitfield_str("123", 0, 6), 2) == 123) -- get: 123
-- assert(tonumber(utils.bitfield_str("0x1000004", 0, 15), 2) == 4) 
-- assert(utils.bitfield_str("0x12345678_12345678 12345678 12345678 12345678 12345678 12345678 12345678", 0, 4) == "11000")

-- assert(utils.bitpat_to_hexstr({
--     {s = 0, e = 1, v = 2},
--     {s = 4, e = 7, v = 4},
--     {s = 63, e = 63, v = 1}
-- }, 64) == "0x8000000000000042")

-- assert(utils.bitpat_to_hexstr({
--     {s = 0, e = 1, v = 2},
--     {s = 4, e = 7, v = 4},
--     {s = 127, e = 127, v = 1}
-- }, 128) == "0x80000000000000000000000000000042")

-- assert(utils.bitpat_to_hexstr({
--     {s = 0, e = 1, v = 2},
--     {s = 4, e = 7, v = 4},
--     {s = 255, e = 255, v = 1}
-- }, 256) == "0x8000000000000000000000000000000000000000000000000000000000000042")

-- assert(utils.bitpat_to_hexstr({
--     {s = 0, e = 1, v = 2},
--     {s = 4, e = 7, v = 4},
--     {s = 109, e = 109, v = 1}
-- }, 110) == "0x00002000000000000000000000000042")

-- assert(utils.bitpat_to_hexstr({
--     {s = 0, e = 1, v = 2},
--     {s = 4, e = 7, v = 4},
--     {s = 65, e = 127, v = 0x11231}
-- }, 128) == "0x00000000000224620000000000000042")

-- assert(utils.bitpat_to_hexstr({
--     {s = 0, e = 63, v = 0xdead}
-- }, 512) == "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dead")

-- assert(utils.bitpat_to_hexstr({
--     {s = 0, e = 63, v = 0xdead},
--     {s = 256, e = 255 + 63, v = 0xbeef},
-- }, 512) == "0x000000000000000000000000000000000000000000000000000000000000beef000000000000000000000000000000000000000000000000000000000000dead")



return utils
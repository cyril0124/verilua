---@diagnostic disable: unnecessary-assert

local bit = require "bit"
local math = require "math"
local stringx = require "pl.stringx"
local table_new = require "table.new"
local utils = require "LuaUtils"

local f = string.format
local tonumber = tonumber
local math_ceil = math.ceil
local table_concat = table.concat

local bit_bor = bit.bor
local bit_bxor = bit.bxor
local bit_bnot = bit.bnot
local bit_band = bit.band
local bit_lshift = bit.lshift

local srep = string.rep
local ssub = string.sub
local scount = stringx.count

---@class (exact) verilua.utils.HexStrBits
local M = {}

---@param bin_or_hex_str string
---@return string
function M.trim_leading_zeros(bin_or_hex_str)
    local ret = bin_or_hex_str:gsub("^0+", "")
    if ret == "" then
        ret = "0"
    end
    return ret
end

-- Helper: Adjust binary string to specific bitwidth (truncate MSB or pad MSB)
---@param bin_str string
---@param bitwidth? integer
---@return string
local function adjust_bin_bitwidth(bin_str, bitwidth)
    if not bitwidth then return bin_str end

    bitwidth = tonumber(bitwidth) --[[@as integer]]

    local len = #bin_str
    if len > bitwidth then
        -- Truncate MSB (overflow behavior: keep the lower 'bitwidth' bits)
        return ssub(bin_str, -bitwidth)
    elseif len < bitwidth then
        -- Pad MSB with zeros (extend to register size)
        return srep("0", bitwidth - len) .. bin_str
    end
    return bin_str
end

--- Helper function to convert hex string to uint64_t safely
--- Handles strings up to 16 hex characters (64 bits)
---@param hex_str string
---@return integer uint64_t value
local function hex_str_to_ull(hex_str)
    local len = #hex_str
    if len <= 13 then
        -- Safe to use tonumber for up to 13 hex characters (52 bits)
        return (tonumber(hex_str, 16) or 0) + 0ULL
    else
        -- For longer strings, split into high and low parts
        local split_pos = len - 13
        local high_str = ssub(hex_str, 1, split_pos)
        local low_str = ssub(hex_str, split_pos + 1)

        local high = (tonumber(high_str, 16) or 0) + 0ULL
        local low = (tonumber(low_str, 16) or 0) + 0ULL

        -- Shift high part left and add low part
        local shift_amount = #low_str * 4 -- 4 bits per hex character
        return bit_lshift(high, shift_amount) + low
    end
end

--- Mask hex string inputs to fit within specified bitwidth
--- @param hex_str string The hex string to mask
--- @param bitwidth number The target bitwidth
--- @return string The masked hex string
local function adjust_hex_bitwidth(hex_str, bitwidth)
    local bitwidth_hex_chars = math_ceil(bitwidth / 4)

    -- Truncate if input exceeds bitwidth
    if #hex_str > bitwidth_hex_chars then
        hex_str = ssub(hex_str, -bitwidth_hex_chars)
    end

    -- Pad to bitwidth_hex_chars if shorter
    if #hex_str < bitwidth_hex_chars then
        hex_str = srep("0", bitwidth_hex_chars - #hex_str) .. hex_str
    end

    -- Mask off extra bits in MSB nibble if bitwidth is not a multiple of 4
    local bitwidth_mod4 = bitwidth % 4
    if bitwidth_mod4 ~= 0 then
        local mask = bit_lshift(1, bitwidth_mod4 --[[@as integer]]) - 1
        local first_nibble = tonumber(ssub(hex_str, 1, 1), 16) or 0
        local masked_nibble = bit_band(first_nibble, mask)
        hex_str = f("%x", masked_nibble) .. ssub(hex_str, 2)
    end

    return hex_str
end

--- Adjust hex string to specified bitwidth with bit-level precision
---@param hex_str string The input hex string (without "0x" prefix)
---@param bitwidth integer The target bitwidth
---@return string The adjusted hex string
function M.adjust_hex_bitwidth(hex_str, bitwidth)
    return adjust_hex_bitwidth(hex_str, bitwidth)
end

--- Adjust binary string to specified bitwidth with bit-level precision
---@param bin_str string The input binary string
---@param bitwidth integer The target bitwidth
---@return string The adjusted binary string
function M.adjust_bin_bitwidth(bin_str, bitwidth)
    return adjust_bin_bitwidth(bin_str, bitwidth)
end

---@param hex_str string The hexadecimal string without "0x" prefix
---@param s integer The start bit
---@param e integer The end bit
---@param bitwidth integer? The bitwidth of the input string (optional)
---@return string The hexadecimal string representation of the extracted bitfield
function M.bitfield_hex_str(hex_str, s, e, bitwidth)
    -- Convert hex string to binary string
    local bin_str = utils.hex_to_bin(hex_str)

    -- Ensure the binary string meets the desired width by padding with leading zeros
    if bitwidth and bitwidth > #bin_str then
        bitwidth = tonumber(bitwidth) --[[@as integer]]
        bin_str = srep("0", bitwidth - #bin_str) .. bin_str
    end

    local len = #bin_str
    if s < 0 or e < 0 or s > len or e > len or s > e then
        error(f("Invalid bitfield range. s:%d, e:%d, len:%d", s, e, len))
    end

    e = tonumber(e) --[[@as integer]]
    s = tonumber(s) --[[@as integer]]

    -- Extract the bitfield as a binary string
    local bin_result = bin_str:sub(len - e, len - s)
    if bin_result == "" then
        bin_result = "0"
    end

    -- Convert binary result to hexadecimal string
    return utils.bin_str_to_hex_str(bin_result)
end

---@param hex_str string The original hexadecimal string without "0x" prefix
---@param s integer The start bit
---@param e integer The end bit
---@param val_hex_str string The value to set in hexadecimal string format without "0x" prefix
---@param bitwidth integer? The bitwidth of the original string (optional)
---@return string The new hexadecimal string
function M.set_bitfield_hex_str(hex_str, s, e, val_hex_str, bitwidth)
    -- Convert hex string to binary string
    local bin_str = utils.hex_to_bin(hex_str)

    -- Ensure the binary string meets the desired bitwidth by padding with leading zeros
    if bitwidth and bitwidth > #bin_str then
        bitwidth = tonumber(bitwidth) --[[@as integer]]
        bin_str = srep("0", bitwidth - #bin_str) .. bin_str
    end

    local len = #bin_str

    s = tonumber(s) --[[@as integer]]
    e = tonumber(e) --[[@as integer]]

    -- Auto-expand if bitwidth is not provided and range exceeds current length
    if not bitwidth and e >= len then
        bin_str = srep("0", e - len + 1) .. bin_str
        len = #bin_str
    end

    if s < 0 or e < 0 or s >= len or e >= len or s > e then
        error(f("Invalid bitfield range. s:%d, e:%d, len:%d", s, e, len))
    end

    -- Convert value to binary
    local val_bin_str = utils.hex_to_bin(val_hex_str)
    local val_width = e - s + 1

    -- Pad or truncate value to fit the range
    if #val_bin_str < val_width then
        val_bin_str = srep("0", val_width - #val_bin_str) .. val_bin_str
    elseif #val_bin_str > val_width then
        val_bin_str = val_bin_str:sub(-val_width)
    end

    -- Replace bits
    -- s is LSB (0-based), e is MSB (0-based)
    -- string index 1 is MSB. string index len is LSB.
    -- bit s is at index len - s
    -- bit e is at index len - e
    -- range in string is [len - e, len - s]

    local start_idx = len - e
    local end_idx = len - s

    local prefix = bin_str:sub(1, start_idx - 1)
    local suffix = bin_str:sub(end_idx + 1)

    local new_bin_str = prefix .. val_bin_str .. suffix

    return utils.bin_str_to_hex_str(new_bin_str)
end

--- Left shift a hexadecimal string representation.
--- Mimics the behavior of `val << n`.
---@param hex_str string: The input hexadecimal string.
---@param n integer: The number of bits to shift.
---@param bitwidth? integer: (Optional) Simulates a fixed-width register. Truncates overflow if set.
---@return string hex_str
function M.lshift_hex_str(hex_str, n, bitwidth)
    n = tonumber(n) --[[@as integer]]

    -- Optimization: If shift is 0, just handle bitwidth adjustment
    if n == 0 then
        if bitwidth then
            local bin_str = utils.hex_to_bin(hex_str)
            bin_str = adjust_bin_bitwidth(bin_str, bitwidth)
            return utils.bin_str_to_hex_str(bin_str)
        else
            return hex_str
        end
    end

    local bin_str = utils.hex_to_bin(hex_str)

    -- LShift adds '0's to the LSB (Least Significant Bits)
    local shifted_bin = bin_str .. srep("0", n)

    -- Handle truncation if bitwidth is specified
    if bitwidth then
        shifted_bin = adjust_bin_bitwidth(shifted_bin, bitwidth)
    end

    -- Convert back to hex and clean up
    local result = utils.bin_str_to_hex_str(shifted_bin)
    if bitwidth then
        return result
    else
        return M.trim_leading_zeros(result)
    end
end

--- Logical right shift a hexadecimal string representation.
--- Mimics the behavior of `val >> n` (Logical Shift, zero-filling MSB).
---@param hex_str string: The input hexadecimal string.
---@param n integer: The number of bits to shift.
---@param bitwidth? integer: (Optional) Simulates a fixed-width register. Used for MSB padding.
---@return string hex_str
function M.rshift_hex_str(hex_str, n, bitwidth)
    n = tonumber(n) --[[@as integer]]

    local bin_str = utils.hex_to_bin(hex_str)

    -- If bitwidth is provided, ensure input is conformant BEFORE shifting
    -- (e.g., shifting a 32-bit value inside an 8-bit register context)
    if bitwidth then
        bin_str = adjust_bin_bitwidth(bin_str, bitwidth)
    end

    local len = #bin_str

    -- Edge Case: If shift amount >= length, the result is 0
    if n >= len then
        return "0"
    end

    -- RShift truncates the LSB (Least Significant Bits).
    -- We keep the substring from index 1 to (length - n).
    -- Note: Logical right shift naturally pads MSB with 0, which is implicit here
    -- because we are removing bits from the end.
    local shifted_bin = ssub(bin_str, 1, len - n)

    -- If bitwidth is strictly required for the output format (e.g. fixed width return),
    -- we pad the now-shorter string with leading zeros.
    if bitwidth then
        shifted_bin = adjust_bin_bitwidth(shifted_bin, bitwidth)
    end

    local result = utils.bin_str_to_hex_str(shifted_bin)
    if bitwidth then
        return result
    else
        return M.trim_leading_zeros(result)
    end
end

--- Perform bitwise OR operation on two hexadecimal strings.
--- Returns a hexadecimal string representing the result.
---@param hex_str1 string: First hexadecimal string (without 0x prefix)
---@param hex_str2 string: Second hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional target bit width (result is truncated/padded to this width)
---@return string: Result as hexadecimal string (without 0x prefix)
function M.bor_hex_str(hex_str1, hex_str2, bitwidth)
    -- Calculate target length based on inputs and bitwidth
    local len1, len2 = #hex_str1, #hex_str2
    local max_len = len1 > len2 and len1 or len2

    if bitwidth then
        bitwidth = tonumber(bitwidth) --[[@as integer]]

        local bitwidth_hex_chars = math_ceil(bitwidth / 4)
        if bitwidth_hex_chars > max_len then
            max_len = bitwidth_hex_chars
        end
        -- Mask inputs to fit within bitwidth
        hex_str1 = adjust_hex_bitwidth(hex_str1, bitwidth)
        hex_str2 = adjust_hex_bitwidth(hex_str2, bitwidth)
        -- Update lengths after masking
        len1, len2 = #hex_str1, #hex_str2
        max_len = len1 > len2 and len1 or len2
        if bitwidth_hex_chars > max_len then
            max_len = bitwidth_hex_chars
        end
    end

    -- Pad both strings to the same length
    if len1 < max_len then
        hex_str1 = srep("0", max_len - len1) .. hex_str1
    elseif len2 < max_len then
        hex_str2 = srep("0", max_len - len2) .. hex_str2
    end

    -- Process in chunks of 16 hex characters (64 bits) for optimal LuaJIT performance
    local result_parts = {}
    local chunk_size = 16
    local num_chunks = math_ceil(max_len / chunk_size)

    for i = 1, num_chunks do
        local end_pos = max_len - (i - 1) * chunk_size
        local start_pos = end_pos - chunk_size + 1
        if start_pos < 1 then start_pos = 1 end

        local chunk1 = ssub(hex_str1, start_pos, end_pos)
        local chunk2 = ssub(hex_str2, start_pos, end_pos)

        -- Convert to numbers and perform bitwise OR
        local num1 = hex_str_to_ull(chunk1)
        local num2 = hex_str_to_ull(chunk2)
        local result = bit_bor(num1, num2)

        -- Format back to hex string with proper padding
        local chunk_len = end_pos - start_pos + 1
        local hex_result = f("%x", result):lower()
        -- Pad to chunk_len if necessary
        if #hex_result < chunk_len then
            hex_result = srep("0", chunk_len - #hex_result) .. hex_result
        end
        result_parts[num_chunks - i + 1] = hex_result
    end

    local result = table_concat(result_parts)

    -- Handle bitwidth truncation/padding if specified
    if bitwidth then
        local bitwidth_hex_chars = math_ceil(bitwidth / 4)
        local result_len = #result
        if result_len > bitwidth_hex_chars then
            result = ssub(result, -bitwidth_hex_chars)
        elseif result_len < bitwidth_hex_chars then
            result = srep("0", bitwidth_hex_chars - result_len) .. result
        end

        -- Mask off extra bits in MSB nibble if bitwidth is not a multiple of 4
        local bitwidth_mod4 = bitwidth % 4
        if bitwidth_mod4 ~= 0 then
            local mask = bit_lshift(1, bitwidth_mod4) - 1
            local first_nibble = tonumber(ssub(result, 1, 1), 16) or 0
            local masked_nibble = bit_band(first_nibble, mask)
            result = f("%x", masked_nibble) .. ssub(result, 2)
        end
    end

    if bitwidth then
        return result
    else
        return M.trim_leading_zeros(result)
    end
end

--- Perform bitwise XOR operation on two hexadecimal strings.
--- Returns a hexadecimal string representing the result.
---@param hex_str1 string: First hexadecimal string (without 0x prefix)
---@param hex_str2 string: Second hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional target bit width (result is truncated/padded to this width)
---@return string: Result as hexadecimal string (without 0x prefix)
function M.bxor_hex_str(hex_str1, hex_str2, bitwidth)
    -- Calculate target length based on inputs and bitwidth
    local len1, len2 = #hex_str1, #hex_str2
    local max_len = len1 > len2 and len1 or len2

    if bitwidth then
        bitwidth = tonumber(bitwidth) --[[@as integer]]

        local bitwidth_hex_chars = math_ceil(bitwidth / 4)
        if bitwidth_hex_chars > max_len then
            max_len = bitwidth_hex_chars
        end
        -- Mask inputs to fit within bitwidth
        hex_str1 = adjust_hex_bitwidth(hex_str1, bitwidth)
        hex_str2 = adjust_hex_bitwidth(hex_str2, bitwidth)
        -- Update lengths after masking
        len1, len2 = #hex_str1, #hex_str2
        max_len = len1 > len2 and len1 or len2
        if bitwidth_hex_chars > max_len then
            max_len = bitwidth_hex_chars
        end
    end

    -- Pad both strings to the same length
    if len1 < max_len then
        hex_str1 = srep("0", max_len - len1) .. hex_str1
    elseif len2 < max_len then
        hex_str2 = srep("0", max_len - len2) .. hex_str2
    end

    -- Process in chunks of 16 hex characters (64 bits) for optimal LuaJIT performance
    local result_parts = {}
    local chunk_size = 16
    local num_chunks = math_ceil(max_len / chunk_size)

    for i = 1, num_chunks do
        local end_pos = max_len - (i - 1) * chunk_size
        local start_pos = end_pos - chunk_size + 1
        if start_pos < 1 then start_pos = 1 end

        local chunk1 = ssub(hex_str1, start_pos, end_pos)
        local chunk2 = ssub(hex_str2, start_pos, end_pos)

        -- Convert to numbers and perform bitwise XOR
        local num1 = hex_str_to_ull(chunk1)
        local num2 = hex_str_to_ull(chunk2)
        local result = bit_bxor(num1, num2)

        -- Format back to hex string with proper padding
        local chunk_len = end_pos - start_pos + 1
        local hex_result = f("%x", result):lower()
        -- Pad to chunk_len if necessary
        if #hex_result < chunk_len then
            hex_result = srep("0", chunk_len - #hex_result) .. hex_result
        end
        result_parts[num_chunks - i + 1] = hex_result
    end

    local result = table_concat(result_parts)

    -- Handle bitwidth truncation/padding if specified
    if bitwidth then
        local bitwidth_hex_chars = math_ceil(bitwidth / 4)
        local result_len = #result
        if result_len > bitwidth_hex_chars then
            result = ssub(result, -bitwidth_hex_chars)
        elseif result_len < bitwidth_hex_chars then
            result = srep("0", bitwidth_hex_chars - result_len) .. result
        end

        -- Mask off extra bits in MSB nibble if bitwidth is not a multiple of 4
        local bitwidth_mod4 = bitwidth % 4
        if bitwidth_mod4 ~= 0 then
            local mask = bit_lshift(1, bitwidth_mod4) - 1
            local first_nibble = tonumber(ssub(result, 1, 1), 16) or 0
            local masked_nibble = bit_band(first_nibble, mask)
            result = f("%x", masked_nibble) .. ssub(result, 2)
        end
    end

    if bitwidth then
        return result
    else
        return M.trim_leading_zeros(result)
    end
end

--- Perform bitwise AND operation on two hexadecimal strings.
--- Returns a hexadecimal string representing the result.
---@param hex_str1 string: First hexadecimal string (without 0x prefix)
---@param hex_str2 string: Second hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional target bit width (result is truncated/padded to this width)
---@return string: Result as hexadecimal string (without 0x prefix)
function M.band_hex_str(hex_str1, hex_str2, bitwidth)
    -- Calculate target length based on inputs and bitwidth
    local len1, len2 = #hex_str1, #hex_str2
    local max_len = len1 > len2 and len1 or len2

    if bitwidth then
        bitwidth = tonumber(bitwidth) --[[@as integer]]

        local bitwidth_hex_chars = math_ceil(bitwidth / 4)
        if bitwidth_hex_chars > max_len then
            max_len = bitwidth_hex_chars
        end
        -- Mask inputs to fit within bitwidth
        hex_str1 = adjust_hex_bitwidth(hex_str1, bitwidth)
        hex_str2 = adjust_hex_bitwidth(hex_str2, bitwidth)
        -- Update lengths after masking
        len1, len2 = #hex_str1, #hex_str2
        max_len = len1 > len2 and len1 or len2
        if bitwidth_hex_chars > max_len then
            max_len = bitwidth_hex_chars
        end
    end

    -- Pad both strings to the same length
    if len1 < max_len then
        hex_str1 = srep("0", max_len - len1) .. hex_str1
    elseif len2 < max_len then
        hex_str2 = srep("0", max_len - len2) .. hex_str2
    end

    -- Process in chunks of 16 hex characters (64 bits) for optimal LuaJIT performance
    local result_parts = {}
    local chunk_size = 16
    local num_chunks = math_ceil(max_len / chunk_size)

    for i = 1, num_chunks do
        local end_pos = max_len - (i - 1) * chunk_size
        local start_pos = end_pos - chunk_size + 1
        if start_pos < 1 then start_pos = 1 end

        local chunk1 = ssub(hex_str1, start_pos, end_pos)
        local chunk2 = ssub(hex_str2, start_pos, end_pos)

        -- Convert to numbers and perform bitwise AND
        local num1 = hex_str_to_ull(chunk1)
        local num2 = hex_str_to_ull(chunk2)
        local result = bit_band(num1, num2)

        -- Format back to hex string with proper padding
        local chunk_len = end_pos - start_pos + 1
        local hex_result = f("%x", result):lower()
        -- Pad to chunk_len if necessary
        if #hex_result < chunk_len then
            hex_result = srep("0", chunk_len - #hex_result) .. hex_result
        end
        result_parts[num_chunks - i + 1] = hex_result
    end

    local result = table_concat(result_parts)

    -- Handle bitwidth truncation/padding if specified
    if bitwidth then
        local bitwidth_hex_chars = math_ceil(bitwidth / 4)
        local result_len = #result
        if result_len > bitwidth_hex_chars then
            result = ssub(result, -bitwidth_hex_chars)
        elseif result_len < bitwidth_hex_chars then
            result = srep("0", bitwidth_hex_chars - result_len) .. result
        end

        -- Mask off extra bits in MSB nibble if bitwidth is not a multiple of 4
        local bitwidth_mod4 = bitwidth % 4
        if bitwidth_mod4 ~= 0 then
            local mask = bit_lshift(1, bitwidth_mod4) - 1
            local first_nibble = tonumber(ssub(result, 1, 1), 16) or 0
            local masked_nibble = bit_band(first_nibble, mask)
            result = f("%x", masked_nibble) .. ssub(result, 2)
        end
    end

    if bitwidth then
        return result
    else
        return M.trim_leading_zeros(result)
    end
end

--- Perform bitwise NOT operation on a hexadecimal string.
--- Returns a hexadecimal string representing the result.
--- If bitwidth is not specified, the function assumes the bitwidth based on the input hex string length.
---@param hex_str string: Hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional bit width (result is masked to this width)
---@return string: Result as hexadecimal string (without 0x prefix)
function M.bnot_hex_str(hex_str, bitwidth)
    -- Determine effective bitwidth
    local effective_bitwidth
    if bitwidth then
        bitwidth = tonumber(bitwidth) --[[@as integer]]

        effective_bitwidth = bitwidth
        -- Mask input to fit within specified bitwidth
        hex_str = adjust_hex_bitwidth(hex_str, bitwidth)
    else
        -- Infer bitwidth from hex string length
        effective_bitwidth = #hex_str * 4
    end

    local hex_len = #hex_str
    local bitwidth_hex_chars = math_ceil(effective_bitwidth / 4)

    -- Pad input to match bitwidth if necessary
    if hex_len < bitwidth_hex_chars then
        hex_str = srep("0", bitwidth_hex_chars - hex_len) .. hex_str
        hex_len = bitwidth_hex_chars
    end

    -- Process in chunks of 16 hex characters (64 bits) for optimal LuaJIT performance
    local result_parts = {}
    local chunk_size = 16
    local num_chunks = math_ceil(hex_len / chunk_size)

    for i = 1, num_chunks do
        local end_pos = hex_len - (i - 1) * chunk_size
        local start_pos = end_pos - chunk_size + 1
        if start_pos < 1 then start_pos = 1 end

        local chunk = ssub(hex_str, start_pos, end_pos)

        -- Convert to number and perform bitwise NOT
        local num = hex_str_to_ull(chunk)
        local result = bit_bnot(num)

        -- Format back to hex string with proper padding
        local chunk_len = end_pos - start_pos + 1
        local hex_result = f("%x", result):lower()

        -- Truncate to chunk_len (bnot creates 64-bit result, we need only chunk_len)
        if #hex_result > chunk_len then
            hex_result = ssub(hex_result, -chunk_len)
        elseif #hex_result < chunk_len then
            hex_result = srep("0", chunk_len - #hex_result) .. hex_result
        end

        result_parts[num_chunks - i + 1] = hex_result
    end

    local result = table_concat(result_parts)

    -- Mask off extra bits in MSB nibble if bitwidth is not a multiple of 4
    local bitwidth_mod4 = effective_bitwidth % 4
    if bitwidth_mod4 ~= 0 then
        local mask = bit_lshift(1, bitwidth_mod4) - 1
        local first_nibble = tonumber(ssub(result, 1, 1), 16) or 0
        local masked_nibble = bit_band(first_nibble, mask)
        result = f("%x", masked_nibble) .. ssub(result, 2)
    end

    -- Handle result formatting based on bitwidth parameter
    if bitwidth then
        -- Ensure result matches bitwidth_hex_chars exactly
        local result_len = #result
        if result_len > bitwidth_hex_chars then
            result = ssub(result, -bitwidth_hex_chars)
        elseif result_len < bitwidth_hex_chars then
            result = srep("0", bitwidth_hex_chars - result_len) .. result
        end
        return result
    else
        return M.trim_leading_zeros(result)
    end
end

--- Perform addition operation on two hexadecimal strings.
--- Returns the result as a hexadecimal string and a carry flag.
---@param hex_str1 string: First hexadecimal string (without 0x prefix)
---@param hex_str2 string: Second hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional target bit width (if specified, result is truncated to this width)
---@return string result: Result as hexadecimal string (without 0x prefix)
---@return boolean carry: Whether there was a carry out from the MSB
function M.add_hex_str(hex_str1, hex_str2, bitwidth)
    -- Calculate target length based on inputs and bitwidth
    local len1, len2 = #hex_str1, #hex_str2
    local max_len = len1 > len2 and len1 or len2

    if bitwidth then
        bitwidth = tonumber(bitwidth) --[[@as integer]]

        local bitwidth_hex_chars = math_ceil(bitwidth / 4)
        if bitwidth_hex_chars > max_len then
            max_len = bitwidth_hex_chars
        end
        -- Mask inputs to fit within bitwidth
        hex_str1 = adjust_hex_bitwidth(hex_str1, bitwidth)
        hex_str2 = adjust_hex_bitwidth(hex_str2, bitwidth)
        -- Update lengths after masking
        len1, len2 = #hex_str1, #hex_str2
        max_len = len1 > len2 and len1 or len2
        if bitwidth_hex_chars > max_len then
            max_len = bitwidth_hex_chars
        end
    end

    -- Pad both strings to the same length
    if len1 < max_len then
        hex_str1 = srep("0", max_len - len1) .. hex_str1
    elseif len2 < max_len then
        hex_str2 = srep("0", max_len - len2) .. hex_str2
    end

    -- Process in chunks of 16 hex characters (64 bits) for optimal LuaJIT performance
    local result_parts = {}
    local chunk_size = 16
    local num_chunks = math_ceil(max_len / chunk_size)

    local carry = 0ULL

    -- Process from LSB to MSB (right to left)
    for i = num_chunks, 1, -1 do
        local end_pos = max_len - (num_chunks - i) * chunk_size
        local start_pos = end_pos - chunk_size + 1
        if start_pos < 1 then start_pos = 1 end

        local chunk1 = ssub(hex_str1, start_pos, end_pos)
        local chunk2 = ssub(hex_str2, start_pos, end_pos)

        -- Convert to numbers and perform addition with carry
        local num1 = hex_str_to_ull(chunk1)
        local num2 = hex_str_to_ull(chunk2)
        local sum = num1 + num2 + carry

        -- Determine chunk length and max value for this chunk
        local chunk_len = end_pos - start_pos + 1
        local max_chunk_val = (chunk_len >= 16) and 0xFFFFFFFFFFFFFFFFULL or bit_lshift(1ULL, chunk_len * 4) - 1ULL

        -- Check for carry out from this chunk
        local has_overflow = false
        if chunk_len >= 16 then
            -- For full 64-bit chunks, check if sum wrapped around
            if sum < num1 or (carry > 0ULL and sum <= num1) then
                has_overflow = true
            end
        else
            -- For partial chunks, check against max value
            if sum > max_chunk_val then
                has_overflow = true
            end
        end

        if has_overflow then
            carry = 1ULL
            if chunk_len >= 16 then
                -- For full chunks, sum is already wrapped, use it as-is
            else
                -- For partial chunks, subtract to get the wrapped value
                sum = sum - bit_lshift(1ULL, chunk_len * 4)
            end
        else
            carry = 0ULL
        end

        -- Format back to hex string with proper padding
        local hex_result = f("%x", sum):lower()
        -- Pad to chunk_len if necessary
        if #hex_result < chunk_len then
            hex_result = srep("0", chunk_len - #hex_result) .. hex_result
        end
        result_parts[i] = hex_result
    end

    -- If there's a final carry, prepend it
    local result
    local final_carry = carry > 0ULL
    if final_carry then
        result = "1" .. table_concat(result_parts)
    else
        result = table_concat(result_parts)
    end

    -- Handle bitwidth truncation if specified
    if bitwidth then
        local bitwidth_hex_chars = math_ceil(bitwidth / 4)
        local result_len = #result

        -- Check if result exceeds bitwidth
        local bitwidth_carry = false

        if final_carry then
            -- If we had a carry, the sum definitely exceeds bitwidth
            bitwidth_carry = true
            -- Remove the leading "1" from carry and truncate to bitwidth
            result = ssub(result, 2) -- Remove leading "1"
            if #result > bitwidth_hex_chars then
                result = ssub(result, -bitwidth_hex_chars)
            end
        elseif result_len > bitwidth_hex_chars then
            -- Result is longer than bitwidth even without explicit carry
            bitwidth_carry = true
            result = ssub(result, -bitwidth_hex_chars)
        end

        -- Now check if the truncated result still has bits beyond bitwidth
        -- We need to mask off any extra bits in the MSB nibble
        local bitwidth_mod4 = bitwidth % 4
        if bitwidth_mod4 ~= 0 then
            -- Need to mask the MSB nibble
            local first_nibble = tonumber(ssub(result, 1, 1), 16) or 0
            local mask = bit_lshift(1, bitwidth_mod4) - 1
            local masked_nibble = bit_band(first_nibble, mask)
            if first_nibble ~= masked_nibble then
                bitwidth_carry = true
            end
            result = f("%x", masked_nibble) .. ssub(result, 2)
        end

        -- Pad to bitwidth hex chars if needed
        if #result < bitwidth_hex_chars then
            result = srep("0", bitwidth_hex_chars - #result) .. result
        end

        return result, bitwidth_carry
    end

    -- Without bitwidth parameter, we extend the result naturally, so carry is always false
    return M.trim_leading_zeros(result), false
end

--- Count the number of '1' bits in a hexadecimal string.
---@param hex_str string
---@return integer
function M.popcount_hex_str(hex_str)
    local bin_str = utils.hex_to_bin(hex_str)
    return scount(bin_str, "1")
end

-- local s = os.clock()
-- for _ = 1, 10000 * 100 do
--     local ret = M.lshift_hex_str("1234", 10, 256)
--     -- assert(ret == "48d000")
-- end
-- local e = os.clock()
-- print(string.format("HSB time: %.2f", e - s))

return M

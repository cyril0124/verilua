---@diagnostic disable: unnecessary-assert

local bit = require "bit"
local math = require "math"

local f = string.format
local tonumber = tonumber
local math_ceil = math.ceil

local bit_band = bit.band
local bit_lshift = bit.lshift

local srep = string.rep
local ssub = string.sub

---@class (exact) verilua.utils.StrBitsUtils
local M = {}

---@nodiscard Return value should not be discarded
---@param bin_or_hex_str string
---@return string
function M.trim_leading_zeros(bin_or_hex_str)
    local len = #bin_or_hex_str
    local start = 1

    -- Iterate to find the first non-zero character
    while start <= len and ssub(bin_or_hex_str, start, start) == "0" do
        start = start + 1
    end

    if start > len then
        return "0"
    end

    return ssub(bin_or_hex_str, start)
end

-- Helper: Adjust binary string to specific bitwidth (truncate MSB or pad MSB)
---@nodiscard Return value should not be discarded
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

local HEX_VALS = {
    ['0'] = 0,
    ['1'] = 1,
    ['2'] = 2,
    ['3'] = 3,
    ['4'] = 4,
    ['5'] = 5,
    ['6'] = 6,
    ['7'] = 7,
    ['8'] = 8,
    ['9'] = 9,
    ['a'] = 10,
    ['b'] = 11,
    ['c'] = 12,
    ['d'] = 13,
    ['e'] = 14,
    ['f'] = 15,
    ['A'] = 10,
    ['B'] = 11,
    ['C'] = 12,
    ['D'] = 13,
    ['E'] = 14,
    ['F'] = 15
}

local VAL_HEXS = {
    [0] = '0',
    [1] = '1',
    [2] = '2',
    [3] = '3',
    [4] = '4',
    [5] = '5',
    [6] = '6',
    [7] = '7',
    [8] = '8',
    [9] = '9',
    [10] = 'a',
    [11] = 'b',
    [12] = 'c',
    [13] = 'd',
    [14] = 'e',
    [15] = 'f'
}

--- Mask hex string inputs to fit within specified bitwidth
---@nodiscard Return value should not be discarded
---@param hex_str string The hex string to mask
---@param bitwidth number The target bitwidth
---@return string The masked hex string
local function adjust_hex_bitwidth(hex_str, bitwidth)
    -- Calculate the required number of hex characters
    local bitwidth_hex_chars = math_ceil(bitwidth / 4)
    local len = #hex_str

    -- Truncate: if input is longer than needed, keep the suffix (least significant bits)
    if len > bitwidth_hex_chars then
        hex_str = ssub(hex_str, -bitwidth_hex_chars)
        len = bitwidth_hex_chars -- Update length to reflect the new string
    end

    -- Pad: if input is shorter, add leading zeros
    -- Only create a new string if padding is actually necessary
    if len < bitwidth_hex_chars then
        hex_str = srep("0", bitwidth_hex_chars - len) .. hex_str
    end

    -- Mask the Most Significant Nibble (first character) if bitwidth is not a multiple of 4
    local bitwidth_mod4 = bitwidth % 4
    ---@cast bitwidth_mod4 integer
    if bitwidth_mod4 ~= 0 then
        -- Extract the first character directly
        local first_char = ssub(hex_str, 1, 1)
        -- Fast lookup to get integer value (avoids tonumber conversion)
        local first_val = HEX_VALS[first_char] or 0

        -- Create mask: e.g., for mod 1 -> mask 1 (0x1); mod 3 -> mask 7 (0x7)
        local mask = bit_lshift(1, bitwidth_mod4) - 1
        local masked_val = bit_band(first_val, mask)

        -- Optimization: Only construct a new string if the value actually changes.
        -- This saves an allocation if the MSB bits were already zero.
        if masked_val ~= first_val then
            -- Fast char replacement using lookup table (avoids string.format)
            hex_str = VAL_HEXS[masked_val] .. ssub(hex_str, 2)
        end
    end

    return hex_str
end

--- Adjust hex string to specified bitwidth with bit-level precision
---@nodiscard Return value should not be discarded
---@param hex_str string The input hex string (without "0x" prefix)
---@param bitwidth integer The target bitwidth
---@return string The adjusted hex string
function M.adjust_hex_bitwidth(hex_str, bitwidth)
    return adjust_hex_bitwidth(hex_str, bitwidth)
end

--- Adjust binary string to specified bitwidth with bit-level precision
---@nodiscard Return value should not be discarded
---@param bin_str string The input binary string
---@param bitwidth integer The target bitwidth
---@return string The adjusted binary string
function M.adjust_bin_bitwidth(bin_str, bitwidth)
    return adjust_bin_bitwidth(bin_str, bitwidth)
end

-- Big-number backend: all wide operations delegate to the Rust bigint_ffi
-- library (shared/libbigint_ffi.so, num-bigint based). Each operation crosses
-- the FFI boundary exactly once per call (parse -> compute -> format happen
-- natively).
local ffi = require "ffi"
local ffi_string = ffi.string

ffi.cdef [[
    const char *vl_bigint_bitfield(const char *hex, uint64_t s, uint64_t e);
    const char *vl_bigint_set_bitfield(const char *hex, uint64_t s, uint64_t e, const char *val_hex);
    const char *vl_bigint_lshift(const char *hex, uint64_t n);
    const char *vl_bigint_rshift(const char *hex, uint64_t n);
    const char *vl_bigint_band(const char *a, const char *b);
    const char *vl_bigint_bor(const char *a, const char *b);
    const char *vl_bigint_bxor(const char *a, const char *b);
    const char *vl_bigint_add(const char *a, const char *b);
    const char *vl_bigint_bnot(const char *hex, uint64_t bitwidth);
    uint64_t vl_bigint_popcount(const char *hex);
]]

local verilua_home = assert(os.getenv("VERILUA_HOME"), "[StrBitsUtils] VERILUA_HOME is not set")
local clib = ffi.load(verilua_home .. "/shared/libbigint_ffi.so")

-- A NULL pointer from the native side means an input was not a valid hex
-- string; fail loudly instead of propagating garbage.
---@param ret ffi.cdata*
---@param what string
---@param hex_str string
---@param hex_str2 string?
---@return string
local function check_hex_ret(ret, what, hex_str, hex_str2)
    if ret == nil then
        assert(false, f(
            "[StrBitsUtils.%s] invalid hex string: %s%s",
            what, tostring(hex_str), hex_str2 and (" or " .. tostring(hex_str2)) or ""
        ))
    end
    return ffi_string(ret)
end

---@nodiscard Return value should not be discarded
---@param hex_str string The hexadecimal string without "0x" prefix
---@param s integer The start bit
---@param e integer The end bit
---@param bitwidth integer? The bitwidth of the input string (optional)
---@return string The hexadecimal string representation of the extracted bitfield
function M.bitfield_hex_str(hex_str, s, e, bitwidth)
    if s > e then
        assert(false, "[StrBitsUtils.bitfield_hex_str] s must be less than or equal to e")
    end

    -- If bitwidth is provided, ensure input is padded to bitwidth
    if bitwidth then
        hex_str = adjust_hex_bitwidth(hex_str, bitwidth)
    end

    local ret = check_hex_ret(clib.vl_bigint_bitfield(hex_str, s, e), "bitfield_hex_str", hex_str)
    -- Always trim leading zeros for the result
    return M.trim_leading_zeros(ret)
end

---@nodiscard Return value should not be discarded
---@param hex_str string The original hexadecimal string without "0x" prefix
---@param s integer The start bit
---@param e integer The end bit
---@param val_hex_str string The value to set in hexadecimal string format without "0x" prefix
---@param bitwidth integer? The bitwidth of the original string (optional)
---@return string The new hexadecimal string
function M.set_bitfield_hex_str(hex_str, s, e, val_hex_str, bitwidth)
    if s > e then
        assert(false, "[StrBitsUtils.set_bitfield_hex_str] s must be less than or equal to e")
    end

    local ret = check_hex_ret(
        clib.vl_bigint_set_bitfield(hex_str, s, e, val_hex_str),
        "set_bitfield_hex_str", hex_str, val_hex_str
    )
    if bitwidth then
        return adjust_hex_bitwidth(ret, bitwidth)
    else
        return M.trim_leading_zeros(ret)
    end
end

--- Left shift a hexadecimal string representation.
--- Mimics the behavior of `val << n`.
---@nodiscard Return value should not be discarded
---@param hex_str string: The input hexadecimal string.
---@param n integer: The number of bits to shift.
---@param bitwidth? integer: (Optional) Simulates a fixed-width register. Truncates overflow if set.
---@return string hex_str
function M.lshift_hex_str(hex_str, n, bitwidth)
    local ret = check_hex_ret(clib.vl_bigint_lshift(hex_str, n), "lshift_hex_str", hex_str)
    if bitwidth then
        return adjust_hex_bitwidth(ret, bitwidth)
    else
        return M.trim_leading_zeros(ret)
    end
end

--- Logical right shift a hexadecimal string representation.
--- Mimics the behavior of `val >> n` (Logical Shift, zero-filling MSB).
---@nodiscard Return value should not be discarded
---@param hex_str string: The input hexadecimal string.
---@param n integer: The number of bits to shift.
---@param bitwidth? integer: (Optional) Simulates a fixed-width register. Used for MSB padding.
---@return string hex_str
function M.rshift_hex_str(hex_str, n, bitwidth)
    -- For rshift with bitwidth, we need to first adjust input to bitwidth
    if bitwidth then
        hex_str = adjust_hex_bitwidth(hex_str, bitwidth)
    end

    local ret = check_hex_ret(clib.vl_bigint_rshift(hex_str, n), "rshift_hex_str", hex_str)
    if bitwidth then
        return adjust_hex_bitwidth(ret, bitwidth)
    else
        return M.trim_leading_zeros(ret)
    end
end

--- Perform bitwise OR operation on two hexadecimal strings.
--- Returns a hexadecimal string representing the result.
---@nodiscard Return value should not be discarded
---@param hex_str1 string: First hexadecimal string (without 0x prefix)
---@param hex_str2 string: Second hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional target bit width (result is truncated/padded to this width)
---@return string: Result as hexadecimal string (without 0x prefix)
function M.bor_hex_str(hex_str1, hex_str2, bitwidth)
    local ret = check_hex_ret(clib.vl_bigint_bor(hex_str1, hex_str2), "bor_hex_str", hex_str1, hex_str2)
    if bitwidth then
        return adjust_hex_bitwidth(ret, bitwidth)
    else
        return M.trim_leading_zeros(ret)
    end
end

--- Perform bitwise XOR operation on two hexadecimal strings.
--- Returns a hexadecimal string representing the result.
---@nodiscard Return value should not be discarded
---@param hex_str1 string: First hexadecimal string (without 0x prefix)
---@param hex_str2 string: Second hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional target bit width (result is truncated/padded to this width)
---@return string: Result as hexadecimal string (without 0x prefix)
function M.bxor_hex_str(hex_str1, hex_str2, bitwidth)
    local ret = check_hex_ret(clib.vl_bigint_bxor(hex_str1, hex_str2), "bxor_hex_str", hex_str1, hex_str2)
    if bitwidth then
        return adjust_hex_bitwidth(ret, bitwidth)
    else
        return M.trim_leading_zeros(ret)
    end
end

--- Perform bitwise AND operation on two hexadecimal strings.
--- Returns a hexadecimal string representing the result.
---@nodiscard Return value should not be discarded
---@param hex_str1 string: First hexadecimal string (without 0x prefix)
---@param hex_str2 string: Second hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional target bit width (result is truncated/padded to this width)
---@return string: Result as hexadecimal string (without 0x prefix)
function M.band_hex_str(hex_str1, hex_str2, bitwidth)
    local ret = check_hex_ret(clib.vl_bigint_band(hex_str1, hex_str2), "band_hex_str", hex_str1, hex_str2)
    if bitwidth then
        return adjust_hex_bitwidth(ret, bitwidth)
    else
        return M.trim_leading_zeros(ret)
    end
end

--- Perform bitwise NOT operation on a hexadecimal string.
--- Returns a hexadecimal string representing the result.
--- If bitwidth is not specified, the function assumes the bitwidth based on the input hex string length.
---@nodiscard Return value should not be discarded
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

    -- NOT within effective_bitwidth: value XOR ((1 << bitwidth) - 1)
    local ret = check_hex_ret(
        clib.vl_bigint_bnot(hex_str, effective_bitwidth),
        "bnot_hex_str", hex_str
    )

    if bitwidth then
        return adjust_hex_bitwidth(ret, bitwidth)
    else
        return M.trim_leading_zeros(ret)
    end
end

--- Perform addition operation on two hexadecimal strings.
--- Returns the result as a hexadecimal string and a carry flag.
---@nodiscard Return value should not be discarded
---@param hex_str1 string: First hexadecimal string (without 0x prefix)
---@param hex_str2 string: Second hexadecimal string (without 0x prefix)
---@param bitwidth integer?: Optional target bit width (if specified, result is truncated to this width)
---@return string result: Result as hexadecimal string (without 0x prefix)
---@return boolean carry: Carry flag (true when the sum overflows bitwidth; always false without bitwidth)
function M.add_hex_str(hex_str1, hex_str2, bitwidth)
    if bitwidth then
        bitwidth = tonumber(bitwidth) --[[@as integer]]
        -- Mask inputs to fit within bitwidth
        hex_str1 = adjust_hex_bitwidth(hex_str1, bitwidth)
        hex_str2 = adjust_hex_bitwidth(hex_str2, bitwidth)
    end

    local sum = check_hex_ret(clib.vl_bigint_add(hex_str1, hex_str2), "add_hex_str", hex_str1, hex_str2)

    if bitwidth then
        -- Mask the sum to bitwidth; if the masked value differs from the
        -- full sum, the addition overflowed (carry out of bitwidth).
        local ret = adjust_hex_bitwidth(sum, bitwidth)
        local carry = (M.trim_leading_zeros(ret) ~= sum)
        return ret, carry
    else
        return M.trim_leading_zeros(sum), false
    end
end

--- Legacy entry point kept as a no-op so existing call sites do not error.
---@deprecated Big-number operations always use the native Rust implementation; this call has no effect.
---@param _self verilua.utils.StrBitsUtils?
---@return verilua.utils.StrBitsUtils
function M.init_use_libgmp(_self)
    print(
        "[StrBitsUtils] Warning: init_use_libgmp() is deprecated and has no effect; " ..
        "big-number operations always use the native Rust implementation"
    )
    return M
end

--- Count the number of '1' bits in a hexadecimal string.
---@nodiscard Return value should not be discarded
---@param hex_str string
---@return integer
function M.popcount_hex_str(hex_str)
    local cnt = clib.vl_bigint_popcount(hex_str)
    if cnt == 0xFFFFFFFFFFFFFFFFULL then
        assert(false, f("[StrBitsUtils.popcount_hex_str] invalid hex string: %s", tostring(hex_str)))
    end
    return tonumber(cnt) --[[@as integer]]
end

return M

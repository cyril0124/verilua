---@diagnostic disable: unnecessary-assert

local ffi = require "ffi"
local bit = require "bit"
local math = require "math"
local class = require "pl.class"
local table_new = require "table.new"
local string_buffer = require "string.buffer"

local type = type
local print = print
local assert = assert
local bit_bor = bit.bor
local tonumber = tonumber
local bit_band = bit.band
local bit_bnot = bit.bnot
local bit_tohex = bit.tohex
local bit_rshift = bit.rshift
local bit_lshift = bit.lshift
local math_floor = math.floor
local math_max = math.max
local string_rep = string.rep
local string_sub = string.sub
local setmetatable = setmetatable

-- Lookup tables for to_hex_str optimization
local hex_digits = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f" }
local nibble_masks = { 0x1, 0x3, 0x7 } -- valid_bits: 1, 2, 3

---@class (exact) verilua.utils.SubBitVec
---@field __type string
---@field _s number
---@field _e number
---@field set fun(self: verilua.utils.SubBitVec, v: number|uint64_t)
---@field set_hex_str fun(self: verilua.utils.SubBitVec, hex_str: string)
---@field set_vec fun(self: verilua.utils.SubBitVec, v: table<number>)
---@field get fun(self: verilua.utils.SubBitVec): uint64_t
---@field get_hex_str fun(self: verilua.utils.SubBitVec): string
---@field get_vec fun(self: verilua.utils.SubBitVec): table<number>
---@field dump_str fun(self: verilua.utils.SubBitVec): string
---@field dump fun(self: verilua.utils.SubBitVec)
---@field value integer|ffi.cdata*|string

---@alias verilua.utils.BitVec.HexStr string

---@class (exact) verilua.utils.BitVec
---@overload fun(data: table<integer, integer>|ffi.cdata*|integer|string, bit_width?: integer): verilua.utils.BitVecInst
---@field private to_hex_str_buffer string.buffer
---@field __type string
---@field _call_cache table<string, verilua.utils.SubBitVec>
---@field u32_vec table<integer, integer>
---@field nr_u32_vec integer
---@field bit_width integer
---@field beat_size integer
---@field hex_str_len integer
---@field _update_u32_vec fun(self: verilua.utils.BitVec, data: integer|integer[])
---@field update_value fun(self: verilua.utils.BitVec, data: integer[]|integer|uint64_t|verilua.utils.BitVec.HexStr)
---@field get_bitfield fun(self: verilua.utils.BitVec, s: integer, e: integer): uint64_t
---@field get_bitfield_hex_str fun(self: verilua.utils.BitVec, s: integer, e: integer): string
---@field get_bitfield_vec fun(self: verilua.utils.BitVec, s: integer, e: integer): table<integer, integer>
---@field set_bitfield fun(self: verilua.utils.BitVec, s: integer, e: integer, v: integer|uint64_t)
---@field set_bitfield_hex_str fun(self: verilua.utils.BitVec, s: integer, e: integer, hex_str: verilua.utils.BitVec.HexStr)
---@field set_bitfield_vec fun(self: verilua.utils.BitVec, s: integer, e: integer, v: table<integer, integer>)
---@field _set_bitfield fun(self: verilua.utils.BitVec, s: integer, e: integer, v: integer|uint64_t): verilua.utils.BitVec
---@field _set_bitfield_hex_str fun(self: verilua.utils.BitVec, s: integer, e: integer, hex_str: verilua.utils.BitVec.HexStr): verilua.utils.BitVec
---@field _set_bitfield_vec fun(self: verilua.utils.BitVec, s: integer, e: integer, v: table<integer, integer>): verilua.utils.BitVec
---@field dump_str fun(self: verilua.utils.BitVec): string
---@field dump fun(self: verilua.utils.BitVec)
----@field to_hex_str fun(self: verilua.utils.BitVec): verilua.utils.BitVec.HexStr
---@field tonumber fun(self: verilua.utils.BitVec): integer
---@field tonumber64 fun(self: verilua.utils.BitVec): integer
local BitVec = class()

---@class (exact) verilua.utils.BitVecInst: verilua.utils.BitVec
---@overload fun(s: integer, e: integer): verilua.utils.SubBitVec

local function hex_str_to_u32_vec(hex_str)
    local hex_length = #hex_str
    local full_beats = math_floor(hex_length / 8)
    local u32_vec = table_new(full_beats, 0)

    for i = 0, full_beats - 1 do
        local start_index = hex_length - (i + 1) * 8 + 1
        -- local hex_part = hex_str:sub(start_index, start_index + 7)
        u32_vec[i + 1] = tonumber(hex_str:sub(start_index, start_index + 7), 16)
    end

    local remaining_chars = hex_length % 8
    if remaining_chars > 0 then
        -- local start_index = 1
        -- local hex_part = hex_str:sub(start_index, remaining_chars)
        u32_vec[full_beats + 1] = tonumber(hex_str:sub(1, remaining_chars), 16)
    end

    return u32_vec
end

local function get_hex_str_len(bit_width)
    return math_floor((bit_width + 3) / 4)
end

local function get_beat_size(bit_width)
    return math_floor((bit_width + 31) / 32)
end

--
-- Little Endian:
--  u32_vec: LSB {u32_0, u32_1, u32_2, u32_3, ...} MSB
--
function BitVec:_init(data, bit_width)
    local typ = type(data)
    local auto_bit_width

    self.__type = "BitVec"
    -- Cache for SubBitVec instances created via __call(s, e)
    -- Memory leak is not a concern because:
    -- 1. In typical usage, (s, e) combinations are limited (e.g., register fields)
    -- 2. Each BitVec instance has its own cache, which is freed when the BitVec is GC'd
    -- 3. Repeated calls with the same (s, e) will reuse cached SubBitVec instances
    self._call_cache = {}

    if typ == "table" then
        auto_bit_width = #data * 32
        if bit_width then
            local data_len = #data
            local beat_size = math_floor(math_floor(bit_width + 31) / 32)
            self.u32_vec = table_new(beat_size, 0)

            for i = 1, data_len do
                self.u32_vec[i] = data[i]
            end

            for i = data_len + 1, beat_size do
                self.u32_vec[i] = 0
            end

            if data_len > beat_size then
                assert(false, "Input u32_vec length: " .. data_len .. " must not exceed " .. beat_size)
            end

            self.bit_width = bit_width
        else
            self.u32_vec = data
            self.bit_width = auto_bit_width
        end
    elseif typ == "cdata" then
        if ffi.istype("uint64_t", data) then
            auto_bit_width = 64
            if bit_width then
                local beat_size = get_beat_size(bit_width)
                self.u32_vec = table_new(beat_size, 0) --[[@as table<integer, integer>]]

                self.u32_vec[1] = tonumber(bit_band(data, 0x00000000FFFFFFFFULL))
                if beat_size > 1 then
                    self.u32_vec[2] = tonumber(bit_rshift(data, 32))
                    for i = 3, beat_size do
                        self.u32_vec[i] = 0
                    end
                end

                self.bit_width = bit_width
            else
                self.u32_vec = table_new(2, 0) --[[@as table<integer, integer>]]
                self.u32_vec[1] = tonumber(bit_band(data, 0x00000000FFFFFFFFULL))
                self.u32_vec[2] = tonumber(bit_rshift(data, 32))
                self.bit_width = auto_bit_width
            end

            self.beat_size = get_beat_size(self.bit_width)
            if self.beat_size == 1 then
                self._update_u32_vec = function(t, data1)
                    ---@cast data1 integer
                    t.u32_vec[1] = data1
                end
            elseif self.beat_size > 1 then
                self._update_u32_vec = function(t, data1)
                    for i = 1, t.beat_size do
                        t.u32_vec[i] = data1[i]
                    end
                end
            end

            self.nr_u32_vec = #self.u32_vec
            self.to_hex_str_buffer = string_buffer.new()
            self.hex_str_len = get_hex_str_len(self.bit_width)

            self:_mask_unused_high_bits()

            self.tonumber = function(this)
                return tonumber(this.u32_vec[1]) --[[@as integer]]
            end

            if self.beat_size > 1 then
                self.tonumber64 = function(this)
                    return bit_lshift(this.u32_vec[2] + 0ULL, 32) + this.u32_vec[1]
                end
            else
                self.tonumber64 = function(this)
                    return this.u32_vec[1] + 0ULL
                end
            end

            return
        end

        local data_len = tonumber(data[0]) --[[@as integer]]
        auto_bit_width = data_len * 32

        if bit_width then
            local beat_size = get_beat_size(bit_width)
            self.u32_vec = table_new(beat_size, 0)

            for i = 1, data_len do
                self.u32_vec[i] = data[i]
            end

            for i = data_len + 1, beat_size do
                self.u32_vec[i] = 0
            end

            if data_len > beat_size then
                assert(false, "Input u32_vec length: " .. data_len .. " must not exceed " .. beat_size)
            end

            self.bit_width = bit_width
        else
            self.u32_vec = table_new(tonumber(data[0]) --[[@as integer]], 0)
            for i = 1, data_len do
                self.u32_vec[i] = data[i]
            end
            self.bit_width = auto_bit_width
        end
    elseif typ == "number" then
        ---@cast data integer
        auto_bit_width = 32
        if bit_width then
            local beat_size = get_beat_size(bit_width)

            self.u32_vec = table_new(beat_size, 0) --[[@as table<integer, integer>]]
            self.u32_vec[1] = data
            for i = 2, beat_size do
                self.u32_vec[i] = 0
            end

            self.bit_width = bit_width
        else
            self.u32_vec = { data }
            self.bit_width = auto_bit_width
        end
    elseif typ == "string" then
        auto_bit_width = #data * 4
        if bit_width then
            local hex_str = data
            local hex_str_len = get_hex_str_len(bit_width)

            if #hex_str > hex_str_len then
                assert(false, "Input hex_str length: " .. #hex_str .. " must not exceed " .. hex_str_len)
            end

            if hex_str_len > #hex_str then
                hex_str = string_rep("0", hex_str_len - #hex_str) .. hex_str
            end

            self.u32_vec = hex_str_to_u32_vec(hex_str)
            self.bit_width = bit_width
        else
            self.u32_vec = hex_str_to_u32_vec(data)
            self.bit_width = auto_bit_width
        end
    else
        assert(false, "Unsupported type: " .. typ)
    end

    self.nr_u32_vec = #self.u32_vec
    self.to_hex_str_buffer = string_buffer.new()
    self.hex_str_len = get_hex_str_len(self.bit_width)

    self.beat_size = get_beat_size(self.bit_width)
    if self.beat_size == 1 then
        self._update_u32_vec = function(t, data1)
            ---@cast data1 integer
            t.u32_vec[1] = data1
        end
    elseif self.beat_size > 1 then
        self._update_u32_vec = function(t, data1)
            for i = 1, t.beat_size do
                t.u32_vec[i] = data1[i]
            end
        end
    end

    self.tonumber = function(this)
        return tonumber(this.u32_vec[1]) --[[@as integer]]
    end

    if self.beat_size > 1 then
        self.tonumber64 = function(this)
            return bit_lshift(this.u32_vec[2] + 0ULL, 32) + this.u32_vec[1]
        end
    else
        self.tonumber64 = function(this)
            return this.u32_vec[1] + 0ULL
        end
    end

    self:_mask_unused_high_bits()
end

--- Ensure unused high bits above `bit_width` are always zero.
--- This keeps bit-precise semantics consistent for all constructors and updates.
function BitVec:_mask_unused_high_bits()
    local beat_size = self.beat_size or #self.u32_vec
    if beat_size <= 0 then
        return
    end

    local valid_bits_in_top = self.bit_width % 32
    if valid_bits_in_top == 0 then
        return
    end

    local top_index = beat_size
    local mask = bit_lshift(1ULL, valid_bits_in_top) - 1
    self.u32_vec[top_index] = tonumber(bit_band((self.u32_vec[top_index] or 0) + 0ULL, mask))
end

function BitVec:update_value(data)
    local typ = type(data)

    if typ == "table" then
        local data_len = #data
        local beat_size = #self.u32_vec

        local t = type(data[1])
        if t ~= "number" then
            assert(false, "Unsupported type: " .. t)
        end

        if data_len > beat_size then
            assert(false, "Input u32_vec length: " .. data_len .. " must not exceed " .. beat_size)
        end

        for i = 1, data_len do
            self.u32_vec[i] = data[i]
        end

        for i = data_len + 1, beat_size do
            self.u32_vec[i] = 0
        end
    elseif typ == "cdata" then
        if ffi.istype("uint64_t", data) then
            ---@cast data integer
            local beat_size = #self.u32_vec

            self.u32_vec[1] = tonumber(bit_band(data, 0x00000000FFFFFFFFULL))

            if beat_size > 1 then
                self.u32_vec[2] = tonumber(bit_rshift(data, 32))

                for i = 3, beat_size do
                    self.u32_vec[i] = 0
                end
            end
        else
            assert(false, "Unsupported type: " .. typ .. ", cdata must be uint64_t")
        end
    elseif typ == "number" then
        local beat_size = #self.u32_vec

        self.u32_vec[1] = data

        for i = 2, beat_size do
            self.u32_vec[i] = 0
        end
    elseif typ == "string" then
        local hex_str = data
        local hex_str_len = get_hex_str_len(self.bit_width)

        if #hex_str > hex_str_len then
            assert(false, "Input hex_str length: " .. #hex_str .. " must not exceed " .. hex_str_len)
        end

        if hex_str_len > #hex_str then
            hex_str = string_rep("0", hex_str_len - #hex_str) .. hex_str
        end

        self.u32_vec = hex_str_to_u32_vec(hex_str)
    else
        assert(false, "Unsupported type: " .. typ)
    end

    self:_mask_unused_high_bits()
    self.nr_u32_vec = #self.u32_vec
end

function BitVec:get_bitfield(s, e)
    assert((e - s) <= 63, "Bitfield size must not exceed 64 bits")

    local start_beat_id = math_floor(s / 32) + 1
    local end_beat_id = math_floor(e / 32) + 1

    local start_bit = s % 32
    local end_bit = e % 32

    local u32_vec = self.u32_vec
    local value = 0ULL
    local mask = 0ULL

    for i = start_beat_id, end_beat_id do
        local u32 = u32_vec[i] or 0

        if i == start_beat_id then
            if start_beat_id == end_beat_id then
                -- mask = 0xFFFFFFFFULL >> (31 - end_bit)
                -- value = (u32 & mask) >> start_bit

                mask = bit_rshift(0xFFFFFFFFULL, 31 - end_bit)
                value = bit_rshift(bit_band(u32, mask), start_bit)
            else
                -- mask = 0xFFFFFFFFULL >> start_bit
                -- value = (((u32 + 0ULL) >> start_bit) & mask) | value

                mask = bit_rshift(0xFFFFFFFFULL, start_bit)
                value = bit_bor(value, bit_band(bit_rshift(u32 + 0ULL, start_bit), mask))
            end
        elseif i == end_beat_id then
            -- mask = (1ULL << (end_bit + 1)) - 1
            -- mask = mask & 0xFFFFFFFFULL
            -- value = (((u32 + 0ULL) & mask) << ((i - 1) * 32 - s)) | value

            mask = bit_lshift(1ULL, end_bit + 1) - 1
            mask = bit_band(mask, 0xFFFFFFFFULL)
            value = bit_bor(value, bit_lshift(bit_band(u32 + 0ULL, mask), (i - 1) * 32 - s))
        else
            -- value = ((u32 + 0ULL) << ((i - 1) * 32 - s)) | value

            value = bit_bor(value, bit_lshift(u32 + 0ULL, ((i - 1) * 32 - s)))
        end
    end

    return value --[[@as uint64_t]]
end

function BitVec:get_bitfield_hex_str(s, e)
    local beat_size = math_floor((e - s) / 32) + 1

    local result = ""
    if beat_size == 1 then
        result = bit_tohex(tonumber(self:get_bitfield(s, e)) --[[@as integer]])
    else
        local ss = s
        local ee = s + 31
        for _i = 1, beat_size - 1 do
            result = bit_tohex(tonumber(self:get_bitfield(ss, ee)) --[[@as integer]]) .. result
            ss = ee + 1
            ee = ee + 32
        end
        result = bit_tohex(tonumber(self:get_bitfield(ss, e)) --[[@as integer]]) .. result
    end

    return result
end

function BitVec:get_bitfield_vec(s, e)
    local beat_size = math_floor((e - s) / 32) + 1

    local result = table_new(beat_size, 0) --[[@as table<integer, integer>]]
    if beat_size == 1 then
        result[1] = tonumber(self:get_bitfield(s, e))
    else
        local ss = s
        local ee = s + 31
        for i = 1, beat_size - 1 do
            result[i] = tonumber(self:get_bitfield(ss, ee))
            ss = ee + 1
            ee = ee + 32
        end
        result[beat_size] = tonumber(self:get_bitfield(ss, e))
    end

    return result
end

function BitVec:set_bitfield(s, e, v)
    assert((e - s) <= 63, "Bitfield size must not exceed 64 bits")

    local start_beat_id = math_floor(s / 32) + 1
    local end_beat_id = math_floor(e / 32) + 1

    local start_bit = s % 32
    local end_bit = e % 32

    local u32_vec = self.u32_vec
    local mask = 0ULL
    local vmask = 0ULL
    local masked_v = 0ULL

    for i = start_beat_id, end_beat_id do
        local u32 = u32_vec[i] or 0

        if i == start_beat_id then
            if start_beat_id == end_beat_id then
                -- mask = ~(((1ULL << (end_bit - start_bit + 1)) - 1) << start_bit)
                -- vmask = (1ULL << (end_bit - start_bit + 1)) - 1
                -- masked_v = (v + 0ULL) & vmask
                -- u32 = (u32 & mask) | (masked_v << start_bit)

                mask = bit_bnot(bit_lshift(bit_lshift(1ULL, end_bit - start_bit + 1) - 1, start_bit))
                vmask = bit_lshift(1ULL, end_bit - start_bit + 1) - 1
                masked_v = bit_band((v + 0ULL) --[[@as integer]], vmask)
                u32 = bit_bor(bit_band(u32, mask), bit_lshift(masked_v, start_bit))
            else
                -- mask = ~(((1ULL << (31 - start_bit)) - 1) << start_bit)
                -- vmask = (1ULL << (32 - start_bit)) - 1
                -- masked_v = (v + 0ULL) & vmask
                -- u32 = (u32 & mask) | (masked_v << start_bit)

                mask = bit_bnot(bit_lshift(bit_lshift(1ULL, 31 - start_bit) - 1, start_bit))
                vmask = bit_lshift(1ULL, 32 - start_bit) - 1
                masked_v = bit_band((v + 0ULL) --[[@as integer]], vmask)
                u32 = bit_bor(bit_band(u32, mask), bit_lshift(masked_v, start_bit))
            end
        elseif i == end_beat_id then
            -- mask = ~((1ULL << (end_bit + 1)) - 1)
            -- vmask = (1ULL << (end_bit + 1)) - 1
            -- masked_v = ((v + 0ULL) >> ((i - 1) * 32 - s)) & vmask
            -- u32 = (u32 & mask) | masked_v

            mask = bit_bnot(bit_lshift(1ULL, end_bit + 1) - 1)
            vmask = bit_lshift(1ULL, end_bit + 1) - 1
            masked_v = bit_band(bit_rshift((v + 0ULL) --[[@as integer]], (i - 1) * 32 - s), vmask)
            u32 = bit_bor(bit_band(u32, mask), masked_v)
        else
            -- masked_v = ((v + 0ULL) >> (32 - start_bit)) & 0xFFFFFFFFULL
            -- u32 = (u32 & 0ULL) | masked_v

            masked_v = bit_band(bit_rshift((v + 0ULL) --[[@as integer]], 32 - start_bit), 0xFFFFFFFFULL)
            u32 = bit_bor(bit_band(u32, 0ULL), masked_v)
        end

        u32_vec[i] = tonumber(u32)
    end
end

function BitVec:set_bitfield_hex_str(s, e, hex_str)
    self:set_bitfield_vec(s, e, hex_str_to_u32_vec(hex_str))
end

function BitVec:set_bitfield_vec(s, e, u32_vec)
    local beat_size = math_floor((e - s) / 32) + 1

    local start_beat_id = math_floor(s / 32) + 1
    local end_beat_id = math_floor(e / 32) + 1
    assert(beat_size == #u32_vec)

    if start_beat_id == end_beat_id then
        self:set_bitfield(s, e, u32_vec[1])
    else
        if beat_size == 1 then
            self:set_bitfield(s, e, u32_vec[1])
        else
            local ss = s
            local ee = s + 31
            for i = 1, beat_size - 1 do
                self:set_bitfield(ss, ee, u32_vec[i])
                ss = ee + 1
                ee = ee + 32
            end
            local vmask = bit_lshift(1ULL, e - ss + 1) - 1
            local masked_v = bit_band(u32_vec[beat_size], vmask)
            self:set_bitfield(ss, e, masked_v --[[@as uint64_t]])
        end
    end
end

function BitVec:_set_bitfield(s, e, v)
    self:set_bitfield(s, e, v)
    return self
end

function BitVec:_set_bitfield_hex_str(s, e, hex_str)
    self:set_bitfield_hex_str(s, e, hex_str)
    return self
end

function BitVec:_set_bitfield_vec(s, e, u32_vec)
    self:set_bitfield_vec(s, e, u32_vec)
    return self
end

---@nodiscard Return value should not be discarded
---@return verilua.utils.BitVec.HexStr
function BitVec:dump_str()
    return self:to_hex_str()
end

function BitVec:dump()
    print(self:dump_str())
end

function BitVec:__tostring()
    return self:dump_str()
end

--- Convert BitVec to hexadecimal string (MSB to LSB)
---
--- The returned string represents the BitVec value with MSB (Most Significant Byte) first,
--- which is the natural left-to-right reading order for humans.
---
--- **Internal Storage (Little Endian):**
---   u32_vec: LSB {u32_0, u32_1, u32_2, ...} MSB
---   - u32_vec[1] contains the least significant 32 bits
---   - u32_vec[n] contains the most significant 32 bits
---
--- **Output Format (Big Endian for readability):**
---   Returns: "MSB...LSB" (hex string)
---   - Most significant byte first
---   - Each u32 is formatted as 8 hex digits (zero-padded)
---
--- **Examples:**
--- ```lua
---   -- Single u32 (32 bits)
---   local bv = BitVec(0x12345678)
---   bv:to_hex_str()  -- Returns: "12345678"
---
---   -- Multiple u32 (64 bits)
---   local bv = BitVec({ 0x12345678, 0x9ABCDEF0 })
---   -- u32_vec[1] = 0x12345678 (LSB)
---   -- u32_vec[2] = 0x9ABCDEF0 (MSB)
---   bv:to_hex_str()  -- Returns: "9abcdef012345678"
---
---   -- From hex string
---   local bv = BitVec("aabbccdd")
---   bv:to_hex_str()  -- Returns: "aabbccdd"
---
---   -- With different bit widths
---   local bv = BitVec(0x12345678, 28)  -- bit_width = 28
---   -- to_hex_str respects bit_width and keeps only valid bits
---   bv:to_hex_str()  -- Returns: "2345678"
---
---   local bv2 = BitVec(0xFFFFFFFF, 30)
---   bv2:to_hex_str() -- Returns: "3fffffff"
--- ```
---
---@nodiscard Return value should not be discarded
---@return verilua.utils.BitVec.HexStr Hexadecimal string (MSB first)
function BitVec:to_hex_str()
    local hex_str = self:to_hex_str_1()
    local hex_str_len = self.hex_str_len

    if #hex_str > hex_str_len then
        hex_str = string_sub(hex_str, #hex_str - hex_str_len + 1)
    end

    local valid_bits = self.bit_width % 4
    if valid_bits ~= 0 and #hex_str > 0 then
        -- Use lookup tables to avoid string.format and bit_lshift + tonumber overhead
        local top_nibble = tonumber(string_sub(hex_str, 1, 1), 16) or 0
        ---@cast valid_bits 1|2|3
        top_nibble = bit_band(top_nibble, nibble_masks[valid_bits])
        hex_str = hex_digits[top_nibble + 1] .. string_sub(hex_str, 2)
    end

    return hex_str
end

--- Converts BitVec to hexadecimal string without trimming to bit_width.
--- Note: This always returns full 32-bit aligned hex (may include leading zeros).
---
--- Performance note:
--- - to_hex_str_1 is faster than to_hex_str because it writes fixed-width 32-bit chunks
---   directly into the string buffer and returns the result as-is.
--- - to_hex_str performs extra work (trimming to bit_width, top-nibble masking and string
---   slicing), which adds branching, string operations and small allocations.
---
---@nodiscard Return value should not be discarded
---@return verilua.utils.BitVec.HexStr Hexadecimal string (MSB first, full 32-bit aligned)
function BitVec:to_hex_str_1()
    local buffer = self.to_hex_str_buffer
    local nr_u32_vec = self.nr_u32_vec or #self.u32_vec
    for i = nr_u32_vec, 1, -1 do
        buffer:putf("%08x", self.u32_vec[i])
    end
    return buffer:get()
end

function BitVec:__concat(other)
    assert(false, "TODO:")
end

function BitVec:__eq(other)
    local max_len = math_max(#self.u32_vec, #other.u32_vec)
    for i = 1, max_len do
        local self_val = self.u32_vec[i] or 0
        local other_val = other.u32_vec[i] or 0
        if self_val ~= other_val then
            return false
        end
    end
    return true
end

function BitVec:__len()
    return self.bit_width
end

local subbitvec_shared_mt = {
    __newindex = function(t, k, v)
        local typ = type(v)
        if k == "value" then
            if typ == "number" then
                t:set(v)
            elseif typ == "cdata" then
                if not ffi.istype("uint64_t", v) then
                    assert(false, "Unsupported type: " .. typ)
                end
                t:set(v)
            elseif typ == "string" then
                t:set_hex_str(v)
            end
        else
            assert(false, "Unknown key: " .. k)
        end
    end,

    __tostring = function(t)
        return t:dump_str()
    end,

    __eq = function(t, other)
        return t:dump_str() == other:dump_str()
    end,

    __len = function(t)
        return t._e - t._s + 1
    end,

    -- TODO: concat
}

function BitVec:__call(s, e)
    ---@type string
    local key = s .. "_" .. e

    if not self._call_cache[key] then
        ---@type verilua.utils.SubBitVec
        local sub_bit_vec = setmetatable({
            __type = "SubBitVec",
            _s = s,
            _e = e,

            set = function(t, v)
                self:set_bitfield(t._s, t._e, v)
            end,

            set_hex_str = function(t, hex_str)
                self:set_bitfield_hex_str(t._s, t._e, hex_str)
            end,

            set_vec = function(t, u32_vec)
                self:set_bitfield_vec(t._s, t._e, u32_vec)
            end,

            get = function(t)
                return self:get_bitfield(t._s, t._e)
            end,

            get_hex_str = function(t)
                return self:get_bitfield_hex_str(t._s, t._e)
            end,

            get_vec = function(t)
                return self:get_bitfield_vec(t._s, t._e)
            end,

            dump_str = function(t)
                return self:get_bitfield_hex_str(t._s, t._e)
            end,

            dump = function(_t)
                print(self:dump_str())
            end
        }, subbitvec_shared_mt)

        self._call_cache[key] = sub_bit_vec
    end
    return self._call_cache[key]
end

return BitVec

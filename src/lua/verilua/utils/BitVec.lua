local ffi = require "ffi"
local bit = require "bit"
local math = require "math"
local utils = require "LuaUtils"
local class = require "pl.class"
local table_new = require "table.new"

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
local to_hex_str = utils.to_hex_str

local BitVec = class()

local function hex_str_to_u32_vec(hex_str)
    local hex_length = #hex_str
    local full_beats = math_floor(hex_length / 8)
    local u32_vec = table_new(full_beats, 0)

    for i = 0, full_beats - 1 do
        local start_index = hex_length - (i + 1) * 8 + 1
        local hex_part = hex_str:sub(start_index, start_index + 7)
        u32_vec[i + 1] = tonumber(hex_part, 16)
    end

    local remaining_chars = hex_length % 8
    if remaining_chars > 0 then
        local start_index = 1
        local hex_part = hex_str:sub(start_index, remaining_chars)
        u32_vec[full_beats + 1] = tonumber(hex_part, 16)
    end

    return u32_vec
end

-- 
-- Little Endian:
--  u32_vec: LSB {u32_0, u32_1, u32_2, u32_3, ...} MSB
-- 
function BitVec:_init(data, bit_width)
    local typ = type(data)
    local auto_bit_width

    if typ == "table" then
        self.u32_vec = data
        auto_bit_width = #data * 32
    elseif typ == "cdata" then
        if ffi.istype("uint64_t", data) then
            assert(false, "Unsupported type: cdata(uint64_t)")
        end
        
        self.u32_vec = data
        auto_bit_width = data[0] * 32
    elseif typ == "string" then
        self.u32_vec = hex_str_to_u32_vec(data)
        auto_bit_width = #data * 4
    else
        assert(false, "Unsupported type: " .. typ)
    end

    if bit_width then
        if bit_width > auto_bit_width then
            assert(false, "Bit width must not exceed " .. auto_bit_width .. " bits")
        end
        self.bit_width = bit_width
    else
        self.bit_width = auto_bit_width
    end
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
        local u32 = u32_vec[i] or 0ULL

        if i == start_beat_id then
            if start_beat_id == end_beat_id then
                mask = bit_rshift(0xFFFFFFFFULL, 31 - end_bit)
                value = bit_rshift(bit_band(u32, mask), start_bit)
            else
                mask = bit_rshift(0xFFFFFFFFULL, start_bit)
                value = bit_bor(value, bit_band(bit_rshift(u32 + 0ULL, start_bit), mask))
            end
        elseif i == end_beat_id then
            mask = bit_lshift(1ULL, end_bit + 1) - 1
            mask = bit_band(mask, 0xFFFFFFFFULL)
            value = bit_bor(value, bit_lshift(bit_band(u32 + 0ULL, mask), (i - 1) * 32 - s))
        else
            value = bit_bor(value, bit_lshift(u32 + 0ULL, ((i - 1) * 32 - s)))
        end
    end

    return value
end

function BitVec:get_bitfield_hex_str(s, e)
    local beat_size = math_floor((e - s) / 32) + 1
    
    local result = ""
    if beat_size == 1 then
        result = bit_tohex(tonumber(self:get_bitfield(s, e)))
    else
        local ss = s
        local ee = s + 31
        for i = 1, beat_size - 1 do
            result = bit_tohex(tonumber(self:get_bitfield(ss, ee))) .. result
            ss = ee + 1
            ee = ee + 32
        end
        result = bit_tohex(tonumber(self:get_bitfield(ss, e))) .. result
    end

    return result
end

function BitVec:get_bitfield_vec(s, e)
    local beat_size = math_floor((e - s) / 32) + 1

    local result = table_new(beat_size, 0)
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

    local start_beat_id = math.floor(s / 32) + 1
    local end_beat_id = math.floor(e / 32) + 1

    local start_bit = s % 32
    local end_bit = e % 32

    local u32_vec = self.u32_vec
    local mask = 0ULL
    local vmask = 0ULL
    local masked_v = 0ULL

    for i = start_beat_id, end_beat_id do
        local u32 = u32_vec[i] or 0ULL

        if i == start_beat_id then
            if start_beat_id == end_beat_id then
                mask = bit_bnot(bit_lshift(bit_lshift(1ULL, end_bit - start_bit + 1) - 1, start_bit))
                vmask = bit_lshift(1ULL, end_bit - start_bit + 1) - 1
                masked_v = bit_band(v + 0ULL, vmask)
                u32 = bit_bor(bit_band(u32, mask), bit_lshift(masked_v, start_bit))
            else
                mask = bit_bnot(bit_lshift(bit_lshift(1ULL, start_bit - 31) - 1, start_bit))
                vmask = bit_lshift(1ULL, 32 - start_bit) - 1
                masked_v = bit_band(v + 0ULL, vmask)
                u32 = bit_bor(bit_band(u32, mask), bit_lshift(masked_v, start_bit))
            end
        elseif i == end_beat_id then
            mask = bit_bnot(bit_lshift(1ULL, end_bit + 1) - 1)
            vmask = bit_lshift(1ULL, end_bit + 1) - 1
            masked_v = bit_band(bit_rshift(v + 0ULL, (i - 1) * 32 - s), vmask)
            u32 = bit_bor(bit_band(u32, mask), masked_v)
        else
            masked_v = bit_band(bit_rshift(v + 0ULL, 32 - start_bit), 0xFFFFFFFFULL)
            u32 = bit_bor(bit_band(u32, 0ULL), masked_v)
        end

        u32_vec[i] = u32
    end
end

function BitVec:set_bitfield_hex_str(s, e, hex_str)
    self:set_bitfield_vec(s, e, hex_str_to_u32_vec(hex_str))
end

function BitVec:set_bitfield_vec(s, e, u32_vec)
    local beat_size = math_floor((e - s) / 32) + 1

    local start_beat_id = math.floor(s / 32) + 1
    local end_beat_id = math.floor(e / 32) + 1
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
            self:set_bitfield(ss, e, masked_v)
        end
    end
end

function BitVec:dump_str(reverse)
    return to_hex_str(self.u32_vec, reverse)
end

function BitVec:dump(reverse)
    print(self:dump_str(reverse))
end

return BitVec
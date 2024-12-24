local ffi = require "ffi"
local bit = require "bit"
local math = require "math"
local class = require "pl.class"

local type = type
local assert = assert
local bit_bor = bit.bor
local bit_band = bit.band
local bit_bnot = bit.bnot
local bit_rshift = bit.rshift
local bit_lshift = bit.lshift
local math_floor = math.floor

local BitVec = class()

-- 
-- Little Endian:
--  u32_vec: LSB {u32_0, u32_1, u32_2, u32_3, ...} MSB
-- 
function BitVec:_init(data, bit_width)
    local typ = type(data)

    if typ == "table" then
        self.u32_vec = data

        local auto_bit_width = (#data * 32)
        if bit_width then
            if bit_width > auto_bit_width then
                assert(false, "Bit width must not exceed " .. auto_bit_width .. " bits")
            end
            self.bit_width = bit_width
        else
            self.bit_width = auto_bit_width
        end
    elseif typ == "cdata" then
        if ffi.istype("uint64_t", data) then
            assert(false, "Unsupported type: cdata(uint64_t)")
        end
        
        self.u32_vec = data

        local auto_bit_width = data[0] * 32
        if bit_width then
            if bit_width > auto_bit_width then
                assert(false, "Bit width must not exceed " .. auto_bit_width .. " bits")
            end
            self.bit_width = bit_width
        else
            self.bit_width = auto_bit_width
        end
    elseif typ == "string" then
        assert(false, "TODO: from_hex_str")
    else
        assert(false, "Unsupported type: " .. typ)
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
    assert(false, "TODO: get_bitfield_hex_str")
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

function BitVec:set_bitfield_hex_str(s, e, v_str)
    assert(false, "TODO: set_bitfield_hex_str")
end

return BitVec
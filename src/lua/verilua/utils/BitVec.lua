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
local string_rep = string.rep
local setmetatable = setmetatable
local to_hex_str = utils.to_hex_str

---@class (exact) SubBitVec
---@field __type string
---@field _s number
---@field _e number
---@field set fun(self: SubBitVec, v: number|uint64_t)
---@field set_hex_str fun(self: SubBitVec, hex_str: string)
---@field set_vec fun(self: SubBitVec, v: table<number>)
---@field get fun(self: SubBitVec): uint64_t
---@field get_hex_str fun(self: SubBitVec): string
---@field get_vec fun(self: SubBitVec): table<number>
---@field dump_str fun(self: SubBitVec): string
---@field dump fun(self: SubBitVec)

---@class (exact) BitVec
---@overload fun(data: table<number>|ffi.cdata*|number|string, bit_width?: number): BitVecInst
---@field __type string
---@field _call_cache table<string, SubBitVec>
---@field u32_vec table<number>
---@field bit_width number
---@field beat_size number
---@field _update_u32_vec fun(self: BitVec, data: table<number>)
---@field update_value fun(self: BitVec, data: table<number>)
---@field get_bitfield fun(self: BitVec, s: number, e: number): uint64_t
---@field get_bitfield_hex_str fun(self: BitVec, s: number, e: number): string
---@field get_bitfield_vec fun(self: BitVec, s: number, e: number): table<number>
---@field set_bitfield fun(self: BitVec, s: number, e: number, v: number|uint64_t)
---@field set_bitfield_hex_str fun(self: BitVec, s: number, e: number, hex_str: string)
---@field set_bitfield_vec fun(self: BitVec, s: number, e: number, v: table<number>)
---@field _set_bitfield fun(self: BitVec, s: number, e: number, v: number|uint64_t): BitVec
---@field _set_bitfield_hex_str fun(self: BitVec, s: number, e: number, hex_str: string): BitVec
---@field _set_bitfield_vec fun(self: BitVec, s: number, e: number, v: table<number>): BitVec
---@field dump_str fun(self: BitVec): string
---@field dump fun(self: BitVec)
---@field to_hex_str fun(self: BitVec): string
---@field tonumber fun(self: BitVec): number
---@field tonumber64 fun(self: BitVec): number
local BitVec = class()

---@class (exact) BitVecInst: BitVec
---@overload fun(s: number, e: number): SubBitVec

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

-- 
-- Little Endian:
--  u32_vec: LSB {u32_0, u32_1, u32_2, u32_3, ...} MSB
-- 
function BitVec:_init(data, bit_width)
    local typ = type(data)
    local auto_bit_width

    self.__type = "BitVec"
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
            assert(false, "Unsupported type: cdata(uint64_t)")
        end

        local data_len = tonumber(data[0])
        auto_bit_width = data_len * 32

        if bit_width then
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
            self.u32_vec = table_new(tonumber(data[0]) --[[@as number]], 0)
            for i  = 1, data_len do
                self.u32_vec[i] = data[i]
            end
            self.bit_width = auto_bit_width
        end
    elseif typ == "number" then
        auto_bit_width = 32
        if bit_width then
            local beat_size = math_floor(math_floor(bit_width + 31) / 32)

            self.u32_vec = table_new(beat_size, 0)
            self.u32_vec[1] = data
            for i = 2, beat_size do
                self.u32_vec[i] = 0
            end

            self.bit_width = bit_width
        else
            self.u32_vec = {data}
            self.bit_width = auto_bit_width
        end
    elseif typ == "string" then
        auto_bit_width = #data * 4
        if bit_width then
            local hex_str = data
            local hex_str_len = math_floor(math_floor(bit_width + 3) / 4)

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

    self.beat_size = math_floor(math_floor(self.bit_width + 31) / 32)
    if self.beat_size == 1 then
        self._update_u32_vec = function (t, data)
            t.u32_vec[1] = data
        end
    elseif self.beat_size > 1 then
        self._update_u32_vec = function (t, data)
            for i = 1, t.beat_size do
                t.u32_vec[i] = data[i]
            end
        end
    end

    self.tonumber = function (this)
        return tonumber(this.u32_vec[1]) --[[@as number]]
    end

    if self.beat_size > 1 then
        self.tonumber64 = function (this)
            return bit_lshift(this.u32_vec[2] + 0ULL, 32) + this.u32_vec[1]
        end
    else
        self.tonumber64 = function (this)
            return this.u32_vec[1] + 0ULL
        end
    end
end

function BitVec:update_value(data)
    local typ = type(data)

    if typ == "table" then
        local data_len = #data
        local beat_size = #self.u32_vec

        for i = 1, data_len do
            self.u32_vec[i] = data[i]
        end

        for i = data_len + 1, beat_size do
            self.u32_vec[i] = 0
        end
    elseif typ == "cdata" then
        assert(false, "TODO: cdata")
    elseif typ == "number" then
        local beat_size = #self.u32_vec

        self.u32_vec[1] = data

        for i = 2, beat_size do
            self.u32_vec[i] = 0
        end
    elseif typ == "string" then
        local hex_str = data
        local hex_str_len = math_floor(math_floor(self.bit_width + 3) / 4)

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
        result = bit_tohex(tonumber(self:get_bitfield(s, e)) --[[@as number]])
    else
        local ss = s
        local ee = s + 31
        for i = 1, beat_size - 1 do
            result = bit_tohex(tonumber(self:get_bitfield(ss, ee)) --[[@as number]]) .. result
            ss = ee + 1
            ee = ee + 32
        end
        result = bit_tohex(tonumber(self:get_bitfield(ss, e)) --[[@as number]]) .. result
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
                masked_v = bit_band(v + 0ULL, vmask)
                u32 = bit_bor(bit_band(u32, mask), bit_lshift(masked_v, start_bit))
            else
                -- mask = ~(((1ULL << (31 - start_bit)) - 1) << start_bit)
                -- vmask = (1ULL << (32 - start_bit)) - 1
                -- masked_v = (v + 0ULL) & vmask
                -- u32 = (u32 & mask) | (masked_v << start_bit)

                mask = bit_bnot(bit_lshift(bit_lshift(1ULL, 31 - start_bit) - 1, start_bit))
                vmask = bit_lshift(1ULL, 32 - start_bit) - 1
                masked_v = bit_band(v + 0ULL, vmask)
                u32 = bit_bor(bit_band(u32, mask), bit_lshift(masked_v, start_bit))
            end
        elseif i == end_beat_id then
            -- mask = ~((1ULL << (end_bit + 1)) - 1)
            -- vmask = (1ULL << (end_bit + 1)) - 1
            -- masked_v = ((v + 0ULL) >> ((i - 1) * 32 - s)) & vmask
            -- u32 = (u32 & mask) | masked_v

            mask = bit_bnot(bit_lshift(1ULL, end_bit + 1) - 1)
            vmask = bit_lshift(1ULL, end_bit + 1) - 1
            masked_v = bit_band(bit_rshift(v + 0ULL, (i - 1) * 32 - s), vmask)
            u32 = bit_bor(bit_band(u32, mask), masked_v)
        else
            -- masked_v = ((v + 0ULL) >> (32 - start_bit)) & 0xFFFFFFFFULL
            -- u32 = (u32 & 0ULL) | masked_v

            masked_v = bit_band(bit_rshift(v + 0ULL, 32 - start_bit), 0xFFFFFFFFULL)
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

function BitVec:dump_str()
    return to_hex_str(self.u32_vec)
end

function BitVec:dump()
    print(self:dump_str())
end

function BitVec:__tostring()
    local result = ""
    for i = 1, #self.u32_vec do
        result = bit_tohex(self.u32_vec[i]) .. result
    end
    return result
end

function BitVec:to_hex_str()
    local result = ""
    for i = 1, #self.u32_vec do
        result = bit_tohex(self.u32_vec[i]) .. result
    end
    return result
end

function BitVec:__concat(other)
    assert(false, "TODO:")
end

function BitVec:__eq(other)
    local self_len = #self.u32_vec
    local other_len = #other.u32_vec
    local result = true

    if self_len == other_len then
        for i = 1, self_len do
            if self.u32_vec[i] ~= other.u32_vec[i] then
                result = false
                break
            end
        end
    elseif self_len > other_len then
        for i = 1, other_len do
            if self.u32_vec[i] ~= other.u32_vec[i] then
                result = false
                break
            end
        end
        for i = other_len + 1, self_len do
            if self.u32_vec[i] ~= 0 then
                result = false
                break
            end
        end
    elseif self_len < other_len then
        for i = 1, self_len do
            if self.u32_vec[i] ~= other.u32_vec[i] then
                result = false
                break
            end
        end
        for i = self_len + 1, other_len do
            if other.u32_vec[i] ~= 0 then
                result = false
                break
            end
        end
    end

    return result
end

function BitVec:__len()
    return self.bit_width
end

local subbitvec_shared_mt = {
    __newindex = function (t, k, v)
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

    __tostring = function (t)
        return t:dump_str()
    end,

    __eq = function (t, other)
        return t:dump_str() == other:dump_str()
    end,

    __len = function (t)
        return t._e - t._s + 1
    end,

    -- TODO: concat
}

function BitVec:__call(s, e)
    ---@type string
    local key = s .. "_" .. e

    if not self._call_cache[key] then
        ---@type SubBitVec
        local sub_bit_vec = setmetatable({
            __type = "SubBitVec",
            _s = s,
            _e = e,

            set = function (t, v)
                self:set_bitfield(t._s, t._e, v)
            end,

            set_hex_str = function (t, hex_str)
                self:set_bitfield_hex_str(t._s, t._e, hex_str)
            end,

            set_vec = function (t, u32_vec)
                self:set_bitfield_vec(t._s, t._e, u32_vec)
            end,

            get = function (t)
                return self:get_bitfield(t._s, t._e)
            end,

            get_hex_str = function (t)
                return self:get_bitfield_hex_str(t._s, t._e)
            end,

            get_vec = function (t)
                return self:get_bitfield_vec(t._s, t._e)
            end,

            dump_str = function (t)
                return self:get_bitfield_hex_str(t._s, t._e)
            end,

            dump = function (t)
                print(self:dump_str())
            end
        }, subbitvec_shared_mt)

        self._call_cache[key] = sub_bit_vec
    end
    return self._call_cache[key]
end

return BitVec
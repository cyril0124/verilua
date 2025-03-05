local ffi = require "ffi"
local BitVec = require "BitVec"
local table_new = require "table.new"

local C = ffi.C
local type = type
local assert = assert
local f = string.format
local ffi_new = ffi.new
local ffi_string = ffi.string

ffi.cdef[[
    void vpiml_get_value_multi(long long handle, uint32_t *ret, int n);
    uint64_t vpiml_get_value64(long long handle);

    void vpiml_set_value64(long long handle, uint64_t value);
    void vpiml_set_value64_force_single(long long handle, uint64_t value, uint32_t size);

    void vpiml_set_value_multi(long long handle, uint32_t *values, int length);
    void vpiml_set_value_multi_beat_2(long long handle, uint32_t v0, uint32_t v1); 
    void vpiml_set_value_multi_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2); 
    void vpiml_set_value_multi_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
    void vpiml_set_value_multi_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
    void vpiml_set_value_multi_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
    void vpiml_set_value_multi_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
    void vpiml_set_value_multi_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);  
]]

local chdl = {
    get = function (this) assert(false, "<chdl>:get() is not implemented!") end,
    get64 = function (this) assert(false, "<chdl>:get64() is not implemented!") end,
    get_bitvec = function (this) assert(false, "<chdl>:get_bitvec() is not implemented!") end,
    set = function (this, value, force_single_beat) assert(false, "<chdl>:set() is not implemented!") end,
    set_unsafe = function (this, value, force_single_beat) assert(false, "<chdl>:set_unsafe() is not implemented!") end,
    set_cached = function (this, value, force_single_beat) assert(false, f("<chdl>:set_cached() is not implemented!, fullpath => %s, bitwidth => %d", this.fullpath, this.width)) end,
    set_bitfield = function (this, s, e, v) assert(false, "<chdl>:set_bitfield() is not implemented!") end,
    set_bitfield_hex_str = function (this, s, e, hex_str) assert(false, "<chdl>:set_bitfield_hex_str() is not implemented!") end,
}

local chdl_array = {
    at = function (this, idx) assert(false, f("[%s] Normal handle does not support <chdl>:at()", this.fullpath)) end,
    get_index = function (this, index) assert(false, f("[%s] Normal handle does not support <chdl>:get_index()", this.fullpath)) end,
    get_index_bitvec = function (this, index) assert(false, f("[%s] Normal handle does not support <chdl>:get_index_bitvec()", this.fullpath)) end,
    set_index = function (this, index, value, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index()", this.fullpath)) end,
    set_index_unsafe = function (this, index, value, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_unsafe()", this.fullpath)) end,
    get_index_all = function (this) assert(false, f("[%s] Normal handle does not support <chdl>:get_index_all()", this.fullpath)) end,
    set_index_bitfield = function (this, index, s, e, v) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_bitfield()", this.fullpath)) end,
    set_index_bitfield_hex_str = function (this, index, s, e, hex_str) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_bitfield_hex_str()", this.fullpath)) end,
    set_index_all = function (this, values, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_all()", this.fullpath)) end,
    set_index_unsafe_all = function (this, values, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_unsafe_all()", this.fullpath)) end,
}

local function chdl_init()
    chdl.get = function (this)
        C.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)
        return this.c_results
    end

    chdl.get64 = function (this)
        return C.vpiml_get_value64(this.hdl)
    end

    chdl.get_bitvec = function (this)
        C.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)

        if this.bitvec then
            this.bitvec:_update_u32_vec(this.c_results)
            return this.bitvec
        else
            this.bitvec = BitVec(this.c_results, this.width)
            return this.bitvec
        end
    end

    chdl.set = function (this, value, force_single_beat)
        if force_single_beat then
            if type(value) == "table" then
                assert(false)
            end
            C.vpiml_set_value64_force_single(this.hdl, value, this.beat_num)
        else
            -- value is a table where <lsb ... msb>
            if type(value) ~= "table" then
                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
            end
            
            local beat_num = this.beat_num
            if #value ~= beat_num then
                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
            end

            -- TODO: Check performance
            if beat_num == 3 then
                C.vpiml_set_value_multi_beat_3(this.hdl, value[1], value[2], value[3]);
            elseif beat_num == 4 then
                C.vpiml_set_value_multi_beat_4(this.hdl, value[1], value[2], value[3], value[4])
            elseif beat_num == 5 then
                C.vpiml_set_value_multi_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
            elseif beat_num == 6 then
                C.vpiml_set_value_multi_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
            elseif beat_num == 7 then
                C.vpiml_set_value_multi_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
            elseif beat_num == 8 then
                C.vpiml_set_value_multi_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
            else
                for i = 1, this.beat_num do
                    this.c_results[i - 1] = value[i]
                end
                C.vpiml_set_value_multi(this.hdl, this.c_results, this.beat_num)
            end
        end
    end

    -- 
    -- Unsafe usage of CallableHDL:set()
    -- Do not check value type and lenght of value table. 
    -- Usually has higher performance than CallableHDL:set()
    -- 
    chdl.set_unsafe = function (this, value, force_single_beat)
        if force_single_beat then
            C.vpiml_set_value64_force_single(this.hdl, value, this.beat_num)
        else
            -- value is a table where <lsb ... msb>
            local beat_num = this.beat_num

            if beat_num == 3 then
                C.vpiml_set_value_multi_beat_3(this.hdl, value[1], value[2], value[3]);
            elseif beat_num == 4 then
                C.vpiml_set_value_multi_beat_4(this.hdl, value[1], value[2], value[3], value[4])
            elseif beat_num == 5 then
                C.vpiml_set_value_multi_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
            elseif beat_num == 6 then
                C.vpiml_set_value_multi_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
            elseif beat_num == 7 then
                C.vpiml_set_value_multi_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
            elseif beat_num == 8 then
                C.vpiml_set_value_multi_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
            else
                for i = 1, this.beat_num do
                    this.c_results[i - 1] = value[i]
                end
                C.vpiml_set_value_multi(this.hdl, this.c_results, this.beat_num)
            end
        end
    end

    chdl.set_cached = function (this, value, force_single_beat)
        if force_single_beat then
            if this.cached_value == value then
                return
            end

            this.cached_value = value
            C.vpiml_set_value64_force_single(this.hdl, value, this.beat_num)
        else
            assert(false, f("<chdl>:set_cached() is only supported for single beat value, fullpath => %s, bitwidth => %d", this.fullpath, this.width))
        end
    end

    chdl.set_bitfield = function (this, s, e, v)
        local bv = this:get_bitvec():_set_bitfield(s, e, v)
        this:set_unsafe(bv.u32_vec)
    end

    chdl.set_bitfield_hex_str = function (this, s, e, hex_str)
        local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
        this:set_unsafe(bv.u32_vec)
    end
end

local function chdl_array_init()
    chdl_array.at = function (this, idx)
        this.hdl = this.array_hdls[idx + 1] -- index is zero-based
        return this
    end

    chdl_array.get_index = function (this, index)
        local chosen_hdl = this.array_hdls[index + 1]
        C.vpiml_get_value_multi(chosen_hdl, this.c_results, this.beat_num)
        return this.c_results
    end

    chdl_array.get_index_bitvec = function (this, index)
        local chosen_hdl = this.array_hdls[index + 1]
        C.vpiml_get_value_multi(chosen_hdl, this.c_results, this.beat_num)

        if this.array_bitvecs[index + 1] then
            this.array_bitvecs[index + 1]:_update_u32_vec(this.c_results)
            return this.array_bitvecs[index + 1]
        else
            this.array_bitvecs[index + 1] = BitVec(this.c_results, this.width)
            return this.array_bitvecs[index + 1]
        end
    end

    chdl_array.set_index = function(this, index, value, force_single_beat)
        local chosen_hdl = this.array_hdls[index + 1]
        if force_single_beat then
            if type(value) == "table" then
                assert(false)
            end
            C.vpiml_set_value64(chosen_hdl, value)
        else
            -- value is a table where <lsb ... msb>
            if type(value) ~= "table" then
                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
            end
            
            local beat_num = this.beat_num
            if #value ~= beat_num then
                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
            end

            if beat_num == 3 then     -- 32 * 3 = 96 bits
                C.vpiml_set_value_multi_beat_3(chosen_hdl, value[1], value[2], value[3])
            elseif beat_num == 4 then -- 32 * 4 = 128 bits
                C.vpiml_set_value_multi_beat_4(chosen_hdl, value[1], value[2], value[3], value[4])
            elseif beat_num == 5 then -- 32 * 5 = 160 bits
                C.vpiml_set_value_multi_beat_5(chosen_hdl, value[1], value[2], value[3], value[4], value[5])
            elseif beat_num == 6 then -- 32 * 6 = 192 bits
                C.vpiml_set_value_multi_beat_6(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6])
            elseif beat_num == 7 then -- 32 * 7 = 224 bits
                C.vpiml_set_value_multi_beat_7(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
            elseif beat_num == 8 then -- 32 * 8 = 256 bits
                C.vpiml_set_value_multi_beat_8(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
            else
                for i = 1, this.beat_num do
                    this.c_results[i - 1] = value[i]
                end
                C.vpiml_set_value_multi(chosen_hdl, this.c_results, this.beat_num)
            end
        end
    end

    chdl_array.set_index_unsafe = function(this, index, value, force_single_beat)
        local chosen_hdl = this.array_hdls[index + 1]
        if force_single_beat then
            C.vpiml_set_value64(chosen_hdl, value)
        else
            -- value is a table where <lsb ... msb>
            local beat_num = this.beat_num

            if beat_num == 3 then     -- 32 * 3 = 96 bits
                C.vpiml_set_value_multi_beat_3(chosen_hdl, value[1], value[2], value[3])
            elseif beat_num == 4 then -- 32 * 4 = 128 bits
                C.vpiml_set_value_multi_beat_4(chosen_hdl, value[1], value[2], value[3], value[4])
            elseif beat_num == 5 then -- 32 * 5 = 160 bits
                C.vpiml_set_value_multi_beat_5(chosen_hdl, value[1], value[2], value[3], value[4], value[5])
            elseif beat_num == 6 then -- 32 * 6 = 192 bits
                C.vpiml_set_value_multi_beat_6(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6])
            elseif beat_num == 7 then -- 32 * 7 = 224 bits
                C.vpiml_set_value_multi_beat_7(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
            elseif beat_num == 8 then -- 32 * 8 = 256 bits
                C.vpiml_set_value_multi_beat_8(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
            else
                for i = 1, this.beat_num do
                    this.c_results[i - 1] = value[i]
                end
                C.vpiml_set_value_multi(chosen_hdl, this.c_results, this.beat_num)
            end
        end
    end

    chdl_array.get_index_all = function (this)
        local ret = table_new(this.array_size, 0)
        for index = 0, this.array_size - 1 do
            this.get_index(this, index)

            -- Transform cdata to table
            local tmp = table_new(this.beat_num, 0)
            for i = 1, this.beat_num do
                tmp[i] = this.c_results[i]
            end

            ret[index + 1] = tmp
        end
        return ret
    end

    chdl_array.set_index_bitfield = function (this, index, s, e, v)
        local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
        this:set_index_unsafe(index, bv.u32_vec)
    end

    chdl_array.set_index_bitfield_hex_str = function (this, index, s, e, hex_str)
        local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
        this:set_index_unsafe(index, bv.u32_vec)
    end

    chdl_array.set_index_all = function (this, values, force_single_beat)
        force_single_beat = force_single_beat or false
        for index = 0, this.array_size - 1 do
            this.set_index(this, index, values[index + 1], force_single_beat)
        end
    end

    chdl_array.set_index_unsafe_all = function (this, values, force_single_beat)
        force_single_beat = force_single_beat or false
        for index = 0, this.array_size - 1 do
            this.set_index_unsafe(this, index, values[index + 1], force_single_beat)
        end
    end
end

return function (is_array)
    chdl_init(chdl)

    if is_array then
        chdl_array_init(chdl_array)
        for k, func in pairs(chdl_array) do
            chdl[k] = func
        end
    end

    return chdl
end

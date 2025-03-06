local ffi = require "ffi"
local BitVec = require "BitVec"
local table_new = require "table.new"

local C = ffi.C
local assert = assert
local f = string.format
local ffi_new = ffi.new
local ffi_string = ffi.string

ffi.cdef[[
    void vpiml_set_value(long long handle, uint32_t value);
    uint32_t vpiml_get_value(long long handle);

    void vpiml_force_value(long long handle, uint32_t value);
    void vpiml_release_value(long long handle);
]]

local chdl = {
    get = function (this) assert(false, "<chdl>:get() is not implemented!") end,
    get64 = function (this) assert(false, "<chdl>:get64() is not implemented!") end,
    get_bitvec = function (this) assert(false, "<chdl>:get_bitvec() is not implemented!") end,
    set = function (this, value) assert(false, "<chdl>:set() is not implemented!") end,
    set_unsafe = function (this, value) assert(false, "<chdl>:set_unsafe() is not implemented!") end,
    set_cached = function (this, value, force_single_beat) assert(false, f("<chdl>:set_cached() is not implemented!, fullpath => %s, bitwidth => %d", this.fullpath, this.width)) end,
    set_bitfield = function (this, s, e, v) assert(false, "<chdl>:set_bitfield() is not implemented!") end,
    set_bitfield_hex_str = function (this, s, e, hex_str) assert(false, "<chdl>:set_bitfield_hex_str() is not implemented!") end,
    set_force = function (this, value) assert(false, "<chdl>:set_force() is not implemented!") end,
    set_release = function (this) assert(false, "<chdl>:set_release() is not implemented!") end,
}

local chdl_array = {
    at = function (this, idx) assert(false, f("[%s] Normal handle does not support <chdl>:at()", this.fullpath)) end,
    get_index = function (this, index) assert(false, f("[%s] Normal handle does not support <chdl>:get_index()", this.fullpath)) end,
    set_index = function (this, index, value) assert(false, f("[%s] Normal handle does not support <chdl>:set_index()", this.fullpath)) end,
    set_index_unsafe = function (this, index, value) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_unsafe()", this.fullpath)) end,
    get_index_all = function (this, force_multi_beat) assert(false, f("[%s] Normal handle does not support <chdl>:get_index_all()", this.fullpath)) end,
    get_index_bitvec = function (this, index) assert(false, f("[%s] Normal handle does not support <chdl>:get_index_bitvec()", this.fullpath)) end,
    set_index_bitfield = function (this, index, s, e, v) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_bitfield()", this.fullpath)) end,
    set_index_bitfield_hex_str = function (this, index, s, e, hex_str) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_bitfield_hex_str()", this.fullpath)) end,
    set_index_all = function (this, values, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_all()", this.fullpath)) end,
    set_index_unsafe_all = function (this, values, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_unsafe_all()", this.fullpath)) end, 
}

local function chdl_init(this)
    chdl.get = function (this)
        return C.vpiml_get_value(this.hdl)
    end

    chdl.get64 = chdl.get

    chdl.get_bitvec = function (this)
        if this.bitvec then
            this.bitvec:_update_u32_vec(C.vpiml_get_value(this.hdl))
            return this.bitvec
        else
            this.bitvec = BitVec(C.vpiml_get_value(this.hdl), this.width)
            return this.bitvec
        end
    end

    chdl.set = function (this, value)
        C.vpiml_set_value(this.hdl, value)
    end

    chdl.set_unsafe = chdl.set

    chdl.set_cached = function (this, value)
        if this.cached_value == value then
            return
        end

        this.cached_value = value
        C.vpiml_set_value(this.hdl, value)
    end

    chdl.set_bitfield = function (this, s, e, v)
        C.vpiml_set_value(this.hdl, this:get_bitvec():_set_bitfield(s, e, v).u32_vec[1])
    end

    chdl.set_bitfield_hex_str = function (this, s, e, hex_str)
        C.vpiml_set_value(this.hdl, this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
    end

    chdl.set_force = function (this, value)
        C.vpiml_force_value(this.hdl, value)
    end

    chdl.set_release = function (this)
        C.vpiml_release_value(this.hdl)
    end
end

local function chdl_array_init()
    chdl_array.at = function (this, idx)
        this.hdl = this.array_hdls[idx + 1] -- index is zero-based
        return this
    end

    -- 
    -- get array value by index, the index value is start with 0
    -- 
    chdl_array.get_index = function (this, index)
        local chosen_hdl = this.array_hdls[index + 1]
        return C.vpiml_get_value(chosen_hdl)
    end

    chdl_array.set_index = function(this, index, value)
        local chosen_hdl = this.array_hdls[index + 1]
        C.vpiml_set_value(chosen_hdl, value)
    end

    chdl_array.set_index_unsafe = chdl_array.set_index

    chdl_array.get_index_all = function (this, force_multi_beat)
        local ret = table_new(this.array_size, 0)
        for index = 0, this.array_size - 1 do
            ret[index + 1] = this.get_index(this, index, force_multi_beat)
        end
        return ret
    end

    chdl_array.get_index_bitvec = function (this, index)
        local chosen_hdl = this.array_hdls[index + 1]
        if this.array_bitvecs[index + 1] then
            this.array_bitvecs[index + 1]:_update_u32_vec(C.vpiml_get_value(chosen_hdl))
            return this.array_bitvecs[index + 1]
        else
            this.array_bitvecs[index + 1] = BitVec(C.vpiml_get_value(chosen_hdl), this.width)
            return this.array_bitvecs[index + 1]
        end
    end

    chdl_array.set_index_bitfield = function (this, index, s, e, v)
        local chosen_hdl = this.array_hdls[index + 1]
        C.vpiml_set_value(chosen_hdl, this:get_index_bitvec(index):_set_bitfield(s, e, v).u32_vec[1])
    end

    chdl_array.set_index_bitfield_hex_str = function (this, index, s, e, hex_str)
        local chosen_hdl = this.array_hdls[index + 1]
        C.vpiml_set_value(chosen_hdl, this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
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
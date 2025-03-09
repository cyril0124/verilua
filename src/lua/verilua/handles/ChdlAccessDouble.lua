local vpiml = require "vpiml"
local BitVec = require "BitVec"
local table_new = require "table.new"

local type = type
local assert = assert
local f = string.format

local chdl = {
    get = function (this, force_multi_beat) assert(false, "<chdl>:get() is not implemented!") end,
    get64 = function (this) assert(false, "<chdl>:get64() is not implemented!") end,
    get_bitvec = function (this) assert(false, "<chdl>:get_bitvec() is not implemented!") end,
    set = function (this, value, force_single_beat) assert(false, "<chdl>:set() is not implemented!") end,
    set_unsafe = function (this, value, force_single_beat) assert(false, "<chdl>:set_unsafe() is not implemented!") end,
    set_cached = function (this, value, force_single_beat) assert(false, f("<chdl>:set_cached() is not implemented!, fullpath => %s, bitwidth => %d", this.fullpath, this.width)) end,
    set_bitfield = function (this, s, e, v) assert(false, "<chdl>:set_bitfield() is not implemented!") end,
    set_bitfield_hex_str = function (this, s, e, hex_str) assert(false, "<chdl>:set_bitfield_hex_str() is not implemented!") end,
    set_force = function (this, value, force_single_beat) assert(false, "<chdl>:set_force() is not implemented!") end,
    set_release = function (this) assert(false, "<chdl>:set_release() is not implemented!") end,
}

local chdl_array = {
    at = function (this, idx) assert(false, f("[%s] Normal handle does not support <chdl>:at()", this.fullpath)) end,
    get_index = function (this, index, force_multi_beat) assert(false, f("[%s] Normal handle does not support <chdl>:get_index()", this.fullpath)) end,
    set_index = function (this, index, value, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index()", this.fullpath)) end,
    set_index_unsafe = function (this, index, value, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_unsafe()", this.fullpath)) end,
    get_index_all = function (this, force_multi_beat) assert(false, f("[%s] Normal handle does not support <chdl>:get_index_all()", this.fullpath)) end,
    get_index_bitvec = function (this, index) assert(false, f("[%s] Normal handle does not support <chdl>:get_index_bitvec()", this.fullpath)) end,
    set_index_bitfield = function (this, index, s, e, v) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_bitfield()", this.fullpath)) end,
    set_index_bitfield_hex_str = function (this, index, s, e, hex_str) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_bitfield_hex_str()", this.fullpath)) end,
    set_index_all = function (this, values, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_all()", this.fullpath)) end,
    set_index_unsafe_all = function (this, values, force_single_beat) assert(false, f("[%s] Normal handle does not support <chdl>:set_index_unsafe_all()", this.fullpath)) end,
}

local function chdl_init()
    chdl.get = function (this, force_multi_beat)
        if force_multi_beat then
            vpiml.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)
            return this.c_results
        else
            return vpiml.vpiml_get_value64(this.hdl)
        end
    end

    chdl.get64 = function (this)
        return vpiml.vpiml_get_value64(this.hdl)
    end

    chdl.get_bitvec = function (this)
        vpiml.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)

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
            vpiml.vpiml_set_value64(this.hdl, value)
        else
            if type(value) ~= "table" then
                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
            end

            if #value ~= 2 then
                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
            end

            vpiml.vpiml_set_value_multi_beat_2(this.hdl, value[1], value[2])
        end
    end

    -- 
    -- Unsafe usage of CallableHDL:set()
    -- Do not check value type and lenght of value table. 
    -- Usually has higher performance than CallableHDL:set()
    -- 
    chdl.set_unsafe = function (this, value, force_single_beat)
        if force_single_beat then
            vpiml.vpiml_set_value64(this.hdl, value)
        else
            -- value is a table where <lsb ... msb>
            vpiml.vpiml_set_value_multi_beat_2(this.hdl, value[1], value[2]);
        end
    end

    chdl.set_bitfield = function (this, s, e, v)
        local bv = this:get_bitvec():_set_bitfield(s, e, v)
        vpiml.vpiml_set_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
    end

    chdl.set_bitfield_hex_str = function (this, s, e, hex_str)
        local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
        vpiml.vpiml_set_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
    end

    chdl.set_force = function (this, value, force_single_beat)
        if force_single_beat then
            vpiml.vpiml_force_value64(this.hdl, value)
        else
            if type(value) ~= "table" then
                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set_force(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
            end

            if #value ~= 2 then
                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
            end

            vpiml.vpiml_force_value_multi_beat_2(this.hdl, value[1], value[2])
        end
    end

    chdl.set_release = function (this)
        vpiml.vpiml_release_value(this.hdl)
    end
end

local function chdl_array_init()
    chdl_array.at = function (this, idx)
        this.hdl = this.array_hdls[idx + 1] -- index is zero-based
        return this
    end
    
    chdl_array.get_index = function (this, index, force_multi_beat)
        local chosen_hdl = this.array_hdls[index + 1]
        if force_multi_beat then
            vpiml.vpiml_get_value_multi(chosen_hdl, this.c_results, this.beat_num)
            return this.c_results
        else
            return vpiml.vpiml_get_value64(chosen_hdl)
        end
    end

    chdl_array.set_index = function(this, index, value, force_single_beat)
        local chosen_hdl = this.array_hdls[index + 1]
        if force_single_beat then
            if type(value) == "table" then
                assert(false)
            end
            vpiml.vpiml_set_value64(chosen_hdl, value)
        else
            -- value is a table where <lsb ... msb>
            if type(value) ~= "table" then
                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
            end
            
            if #value ~= 2 then
                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
            end

            vpiml.vpiml_set_value_multi_beat_2(chosen_hdl, value[1], value[2])
        end
    end

    chdl_array.set_index_unsafe = function(this, index, value, force_single_beat)
        local chosen_hdl = this.array_hdls[index + 1]
        if force_single_beat then
            vpiml.vpiml_set_value64(chosen_hdl, value)
        else
            -- value is a table where <lsb ... msb>
            vpiml.vpiml_set_value_multi_beat_2(chosen_hdl, value[1], value[2])
        end
    end

    chdl_array.get_index_all = function (this, force_multi_beat)
        local force_multi_beat = force_multi_beat or false
        local ret = table_new(this.array_size, 0)
        if force_multi_beat then
            for index = 0, this.array_size - 1 do
                this.get_index(this, index, true)

                -- Transform cdata to table
                local tmp = table_new(this.beat_num, 0)
                for i = 1, this.beat_num do
                    tmp[i] = this.c_results[i]
                end

                ret[index + 1] = tmp
            end
        else
            for index = 0, this.array_size - 1 do
                ret[index + 1] = this.get_index(this, index, false)
            end
        end
        return ret
    end

    chdl_array.get_index_bitvec = function (this, index)
        local chosen_hdl = this.array_hdls[index + 1]
        vpiml.vpiml_get_value_multi(chosen_hdl, this.c_results, this.beat_num)

        if this.array_bitvecs[index + 1] then
            this.array_bitvecs[index + 1]:_update_u32_vec(this.c_results)
            return this.array_bitvecs[index + 1]
        else
            this.array_bitvecs[index + 1] = BitVec(this.c_results, this.width)
            return this.array_bitvecs[index + 1]
        end
    end

    chdl_array.set_index_bitfield = function (this, index, s, e, v)
        local chosen_hdl = this.array_hdls[index + 1]
        local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
        vpiml.vpiml_set_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
    end

    chdl_array.set_index_bitfield_hex_str = function (this, index, s, e, hex_str)
        local chosen_hdl = this.array_hdls[index + 1]
        local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
        vpiml.vpiml_set_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
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

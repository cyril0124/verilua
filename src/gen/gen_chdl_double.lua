-- gen_v2_double.lua
-- Generates the body for ChdlAccessDouble.lua (beat_num == 2)

return function()
    return [[
-- Singleton methods: created once at require() time
chdl.get = function(this, force_multi_beat)
    if force_multi_beat then
        vpiml.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)
        return this.c_results
    else
        return vpiml.vpiml_get_value64(this.hdl)
    end
end

chdl.get64 = function(this)
    return vpiml.vpiml_get_value64(this.hdl)
end

chdl.get_bitvec = function(this)
    vpiml.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)
    if this.bitvec then
        this.bitvec:_update_u32_vec(this.c_results)
        return this.bitvec
    else
        this.bitvec = BitVec(this.c_results, this.width)
        return this.bitvec
    end
end

chdl.set = function(this, value, force_single_beat)
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

chdl.set_unsafe = function(this, value, force_single_beat)
    if force_single_beat then
        vpiml.vpiml_set_value64(this.hdl, value)
    else
        vpiml.vpiml_set_value_multi_beat_2(this.hdl, value[1], value[2])
    end
end

chdl.set_cached = function(this, value)
    if this.cached_value == value then return end
    this.cached_value = value
    vpiml.vpiml_set_value64(this.hdl, value)
end

chdl.set_bitfield = function(this, s, e, v)
    local bv = this:get_bitvec():_set_bitfield(s, e, v)
    vpiml.vpiml_set_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
end

chdl.set_bitfield_hex_str = function(this, s, e, hex_str)
    local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
    vpiml.vpiml_set_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
end

chdl.set_force = function(this, value, force_single_beat)
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

chdl.set_release = function(this)
    vpiml.vpiml_release_value(this.hdl)
end

chdl.set_imm = function(this, value, force_single_beat)
    if force_single_beat then
        vpiml.vpiml_set_imm_value64(this.hdl, value)
    else
        if type(value) ~= "table" then
            assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
        end
        if #value ~= 2 then
            assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
        end
        vpiml.vpiml_set_imm_value_multi_beat_2(this.hdl, value[1], value[2])
    end
end

chdl.set_imm_unsafe = function(this, value, force_single_beat)
    if force_single_beat then
        vpiml.vpiml_set_imm_value64(this.hdl, value)
    else
        vpiml.vpiml_set_imm_value_multi_beat_2(this.hdl, value[1], value[2])
    end
end

chdl.set_imm_cached = function(this, value)
    if this.cached_value == value then return end
    this.cached_value = value
    vpiml.vpiml_set_imm_value64(this.hdl, value)
end

chdl.set_imm_bitfield = function(this, s, e, v)
    local bv = this:get_bitvec():_set_bitfield(s, e, v)
    vpiml.vpiml_set_imm_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
end

chdl.set_imm_bitfield_hex_str = function(this, s, e, hex_str)
    local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
    vpiml.vpiml_set_imm_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
end

chdl.set_imm_force = function(this, value, force_single_beat)
    if force_single_beat then
        vpiml.vpiml_force_imm_value64(this.hdl, value)
    else
        if type(value) ~= "table" then
            assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set_force(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
        end
        if #value ~= 2 then
            assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
        end
        vpiml.vpiml_force_imm_value_multi_beat_2(this.hdl, value[1], value[2])
    end
end

chdl.set_imm_release = function(this)
    vpiml.vpiml_release_imm_value(this.hdl)
end

-- Array methods (also singleton)
chdl_array.at = function(this, idx)
    this.hdl = this.array_hdls[idx + 1]
    return this
end

chdl_array.get_index = function(this, index, force_multi_beat)
    local chosen_hdl = this.array_hdls[index + 1]
    if force_multi_beat then
        vpiml.vpiml_get_value_multi(chosen_hdl, this.c_results, this.beat_num)
        return this.c_results
    else
        return vpiml.vpiml_get_value64(chosen_hdl)
    end
end

chdl_array.get_index_all = function(this, force_multi_beat)
    local ret = table_new(this.array_size, 0)
    if force_multi_beat then
        for index = 0, this.array_size - 1 do
            vpiml.vpiml_get_value_multi(this.array_hdls[index + 1], this.c_results, this.beat_num)
            local tmp = table_new(this.beat_num, 0)
            for i = 1, this.beat_num do
                tmp[i] = this.c_results[i]
            end
            ret[index + 1] = tmp
        end
    else
        for index = 0, this.array_size - 1 do
            ret[index + 1] = vpiml.vpiml_get_value64(this.array_hdls[index + 1])
        end
    end
    return ret
end

chdl_array.get_index_bitvec = function(this, index)
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

chdl_array.set_index = function(this, index, value, force_single_beat)
    local chosen_hdl = this.array_hdls[index + 1]
    if force_single_beat then
        vpiml.vpiml_set_value64(chosen_hdl, value)
    else
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
        vpiml.vpiml_set_value_multi_beat_2(chosen_hdl, value[1], value[2])
    end
end

chdl_array.set_index_bitfield = function(this, index, s, e, v)
    local chosen_hdl = this.array_hdls[index + 1]
    local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
    vpiml.vpiml_set_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
end

chdl_array.set_index_bitfield_hex_str = function(this, index, s, e, hex_str)
    local chosen_hdl = this.array_hdls[index + 1]
    local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
    vpiml.vpiml_set_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
end

chdl_array.set_index_all = function(this, values, force_single_beat)
    force_single_beat = force_single_beat or false
    for index = 0, this.array_size - 1 do
        this:set_index(index, values[index + 1], force_single_beat)
    end
end

chdl_array.set_index_unsafe_all = function(this, values, force_single_beat)
    force_single_beat = force_single_beat or false
    for index = 0, this.array_size - 1 do
        this:set_index_unsafe(index, values[index + 1], force_single_beat)
    end
end

chdl_array.set_imm_index = function(this, index, value, force_single_beat)
    local chosen_hdl = this.array_hdls[index + 1]
    if force_single_beat then
        vpiml.vpiml_set_imm_value64(chosen_hdl, value)
    else
        if type(value) ~= "table" then
            assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
        end
        if #value ~= 2 then
            assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
        end
        vpiml.vpiml_set_imm_value_multi_beat_2(chosen_hdl, value[1], value[2])
    end
end

chdl_array.set_imm_index_unsafe = function(this, index, value, force_single_beat)
    local chosen_hdl = this.array_hdls[index + 1]
    if force_single_beat then
        vpiml.vpiml_set_imm_value64(chosen_hdl, value)
    else
        vpiml.vpiml_set_imm_value_multi_beat_2(chosen_hdl, value[1], value[2])
    end
end

chdl_array.set_imm_index_bitfield = function(this, index, s, e, v)
    local chosen_hdl = this.array_hdls[index + 1]
    local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
    vpiml.vpiml_set_imm_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
end

chdl_array.set_imm_index_bitfield_hex_str = function(this, index, s, e, hex_str)
    local chosen_hdl = this.array_hdls[index + 1]
    local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
    vpiml.vpiml_set_imm_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
end

chdl_array.set_imm_index_all = function(this, values, force_single_beat)
    force_single_beat = force_single_beat or false
    for index = 0, this.array_size - 1 do
        this:set_imm_index(index, values[index + 1], force_single_beat)
    end
end

chdl_array.set_imm_index_unsafe_all = function(this, values, force_single_beat)
    force_single_beat = force_single_beat or false
    for index = 0, this.array_size - 1 do
        this:set_imm_index_unsafe(index, values[index + 1], force_single_beat)
    end
end
]]
end

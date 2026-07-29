-- gen_v2_single.lua
-- Generates the body for ChdlAccessSingle.lua (beat_num == 1)
-- All functions are defined at module level → singleton, shared across all instances

return function()
    return [[
-- Singleton methods: created once at require() time
chdl.get = function(this)
    return vpiml.vpiml_get_value(this.hdl)
end

chdl.get64 = chdl.get

chdl.get_bitvec = function(this)
    if this.bitvec then
        this.bitvec:_update_u32_vec(vpiml.vpiml_get_value(this.hdl))
        return this.bitvec
    else
        this.bitvec = BitVec(vpiml.vpiml_get_value(this.hdl), this.width)
        return this.bitvec
    end
end

chdl.set = function(this, value)
    vpiml.vpiml_set_value(this.hdl, value)
end

chdl.set_unsafe = chdl.set

chdl.set_cached = function(this, value)
    if this.cached_value == value then return end
    this.cached_value = value
    vpiml.vpiml_set_value(this.hdl, value)
end

chdl.set_bitfield = function(this, s, e, v)
    vpiml.vpiml_set_value(this.hdl, this:get_bitvec():_set_bitfield(s, e, v).u32_vec[1])
end

chdl.set_bitfield_hex_str = function(this, s, e, hex_str)
    vpiml.vpiml_set_value(this.hdl, this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
end

chdl.set_force = function(this, value)
    vpiml.vpiml_force_value(this.hdl, value)
end

chdl.set_release = function(this)
    vpiml.vpiml_release_value(this.hdl)
end

chdl.set_imm = function(this, value)
    vpiml.vpiml_set_imm_value(this.hdl, value)
end

chdl.set_imm_unsafe = chdl.set_imm

chdl.set_imm_cached = function(this, value)
    if this.cached_value == value then return end
    this.cached_value = value
    vpiml.vpiml_set_imm_value(this.hdl, value)
end

chdl.set_imm_bitfield = function(this, s, e, v)
    vpiml.vpiml_set_imm_value(this.hdl, this:get_bitvec():_set_bitfield(s, e, v).u32_vec[1])
end

chdl.set_imm_bitfield_hex_str = function(this, s, e, hex_str)
    vpiml.vpiml_set_imm_value(this.hdl, this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
end

chdl.set_imm_force = function(this, value)
    vpiml.vpiml_force_imm_value(this.hdl, value)
end

chdl.set_imm_release = function(this)
    vpiml.vpiml_release_imm_value(this.hdl)
end

-- Array methods (also singleton)
chdl_array.at = function(this, idx)
    this.hdl = this.array_hdls[idx + 1]
    return this
end

chdl_array.get_index = function(this, index)
    return vpiml.vpiml_get_value(this.array_hdls[index + 1])
end

chdl_array.get_index_all = function(this)
    local ret = table_new(this.array_size, 0)
    for index = 0, this.array_size - 1 do
        ret[index + 1] = vpiml.vpiml_get_value(this.array_hdls[index + 1])
    end
    return ret
end

chdl_array.get_index_bitvec = function(this, index)
    local chosen_hdl = this.array_hdls[index + 1]
    if this.array_bitvecs[index + 1] then
        this.array_bitvecs[index + 1]:_update_u32_vec(vpiml.vpiml_get_value(chosen_hdl))
        return this.array_bitvecs[index + 1]
    else
        this.array_bitvecs[index + 1] = BitVec(vpiml.vpiml_get_value(chosen_hdl), this.width)
        return this.array_bitvecs[index + 1]
    end
end

chdl_array.set_index = function(this, index, value)
    vpiml.vpiml_set_value(this.array_hdls[index + 1], value)
end

chdl_array.set_index_unsafe = chdl_array.set_index

chdl_array.set_index_bitfield = function(this, index, s, e, v)
    vpiml.vpiml_set_value(this.array_hdls[index + 1], this:get_index_bitvec(index):_set_bitfield(s, e, v).u32_vec[1])
end

chdl_array.set_index_bitfield_hex_str = function(this, index, s, e, hex_str)
    vpiml.vpiml_set_value(this.array_hdls[index + 1], this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
end

chdl_array.set_index_all = function(this, values)
    for index = 0, this.array_size - 1 do
        vpiml.vpiml_set_value(this.array_hdls[index + 1], values[index + 1])
    end
end

chdl_array.set_index_unsafe_all = chdl_array.set_index_all

chdl_array.set_imm_index = function(this, index, value)
    vpiml.vpiml_set_imm_value(this.array_hdls[index + 1], value)
end

chdl_array.set_imm_index_unsafe = chdl_array.set_imm_index

chdl_array.set_imm_index_bitfield = function(this, index, s, e, v)
    vpiml.vpiml_set_imm_value(this.array_hdls[index + 1], this:get_index_bitvec(index):_set_bitfield(s, e, v).u32_vec[1])
end

chdl_array.set_imm_index_bitfield_hex_str = function(this, index, s, e, hex_str)
    vpiml.vpiml_set_imm_value(this.array_hdls[index + 1], this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
end

chdl_array.set_imm_index_all = function(this, values)
    for index = 0, this.array_size - 1 do
        vpiml.vpiml_set_imm_value(this.array_hdls[index + 1], values[index + 1])
    end
end

chdl_array.set_imm_index_unsafe_all = chdl_array.set_imm_index_all
]]
end

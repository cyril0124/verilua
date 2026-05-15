-- gen_chdl_multi.lua
-- Generates the body for ChdlAccessMulti.lua (beat_num >= 3)

-- Helper to generate the beat_num dispatch chain for multi-beat set operations
local function gen_multi_set_dispatch(vpi_prefix, hdl_expr)
    hdl_expr = hdl_expr or "this.hdl"
    local lines = {}
    lines[#lines + 1] = "        assert(t == \"table\", \"set() expects number, uint64_t, or table; got \" .. t .. \", fullpath => \" .. this.fullpath)"
    lines[#lines + 1] = "        local beat_num = this.beat_num"
    lines[#lines + 1] = "        if #value ~= beat_num then"
    lines[#lines + 1] = '            assert(false, "len: " .. #value .. " =/= " .. this.beat_num)'
    lines[#lines + 1] = "        end"
    lines[#lines + 1] = ""
    for n = 3, 8 do
        local args = {}
        for i = 1, n do args[i] = "value[" .. i .. "]" end
        local kw = n == 3 and "if" or "elseif"
        lines[#lines + 1] = string.format("        %s beat_num == %d then", kw, n)
        lines[#lines + 1] = string.format("            vpiml.%s_multi_beat_%d(%s, %s)", vpi_prefix, n, hdl_expr, table.concat(args, ", "))
    end
    lines[#lines + 1] = "        else"
    lines[#lines + 1] = "            for i = 1, this.beat_num do"
    lines[#lines + 1] = "                this.c_results[i - 1] = value[i]"
    lines[#lines + 1] = "            end"
    lines[#lines + 1] = string.format("            vpiml.%s_multi(%s, this.c_results)", vpi_prefix, hdl_expr)
    lines[#lines + 1] = "        end"
    return table.concat(lines, "\n")
end

-- Helper for unsafe variant (no type/length checks)
local function gen_multi_set_unsafe_dispatch(vpi_prefix, hdl_expr)
    hdl_expr = hdl_expr or "this.hdl"
    local lines = {}
    lines[#lines + 1] = "        local beat_num = this.beat_num"
    for n = 3, 8 do
        local args = {}
        for i = 1, n do args[i] = "value[" .. i .. "]" end
        local kw = n == 3 and "if" or "elseif"
        lines[#lines + 1] = string.format("        %s beat_num == %d then", kw, n)
        lines[#lines + 1] = string.format("            vpiml.%s_multi_beat_%d(%s, %s)", vpi_prefix, n, hdl_expr, table.concat(args, ", "))
    end
    lines[#lines + 1] = "        else"
    lines[#lines + 1] = "            for i = 1, this.beat_num do"
    lines[#lines + 1] = "                this.c_results[i - 1] = value[i]"
    lines[#lines + 1] = "            end"
    lines[#lines + 1] = string.format("            vpiml.%s_multi(%s, this.c_results)", vpi_prefix, hdl_expr)
    lines[#lines + 1] = "        end"
    return table.concat(lines, "\n")
end

return function()
    local parts = {}
    local function emit(s) parts[#parts + 1] = s end

    emit([[
-- Singleton methods: created once at require() time
chdl.get = function(this)
    vpiml.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)
    return this.c_results
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
]])

    -- Generate set/set_imm/set_force/set_imm_force with type-based auto-dispatch
    local set_variants = {
        { name = "set",           vpi = "vpiml_set_value",       vpi64 = "vpiml_set_value64_force_single" },
        { name = "set_imm",      vpi = "vpiml_set_imm_value",   vpi64 = "vpiml_set_imm_value64_force_single" },
        { name = "set_force",    vpi = "vpiml_force_value",      vpi64 = "vpiml_force_value64_force_single" },
        { name = "set_imm_force", vpi = "vpiml_force_imm_value", vpi64 = "vpiml_force_imm_value64_force_single" },
    }

    for _, sv in ipairs(set_variants) do
        emit(string.format([[
chdl.%s = function(this, value)
    local t = type(value)
    if t == "number" or (t == "cdata" and ffi_istype("uint64_t", value)) then
        vpiml.%s(this.hdl, value)
    else
%s
    end
end
]], sv.name, sv.vpi64, gen_multi_set_dispatch(sv.vpi)))
    end

    -- Unsafe variants
    local unsafe_variants = {
        { name = "set_unsafe",     vpi = "vpiml_set_value",     vpi64 = "vpiml_set_value64_force_single" },
        { name = "set_imm_unsafe", vpi = "vpiml_set_imm_value", vpi64 = "vpiml_set_imm_value64_force_single" },
    }

    for _, sv in ipairs(unsafe_variants) do
        emit(string.format([[
chdl.%s = function(this, value)
    local t = type(value)
    if t == "number" or (t == "cdata" and ffi_istype("uint64_t", value)) then
        vpiml.%s(this.hdl, value)
    else
%s
    end
end
]], sv.name, sv.vpi64, gen_multi_set_unsafe_dispatch(sv.vpi)))
    end

    -- Bitfield, cached, release variants
    emit([[
chdl.set_bitfield = function(this, s, e, v)
    local bv = this:get_bitvec():_set_bitfield(s, e, v)
    this:set_unsafe(bv.u32_vec)
end

chdl.set_bitfield_hex_str = function(this, s, e, hex_str)
    local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
    this:set_unsafe(bv.u32_vec)
end

chdl.set_imm_bitfield = function(this, s, e, v)
    local bv = this:get_bitvec():_set_bitfield(s, e, v)
    this:set_imm_unsafe(bv.u32_vec)
end

chdl.set_imm_bitfield_hex_str = function(this, s, e, hex_str)
    local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
    this:set_imm_unsafe(bv.u32_vec)
end

chdl.set_cached = function(this, value)
    if this.cached_value == value then return end
    this.cached_value = value
    vpiml.vpiml_set_value64_force_single(this.hdl, value)
end

chdl.set_imm_cached = function(this, value)
    if this.cached_value == value then return end
    this.cached_value = value
    vpiml.vpiml_set_imm_value64_force_single(this.hdl, value)
end

chdl.set_release = function(this)
    vpiml.vpiml_release_value(this.hdl)
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
    local chosen_hdl = this.array_hdls[index + 1]
    vpiml.vpiml_get_value_multi(chosen_hdl, this.c_results, this.beat_num)
    return this.c_results
end

chdl_array.get_index_all = function(this)
    local ret = table_new(this.array_size, 0)
    for index = 0, this.array_size - 1 do
        vpiml.vpiml_get_value_multi(this.array_hdls[index + 1], this.c_results, this.beat_num)
        local tmp = table_new(this.beat_num, 0)
        for i = 1, this.beat_num do
            tmp[i] = this.c_results[i]
        end
        ret[index + 1] = tmp
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
]])

    -- Array set_index variants with type-based dispatch
    local array_set_variants = {
        { name = "set_index",     vpi = "vpiml_set_value",     vpi64 = "vpiml_set_value64_force_single" },
        { name = "set_imm_index", vpi = "vpiml_set_imm_value", vpi64 = "vpiml_set_imm_value64_force_single" },
    }

    for _, sv in ipairs(array_set_variants) do
        emit(string.format([[
chdl_array.%s = function(this, index, value)
    local chosen_hdl = this.array_hdls[index + 1]
    local t = type(value)
    if t == "number" or (t == "cdata" and ffi_istype("uint64_t", value)) then
        vpiml.%s(chosen_hdl, value)
    else
%s
    end
end
]], sv.name, sv.vpi64, gen_multi_set_dispatch(sv.vpi, "chosen_hdl")))
    end

    -- Array unsafe variants
    local array_unsafe_variants = {
        { name = "set_index_unsafe",     vpi = "vpiml_set_value",     vpi64 = "vpiml_set_value64_force_single" },
        { name = "set_imm_index_unsafe", vpi = "vpiml_set_imm_value", vpi64 = "vpiml_set_imm_value64_force_single" },
    }

    for _, sv in ipairs(array_unsafe_variants) do
        emit(string.format([[
chdl_array.%s = function(this, index, value)
    local chosen_hdl = this.array_hdls[index + 1]
    local t = type(value)
    if t == "number" or (t == "cdata" and ffi_istype("uint64_t", value)) then
        vpiml.%s(chosen_hdl, value)
    else
%s
    end
end
]], sv.name, sv.vpi64, gen_multi_set_unsafe_dispatch(sv.vpi, "chosen_hdl")))
    end

    -- Array bitfield and bulk variants
    emit([[
chdl_array.set_index_bitfield = function(this, index, s, e, v)
    local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
    this:set_index_unsafe(index, bv.u32_vec)
end

chdl_array.set_index_bitfield_hex_str = function(this, index, s, e, hex_str)
    local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
    this:set_index_unsafe(index, bv.u32_vec)
end

chdl_array.set_imm_index_bitfield = function(this, index, s, e, v)
    local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
    this:set_imm_index_unsafe(index, bv.u32_vec)
end

chdl_array.set_imm_index_bitfield_hex_str = function(this, index, s, e, hex_str)
    local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
    this:set_index_unsafe(index, bv.u32_vec)
end

chdl_array.set_index_all = function(this, values)
    for index = 0, this.array_size - 1 do
        this:set_index(index, values[index + 1])
    end
end

chdl_array.set_index_unsafe_all = function(this, values)
    for index = 0, this.array_size - 1 do
        this:set_index_unsafe(index, values[index + 1])
    end
end

chdl_array.set_imm_index_all = function(this, values)
    for index = 0, this.array_size - 1 do
        this:set_imm_index(index, values[index + 1])
    end
end

chdl_array.set_imm_index_unsafe_all = function(this, values)
    for index = 0, this.array_size - 1 do
        this:set_imm_index_unsafe(index, values[index + 1])
    end
end
]])

    return table.concat(parts, "\n")
end

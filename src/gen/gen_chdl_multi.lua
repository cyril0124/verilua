-- gen_v2_multi.lua
-- Generates the body for ChdlAccessMulti.lua (beat_num >= 3)

-- Helper to generate the beat_num dispatch chain for multi-beat set operations
local function gen_multi_set_dispatch(vpi_prefix)
    local lines = {}
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
        lines[#lines + 1] = string.format("            vpiml.%s_multi_beat_%d(this.hdl, %s)", vpi_prefix, n, table.concat(args, ", "))
    end
    lines[#lines + 1] = "        else"
    lines[#lines + 1] = "            for i = 1, this.beat_num do"
    lines[#lines + 1] = "                this.c_results[i - 1] = value[i]"
    lines[#lines + 1] = "            end"
    lines[#lines + 1] = string.format("            vpiml.%s_multi(this.hdl, this.c_results)", vpi_prefix)
    lines[#lines + 1] = "        end"
    return table.concat(lines, "\n")
end

-- Helper for unsafe variant (no type/length checks)
local function gen_multi_set_unsafe_dispatch(vpi_prefix)
    local lines = {}
    lines[#lines + 1] = "        local beat_num = this.beat_num"
    for n = 3, 8 do
        local args = {}
        for i = 1, n do args[i] = "value[" .. i .. "]" end
        local kw = n == 3 and "if" or "elseif"
        lines[#lines + 1] = string.format("        %s beat_num == %d then", kw, n)
        lines[#lines + 1] = string.format("            vpiml.%s_multi_beat_%d(this.hdl, %s)", vpi_prefix, n, table.concat(args, ", "))
    end
    lines[#lines + 1] = "        else"
    lines[#lines + 1] = "            for i = 1, this.beat_num do"
    lines[#lines + 1] = "                this.c_results[i - 1] = value[i]"
    lines[#lines + 1] = "            end"
    lines[#lines + 1] = string.format("            vpiml.%s_multi(this.hdl, this.c_results)", vpi_prefix)
    lines[#lines + 1] = "        end"
    return table.concat(lines, "\n")
end

-- Helper for array set_index dispatch (uses chosen_hdl instead of this.hdl)
local function gen_multi_array_set_dispatch(vpi_prefix, with_checks)
    local lines = {}
    lines[#lines + 1] = "        local beat_num = this.beat_num"
    if with_checks then
        lines[#lines + 1] = "        if #value ~= beat_num then"
        lines[#lines + 1] = '            assert(false, "len: " .. #value .. " =/= " .. this.beat_num)'
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = ""
    end
    for n = 3, 8 do
        local args = {}
        for i = 1, n do args[i] = "value[" .. i .. "]" end
        local kw = n == 3 and "if" or "elseif"
        lines[#lines + 1] = string.format("        %s beat_num == %d then", kw, n)
        lines[#lines + 1] = string.format("            vpiml.%s_multi_beat_%d(chosen_hdl, %s)", vpi_prefix, n, table.concat(args, ", "))
    end
    lines[#lines + 1] = "        else"
    lines[#lines + 1] = "            for i = 1, this.beat_num do"
    lines[#lines + 1] = "                this.c_results[i - 1] = value[i]"
    lines[#lines + 1] = "            end"
    lines[#lines + 1] = string.format("            vpiml.%s_multi(chosen_hdl, this.c_results)", vpi_prefix)
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

    -- Generate set/set_imm/set_force/set_imm_force with their dispatch chains
    local set_variants = {
        { name = "set",           vpi = "vpiml_set_value",           vpi64 = "vpiml_set_value64_force_single",           err_api = "set" },
        { name = "set_imm",      vpi = "vpiml_set_imm_value",      vpi64 = "vpiml_set_imm_value64_force_single",      err_api = "set" },
        { name = "set_force",    vpi = "vpiml_force_value",         vpi64 = "vpiml_force_value64_force_single",         err_api = "set_force" },
        { name = "set_imm_force", vpi = "vpiml_force_imm_value",    vpi64 = "vpiml_force_imm_value64_force_single",    err_api = "set_force" },
    }

    for _, sv in ipairs(set_variants) do
        emit(string.format([[
chdl.%s = function(this, value, force_single_beat)
    if force_single_beat then
        if type(value) == "table" then
            assert(false)
        end
        vpiml.%s(this.hdl, value)
    else
        if type(value) ~= "table" then
            assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:%s(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
        end
%s
    end
end
]], sv.name, sv.vpi64, sv.err_api, gen_multi_set_dispatch(sv.vpi)))
    end

    -- Unsafe variants
    local unsafe_variants = {
        { name = "set_unsafe",     vpi = "vpiml_set_value",      vpi64 = "vpiml_set_value64_force_single" },
        { name = "set_imm_unsafe", vpi = "vpiml_set_imm_value",  vpi64 = "vpiml_set_imm_value64_force_single" },
    }

    for _, sv in ipairs(unsafe_variants) do
        emit(string.format([[
chdl.%s = function(this, value, force_single_beat)
    if force_single_beat then
        vpiml.%s(this.hdl, value)
    else
%s
    end
end
]], sv.name, sv.vpi64, gen_multi_set_unsafe_dispatch(sv.vpi)))
    end

    -- Bitfield variants
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

    -- Array set_index variants
    local array_set_variants = {
        { name = "set_index",     vpi = "vpiml_set_value",     vpi64 = "vpiml_set_value64_force_single" },
        { name = "set_imm_index", vpi = "vpiml_set_imm_value", vpi64 = "vpiml_set_imm_value64_force_single" },
    }

    for _, sv in ipairs(array_set_variants) do
        emit(string.format([[
chdl_array.%s = function(this, index, value, force_single_beat)
    local chosen_hdl = this.array_hdls[index + 1]
    if force_single_beat then
        if type(value) == "table" then
            assert(false)
        end
        vpiml.%s(chosen_hdl, value)
    else
        if type(value) ~= "table" then
            assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
        end
%s
    end
end
]], sv.name, sv.vpi64, gen_multi_array_set_dispatch(sv.vpi, true)))
    end

    -- Array unsafe variants
    local array_unsafe_variants = {
        { name = "set_index_unsafe",     vpi = "vpiml_set_value",     vpi64 = "vpiml_force_value64_force_single" },
        { name = "set_imm_index_unsafe", vpi = "vpiml_set_imm_value", vpi64 = "vpiml_force_imm_value64_force_single" },
    }

    for _, sv in ipairs(array_unsafe_variants) do
        emit(string.format([[
chdl_array.%s = function(this, index, value, force_single_beat)
    local chosen_hdl = this.array_hdls[index + 1]
    if force_single_beat then
        vpiml.%s(chosen_hdl, value)
    else
%s
    end
end
]], sv.name, sv.vpi64, gen_multi_array_set_dispatch(sv.vpi, false)))
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
]])

    return table.concat(parts, "\n")
end

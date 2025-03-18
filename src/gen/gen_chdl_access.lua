--[[luajit-pro, pretty, {IS_SINGLE = 1, IS_DOUBLE = 0, IS_MULTI = 0}]]

local vpiml = require "vpiml"
local BitVec = require "BitVec"
local table_new = require "table.new"

function __LJP:comp_time()
    _G.chdl_apis = {
        "get",
        "get64",
        "set",
        "set_imm",
        "set_unsafe",
        "set_imm_unsafe",
        "set_cached",
        "set_imm_cached",
        "set_bitfield",
        "set_imm_bitfield",
        "set_bitfield_hex_str",
        "set_imm_bitfield_hex_str",
        "set_force",
        "set_imm_force",
        "set_release",
        "set_imm_release",
    }

    _G.chdl_array_apis = {
        "at",
        "get_index",
        "set_index",
        "set_imm_index",
        "set_index_unsafe",
        "set_imm_index_unsafe",
        "get_index_all",
        "get_index_bitvec",
        "set_index_bitfield",
        "set_imm_index_bitfield",
        "set_index_bitfield_hex_str",
        "set_imm_index_bitfield_hex_str",
        "set_index_all",
        "set_imm_index_all",
        "set_index_unsafe_all",
        "set_imm_index_unsafe_all",
    }

    require("pl.text").format_operator()
end

local assert = assert
local f = string.format

local chdl, chdl_array
function __LJP:comp_time()
    output("chdl = {")
    for _, api_name in ipairs(chdl_apis) do
        output([[{{api_name}} = function(this) assert(false, f("<chdl>:{{api_name}}() is not implemented! fullpath => %s bitwidth => %d", this.fullpath, this.width)) end,]])
    end
    output("}")

    output("chdl_array = {")
    for _, api_name in ipairs(chdl_array_apis) do
        output([[{{api_name}} = function(this) assert(false, f("Normal handle does not support <chdl>:at(), fullpath => %s bitwidth => %d is_array => %s", this.fullpath, this.width, tostring(this.is_array))) end,]])
    end
    output("}")
end

local function chdl_init()
    function __LJP:comp_time()
        keep_line()
        local function gen_getter_func()
            output([==[
                chdl.get = function(this, force_multi_beat)
                    if _G.IS_SINGLE then
                        return vpiml.vpiml_get_value(this.hdl)
                    elseif _G.IS_DOUBLE then
                        if force_multi_beat then
                            vpiml.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)
                            return this.c_results
                        else
                            return vpiml.vpiml_get_value64(this.hdl)
                        end
                    elseif _G.IS_MULTI then
                        vpiml.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)
                        return this.c_results
                    end
                end

                chdl.get64 = function (this)
                    
                    if _G.IS_SINGLE then
                        return this:get()
                    else
                        return vpiml.vpiml_get_value64(this.hdl)
                    end
                end

                chdl.get_bitvec = function (this)
                    if _G.IS_SINGLE then
                         if this.bitvec then
                            this.bitvec:_update_u32_vec(vpiml.vpiml_get_value(this.hdl))
                            return this.bitvec
                        else
                            this.bitvec = BitVec(vpiml.vpiml_get_value(this.hdl), this.width)
                            return this.bitvec
                        end
                    else
                        vpiml.vpiml_get_value_multi(this.hdl, this.c_results, this.beat_num)

                        if this.bitvec then
                            this.bitvec:_update_u32_vec(this.c_results)
                            return this.bitvec
                        else
                            this.bitvec = BitVec(this.c_results, this.width)
                            return this.bitvec
                        end
                    end
                end

            ]==])
        end

        local function gen_setter_func(is_imm)
            local prefix = is_imm and "_imm" or ""
            output([==[
                chdl.set{{prefix}} = function (this, value, force_single_beat)
                    if _G.IS_SINGLE then
                        vpiml.vpiml_set{{prefix}}_value(this.hdl, value)
                    elseif _G.IS_DOUBLE then
                        if force_single_beat then
                            vpiml.vpiml_set{{prefix}}_value64(this.hdl, value)
                        else
                            if type(value) ~= "table" then
                                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                            end

                            if #value ~= 2 then
                                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                            end

                            vpiml.vpiml_set{{prefix}}_value_multi_beat_2(this.hdl, value[1], value[2])
                        end
                    elseif _G.IS_MULTI then
                         if force_single_beat then
                            if type(value) == "table" then
                                assert(false)
                            end
                            vpiml.vpiml_set{{prefix}}_value64_force_single(this.hdl, value)
                        else
                            -- value is a table where <lsb ... msb>
                            if type(value) ~= "table" then
                                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                            end
                            
                            local beat_num = this.beat_num
                            if #value ~= beat_num then
                                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                            end

                            --# TODO: Check performance
                            if beat_num == 3 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_3(this.hdl, value[1], value[2], value[3]);
                            elseif beat_num == 4 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_4(this.hdl, value[1], value[2], value[3], value[4])
                            elseif beat_num == 5 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
                            elseif beat_num == 6 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                            elseif beat_num == 7 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                            elseif beat_num == 8 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                            else
                                for i = 1, this.beat_num do
                                    this.c_results[i - 1] = value[i]
                                end
                                vpiml.vpiml_set{{prefix}}_value_multi(this.hdl, this.c_results)
                            end
                        end
                    end
                end

                if _G.IS_SINGLE then
                    --#
                    --# Unsafe usage of CallableHDL:set()
                    --# Do not check value type and lenght of value table. 
                    --# Usually has higher performance than CallableHDL:set()
                    --#
                    chdl.set{{prefix}}_unsafe = chdl.set{{prefix}}

                    chdl.set{{prefix}}_cached = function (this, value)
                        if this.cached_value == value then
                            return
                        end

                        this.cached_value = value
                        vpiml.vpiml_set{{prefix}}_value(this.hdl, value)
                    end
                elseif _G.IS_DOUBLE then
                    chdl.set{{prefix}}_unsafe = function (this, value, force_single_beat)
                        --#
                        --# Unsafe usage of CallableHDL:set()
                        --# Do not check value type and lenght of value table. 
                        --# Usually has higher performance than CallableHDL:set()
                        --#
                        if force_single_beat then
                            vpiml.vpiml_set{{prefix}}_value64(this.hdl, value)
                        else
                            -- value is a table where <lsb ... msb>
                            vpiml.vpiml_set{{prefix}}_value_multi_beat_2(this.hdl, value[1], value[2]);
                        end
                    end
                elseif _G.IS_MULTI then
                    chdl.set{{prefix}}_unsafe = function (this, value, force_single_beat)
                        --#
                        --# Unsafe usage of CallableHDL:set()
                        --# Do not check value type and lenght of value table. 
                        --# Usually has higher performance than CallableHDL:set()
                        --#
                        if force_single_beat then
                            vpiml.vpiml_set{{prefix}}_value64_force_single(this.hdl, value)
                        else
                            --# value is a table where <lsb ... msb>
                            local beat_num = this.beat_num

                            if beat_num == 3 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_3(this.hdl, value[1], value[2], value[3]);
                            elseif beat_num == 4 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_4(this.hdl, value[1], value[2], value[3], value[4])
                            elseif beat_num == 5 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
                            elseif beat_num == 6 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                            elseif beat_num == 7 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                            elseif beat_num == 8 then
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                            else
                                for i = 1, this.beat_num do
                                    this.c_results[i - 1] = value[i]
                                end
                                vpiml.vpiml_set{{prefix}}_value_multi(this.hdl, this.c_results)
                            end
                        end
                    end
                end

                chdl.set{{prefix}}_bitfield = function (this, s, e, v)
                    if _G.IS_SINGLE then
                        vpiml.vpiml_set{{prefix}}_value(this.hdl, this:get_bitvec():_set_bitfield(s, e, v).u32_vec[1])
                    elseif _G.IS_DOUBLE then
                        local bv = this:get_bitvec():_set_bitfield(s, e, v)
                        vpiml.vpiml_set{{prefix}}_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
                    elseif _G.IS_MULTI then
                        local bv = this:get_bitvec():_set_bitfield(s, e, v)
                        this:set{{prefix}}_unsafe(bv.u32_vec)
                    end
                end

                chdl.set{{prefix}}_bitfield_hex_str = function (this, s, e, hex_str)
                    if _G.IS_SINGLE then
                        vpiml.vpiml_set_value(this.hdl, this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
                    elseif _G.IS_DOUBLE then
                        local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
                        vpiml.vpiml_set_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
                    elseif _G.IS_MULTI then
                        local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
                        this:set{{prefix}}_unsafe(bv.u32_vec)
                    end
                end

                chdl.set{{prefix}}_force = function (this, value, force_single_beat)
                    if _G.IS_SINGLE then
                        vpiml.vpiml_force{{prefix}}_value(this.hdl, value)
                    elseif _G.IS_DOUBLE then
                        if force_single_beat then
                            vpiml.vpiml_force{{prefix}}_value64(this.hdl, value)
                        else
                            if type(value) ~= "table" then
                                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set_force(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                            end

                            if #value ~= 2 then
                                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                            end

                            vpiml.vpiml_force{{prefix}}_value_multi_beat_2(this.hdl, value[1], value[2])
                        end
                    elseif _G.IS_MULTI then
                        if force_single_beat then
                            if type(value) == "table" then
                                assert(false)
                            end
                            vpiml.vpiml_force{{prefix}}_value64_force_single(this.hdl, value)
                        else
                            --# value is a table where <lsb ... msb>
                            if type(value) ~= "table" then
                                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set_force(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                            end
                            
                            local beat_num = this.beat_num
                            if #value ~= beat_num then
                                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                            end

                            --# TODO: Check performance
                            if beat_num == 3 then
                                vpiml.vpiml_force{{prefix}}_value_multi_beat_3(this.hdl, value[1], value[2], value[3]);
                            elseif beat_num == 4 then
                                vpiml.vpiml_force{{prefix}}_value_multi_beat_4(this.hdl, value[1], value[2], value[3], value[4])
                            elseif beat_num == 5 then
                                vpiml.vpiml_force{{prefix}}_value_multi_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
                            elseif beat_num == 6 then
                                vpiml.vpiml_force{{prefix}}_value_multi_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                            elseif beat_num == 7 then
                                vpiml.vpiml_force{{prefix}}_value_multi_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                            elseif beat_num == 8 then
                                vpiml.vpiml_force{{prefix}}_value_multi_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                            else
                                for i = 1, this.beat_num do
                                    this.c_results[i - 1] = value[i]
                                end
                                vpiml.vpiml_force{{prefix}}_value_multi(this.hdl, this.c_results)
                            end
                        end
                    end
                end

                chdl.set{{prefix}}_release = function (this)
                    vpiml.vpiml_release{{prefix}}_value(this.hdl)
                end
            ]==])
        end

        gen_getter_func()
        gen_setter_func(false)
        gen_setter_func(true)
    end
end

local function chdl_array_init()
    function __LJP:comp_time()
        keep_line()
        local function gen_getter_func()
            output([[
                chdl_array.get_index = function (this, index)
                    if _G.IS_SINGLE then
                        local chosen_hdl = this.array_hdls[index + 1]
                        return vpiml.vpiml_get_value(chosen_hdl)
                    elseif _G.IS_DOUBLE then
                        local chosen_hdl = this.array_hdls[index + 1]
                        if force_multi_beat then
                            vpiml.vpiml_get_value_multi(chosen_hdl, this.c_results, this.beat_num)
                            return this.c_results
                        else
                            return vpiml.vpiml_get_value64(chosen_hdl)
                        end
                    elseif _G.IS_MULTI then
                        local chosen_hdl = this.array_hdls[index + 1]
                        vpiml.vpiml_get_value_multi(chosen_hdl, this.c_results, this.beat_num)
                        return this.c_results
                    end
                end

                chdl_array.get_index_all = function (this, force_multi_beat)
                    if _G.IS_SINGLE then
                        local ret = table_new(this.array_size, 0)
                        for index = 0, this.array_size - 1 do
                            ret[index + 1] = this.get_index(this, index, force_multi_beat)
                        end
                        return ret
                    elseif _G.IS_DOUBLE then
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
                    elseif _G.IS_MULTI then
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
                end

                chdl_array.get_index_bitvec = function (this, index)
                    if _G.IS_SINGLE then
                        local chosen_hdl = this.array_hdls[index + 1]
                        if this.array_bitvecs[index + 1] then
                            this.array_bitvecs[index + 1]:_update_u32_vec(vpiml.vpiml_get_value(chosen_hdl))
                            return this.array_bitvecs[index + 1]
                        else
                            this.array_bitvecs[index + 1] = BitVec(vpiml.vpiml_get_value(chosen_hdl), this.width)
                            return this.array_bitvecs[index + 1]
                        end
                    else
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
                end
            ]])
        end
        
        local function gen_setter_func(is_imm)
            local prefix = is_imm and "_imm" or ""
            output([[
                chdl_array.set{{prefix}}_index = function(this, index, value, force_single_beat)
                    local chosen_hdl = this.array_hdls[index + 1]
                    if _G.IS_SINGLE then
                        vpiml.vpiml_set{{prefix}}_value(chosen_hdl, value)
                    elseif _G.IS_DOUBLE then
                        if force_single_beat then
                            if type(value) == "table" then
                                assert(false)
                            end
                            vpiml.vpiml_set{{prefix}}_value64(chosen_hdl, value)
                        else
                            --# value is a table where <lsb ... msb>
                            if type(value) ~= "table" then
                                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                            end
                            
                            if #value ~= 2 then
                                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                            end

                            vpiml.vpiml_set{{prefix}}_value_multi_beat_2(chosen_hdl, value[1], value[2])
                        end
                    elseif _G.IS_MULTI then
                        if force_single_beat then
                            if type(value) == "table" then
                                assert(false)
                            end
                            vpiml.vpiml_set{{prefix}}_value64_force_single(chosen_hdl, value)
                        else
                            --# value is a table where <lsb ... msb>
                            if type(value) ~= "table" then
                                assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                            end
                            
                            local beat_num = this.beat_num
                            if #value ~= beat_num then
                                assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                            end

                            if beat_num == 3 then     --# 32 * 3 = 96 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_3(chosen_hdl, value[1], value[2], value[3])
                            elseif beat_num == 4 then --# 32 * 4 = 128 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_4(chosen_hdl, value[1], value[2], value[3], value[4])
                            elseif beat_num == 5 then --# 32 * 5 = 160 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_5(chosen_hdl, value[1], value[2], value[3], value[4], value[5])
                            elseif beat_num == 6 then --# 32 * 6 = 192 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_6(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                            elseif beat_num == 7 then --# 32 * 7 = 224 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_7(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                            elseif beat_num == 8 then --# 32 * 8 = 256 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_8(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                            else
                                for i = 1, this.beat_num do
                                    this.c_results[i - 1] = value[i]
                                end
                                vpiml.vpiml_set{{prefix}}_value_multi(chosen_hdl, this.c_results)
                            end
                        end
                    end
                end

                if _G.IS_SINGLE then
                    chdl_array.set{{prefix}}_index_unsafe = chdl_array.set{{prefix}}_index
                elseif _G.IS_DOUBLE then
                    chdl_array.set{{prefix}}_index_unsafe = function(this, index, value, force_single_beat)
                        local chosen_hdl = this.array_hdls[index + 1]
                        if force_single_beat then
                            vpiml.vpiml_set{{prefix}}_value64(chosen_hdl, value)
                        else
                            --# value is a table where <lsb ... msb>
                            vpiml.vpiml_set{{prefix}}_value_multi_beat_2(chosen_hdl, value[1], value[2])
                        end
                    end
                elseif _G.IS_MULTI then
                    chdl_array.set{{prefix}}_index_unsafe = function(this, index, value, force_single_beat)
                        local chosen_hdl = this.array_hdls[index + 1]
                        if force_single_beat then
                            vpiml.vpiml_force{{prefix}}_value64_force_single(chosen_hdl, value)
                        else
                            --# value is a table where <lsb ... msb>
                            local beat_num = this.beat_num

                            if beat_num == 3 then     --# 32 * 3 = 96 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_3(chosen_hdl, value[1], value[2], value[3])
                            elseif beat_num == 4 then --# 32 * 4 = 128 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_4(chosen_hdl, value[1], value[2], value[3], value[4])
                            elseif beat_num == 5 then --# 32 * 5 = 160 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_5(chosen_hdl, value[1], value[2], value[3], value[4], value[5])
                            elseif beat_num == 6 then --# 32 * 6 = 192 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_6(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                            elseif beat_num == 7 then --# 32 * 7 = 224 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_7(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                            elseif beat_num == 8 then --# 32 * 8 = 256 bits
                                vpiml.vpiml_set{{prefix}}_value_multi_beat_8(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                            else
                                for i = 1, this.beat_num do
                                    this.c_results[i - 1] = value[i]
                                end
                                vpiml.vpiml_set{{prefix}}_value_multi(chosen_hdl, this.c_results)
                            end
                        end
                    end
                end

                chdl_array.set{{prefix}}_index_bitfield = function (this, index, s, e, v)
                    local chosen_hdl = this.array_hdls[index + 1]
                    if _G.IS_SINGLE then
                        vpiml.vpiml_set{{prefix}}_value(chosen_hdl, this:get_index_bitvec(index):_set_bitfield(s, e, v).u32_vec[1])
                    elseif _G.IS_DOUBLE then
                        local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
                        vpiml.vpiml_set{{prefix}}_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
                    elseif _G.IS_MULTI then
                        local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
                        this:set{{prefix}}_index_unsafe(index, bv.u32_vec)
                    end
                end

                chdl_array.set{{prefix}}_index_bitfield_hex_str = function (this, index, s, e, hex_str)
                    local chosen_hdl = this.array_hdls[index + 1]
                    if _G.IS_SINGLE then
                        vpiml.vpiml_set{{prefix}}_value(chosen_hdl, this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
                    elseif _G.IS_DOUBLE then
                        local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
                        vpiml.vpiml_set{{prefix}}_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
                    elseif _G.IS_MULTI then
                        local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
                        this:set_index_unsafe(index, bv.u32_vec)
                    end
                end

                chdl_array.set{{prefix}}_index_all = function (this, values, force_single_beat)
                    force_single_beat = force_single_beat or false
                    for index = 0, this.array_size - 1 do
                        this:set{{prefix}}_index(index, values[index + 1], force_single_beat)
                    end
                end

                chdl_array.set{{prefix}}_index_unsafe_all = function (this, values, force_single_beat)
                    force_single_beat = force_single_beat or false
                    for index = 0, this.array_size - 1 do
                        this:set{{prefix}}_index_unsafe(index, values[index + 1], force_single_beat)
                    end
                end
            ]])
        end

        output([[
            chdl_array.at = function (this, idx)
                this.hdl = this.array_hdls[idx + 1] -- index is zero-based
                return this
            end
        ]])
        gen_getter_func()
        gen_setter_func(false)
        gen_setter_func(true)
    end
end

return function (is_array)
    chdl_init()

    if is_array then
        chdl_array_init()
        for k, func in pairs(chdl_array) do
            chdl[k] = func
        end
    end

    return chdl
end
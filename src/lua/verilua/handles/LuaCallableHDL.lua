local ffi = require "ffi"
local math = require "math"
local debug = require "debug"
local BitVec = require "BitVec"
local utils = require "LuaUtils"
local class = require "pl.class"
local texpect = require "TypeExpect"
local table_new = require "table.new"

local BeatWidth = 32

local type = type
local print = print
local assert = assert
local f = string.format
local tonumber = tonumber
local setmetatable = setmetatable
local table_insert = table.insert

local C = ffi.C
local ffi_new = ffi.new
local ffi_string = ffi.string

local HexStr = _G.HexStr
local BinStr = _G.BinStr
local DecStr = _G.DecStr
local verilua_debug = _G.verilua_debug
local await_posedge_hdl = _G.await_posedge_hdl
local await_negedge_hdl = _G.await_negedge_hdl
local always_await_posedge_hdl = _G.always_await_posedge_hdl
local await_noop = _G.await_noop

local compare_value_str = utils.compare_value_str

ffi.cdef[[
  long long c_handle_by_name_safe(const char* name);
  long long c_handle_by_index(const char *parent_name, long long hdl, int index);

  const char *c_get_hdl_type(long long handle);
  unsigned int c_get_signal_width(long long handle);

  void c_set_value(long long handle, uint32_t value);
  void c_set_value64(long long handle, uint64_t value);
  void c_set_value_force_single(long long handle, uint32_t value, uint32_t size);
  
  uint32_t c_get_value(long long handle);
  uint64_t c_get_value64(long long handle);

  void c_get_value_multi(long long handle, uint32_t *ret, int n);

  void c_set_value_multi(long long handle, uint32_t *values, int length);
  void c_set_value_multi_beat_2(long long handle, uint32_t v0, uint32_t v1); 
  void c_set_value_multi_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2); 
  void c_set_value_multi_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
  void c_set_value_multi_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
  void c_set_value_multi_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
  void c_set_value_multi_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
  void c_set_value_multi_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);

  void c_set_value_str(long long handle, const char *str);
  void c_set_value_hex_str(long long handle, const char *str);
  const char *c_get_value_str(long long handle, int format);
]]

local CallableHDL = class()

function CallableHDL:_init(fullpath, name, hdl)
    texpect.expect_string(fullpath, "fullpath")

    self.__type = "CallableHDL"
    self.fullpath = fullpath
    self.name = name or "Unknown"
    self.always_fired = false -- used by <chdl>:always_posedge()

    local tmp_hdl = hdl or C.c_handle_by_name_safe(fullpath)
    if tmp_hdl == -1 then
        local err = f("[CallableHDL:_init] No handle found! fullpath: %s name: %s\t\n%s\n", fullpath, self.name == "" and "Unknown" or self.name, debug.traceback())
        verilua_debug(err)
        assert(false, err)
    end
    self.hdl = tmp_hdl
    self.hdl_type = ffi_string((C.c_get_hdl_type(self.hdl)))

    self.is_array = false
    self.array_size = 0
    if self.hdl_type == "vpiReg" or self.hdl_type == "vpiNet" or self.hdl_type == "vpiLogicVar" then
        self.is_array = false
    elseif self.hdl_type == "vpiRegArray" or self.hdl_type == "vpiNetArray" or self.hdl_type == "vpiMemory" then
        -- 
        -- for multidimensional reg array, VCS vpi treat it as "vpiRegArray" while
        -- Verilator treat it as "vpiMemory"
        -- 
        self.is_array = true
        self.array_size = tonumber(C.c_get_signal_width(self.hdl))
        self.array_hdls = table_new(self.array_size, 0)
        self.array_bitvecs = table_new(self.array_size, 0)
        for i = 1, self.array_size do
            self.array_hdls[i] = C.c_handle_by_index(self.fullpath, self.hdl, i - 1)
        end
    else
        assert(false, f("Unknown hdl_type => %s fullpath => %s name => %s", self.hdl_type, self.fullpath, self.name))
    end

    local _hdl = nil
    do
        if self.is_array then
            _hdl = self.array_hdls[1]
        else
            _hdl = self.hdl
        end
        
        assert(_hdl ~= nil)
    end

    self.width = tonumber(C.c_get_signal_width(_hdl))
    self.beat_num = math.ceil(self.width / BeatWidth)
    self.is_multi_beat = not (self.beat_num == 1)

    self.c_results = ffi_new("uint32_t[?]", self.beat_num + 1) -- create a new array to store the result
                                                               -- c_results[0] is the lenght of the beat data since a normal lua table use 1 as the first index of array while ffi cdata still use 0

    verilua_debug("New CallableHDL => ", "name: " .. self.name, "fullpath: " .. self.fullpath, "width: " .. self.width, "beat_num: " .. self.beat_num, "is_multi_beat: " .. tostring(self.is_multi_beat))

    if self.is_array == false then
        if self.beat_num == 1 then
            self.get = function (this)
                return C.c_get_value(this.hdl)
            end

            self.get_bitvec = function (this)
                if this.bitvec then
                    this.bitvec:_update_u32_vec(C.c_get_value(this.hdl))
                    return this.bitvec
                else
                    this.bitvec = BitVec(C.c_get_value(this.hdl), this.width)
                    return this.bitvec
                end
            end

            self.set = function (this, value)
                C.c_set_value(this.hdl, value)
            end

            self.set_unsafe = self.set

            self.set_bitfield = function (this, s, e, v)
                C.c_set_value(this.hdl, this:get_bitvec():_set_bitfield(s, e, v).u32_vec[1])
            end

            self.set_bitfield_hex_str = function (this, s, e, hex_str)
                C.c_set_value(this.hdl, this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
            end
        elseif self.beat_num == 2 then
            self.get = function (this, force_multi_beat)
                if force_multi_beat then
                    C.c_get_value_multi(this.hdl, this.c_results, this.beat_num)
                    return this.c_results
                else
                    return C.c_get_value64(this.hdl)
                end
            end

            self.get_bitvec = function (this)
                C.c_get_value_multi(this.hdl, this.c_results, this.beat_num)

                if this.bitvec then
                    this.bitvec:_update_u32_vec(this.c_results)
                    return this.bitvec
                else
                    this.bitvec = BitVec(this.c_results, this.width)
                    return this.bitvec
                end
            end

            self.set = function (this, value, force_single_beat)
                if force_single_beat then
                    C.c_set_value64(this.hdl, value)
                else
                    if type(value) ~= "table" then
                        assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                    end

                    if #value ~= 2 then
                        assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                    end

                    C.c_set_value_multi_beat_2(this.hdl, value[1], value[2])
                end
            end

            -- 
            -- Unsafe usage of CallableHDL:set()
            -- Do not check value type and lenght of value table. 
            -- Usually has higher performance than CallableHDL:set()
            -- 
            self.set_unsafe = function (this, value, force_single_beat)
                if force_single_beat then
                    C.c_set_value64(this.hdl, value)
                else
                    -- value is a table where <lsb ... msb>
                    C.c_set_value_multi_beat_2(this.hdl, value[1], value[2]);
                end
            end

            self.set_bitfield = function (this, s, e, v)
                local bv = this:get_bitvec():_set_bitfield(s, e, v)
                C.c_set_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
            end

            self.set_bitfield_hex_str = function (this, s, e, hex_str)
                local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
                C.c_set_value_multi_beat_2(this.hdl, bv.u32_vec[1], bv.u32_vec[2])
            end
        else -- self.beat_num >= 3
            assert(self.beat_num > 2)

            self.get = function (this)
                C.c_get_value_multi(this.hdl, this.c_results, this.beat_num)
                return this.c_results
            end

            self.get_bitvec = function (this)
                C.c_get_value_multi(this.hdl, this.c_results, this.beat_num)

                if this.bitvec then
                    this.bitvec:_update_u32_vec(this.c_results)
                    return this.bitvec
                else
                    this.bitvec = BitVec(this.c_results, this.width)
                    return this.bitvec
                end
            end

            self.set = function (this, value, force_single_beat)
                if force_single_beat then
                    if type(value) == "table" then
                        assert(false)
                    end
                    C.c_set_value_force_single(this.hdl, value, this.beat_num)
                else
                    -- value is a table where <lsb ... msb>
                    if type(value) ~= "table" then
                        assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                    end
                    
                    local beat_num = this.beat_num
                    if #value ~= beat_num then
                        assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                    end

                    if beat_num == 3 then
                        C.c_set_value_multi_beat_3(this.hdl, value[1], value[2], value[3]);
                    elseif beat_num == 4 then
                        C.c_set_value_multi_beat_4(this.hdl, value[1], value[2], value[3], value[4])
                    elseif beat_num == 5 then
                        C.c_set_value_multi_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
                    elseif beat_num == 6 then
                        C.c_set_value_multi_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                    elseif beat_num == 7 then
                        C.c_set_value_multi_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                    elseif beat_num == 8 then
                        C.c_set_value_multi_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                    else
                        for i = 1, this.beat_num do
                            this.c_results[i - 1] = value[i]
                        end
                        C.c_set_value_multi(this.hdl, this.c_results, this.beat_num)
                    end
                end
            end

            self.set_unsafe = function (this, value, force_single_beat)
                if force_single_beat then
                    C.c_set_value_force_single(this.hdl, value, this.beat_num)
                else
                    -- value is a table where <lsb ... msb>
                    local beat_num = this.beat_num

                    if beat_num == 3 then
                        C.c_set_value_multi_beat_3(this.hdl, value[1], value[2], value[3]);
                    elseif beat_num == 4 then
                        C.c_set_value_multi_beat_4(this.hdl, value[1], value[2], value[3], value[4])
                    elseif beat_num == 5 then
                        C.c_set_value_multi_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
                    elseif beat_num == 6 then
                        C.c_set_value_multi_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                    elseif beat_num == 7 then
                        C.c_set_value_multi_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                    elseif beat_num == 8 then
                        C.c_set_value_multi_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                    else
                        for i = 1, this.beat_num do
                            this.c_results[i - 1] = value[i]
                        end
                        C.c_set_value_multi(this.hdl, this.c_results, this.beat_num)
                    end
                end
            end

            self.set_bitfield = function (this, s, e, v)
                local bv = this:get_bitvec():_set_bitfield(s, e, v)
                this:set_unsafe(bv.u32_vec)
            end

            self.set_bitfield_hex_str = function (this, s, e, hex_str)
                local bv = this:get_bitvec():_set_bitfield_hex_str(s, e, hex_str)
                this:set_unsafe(bv.u32_vec)
            end
        end

        -- 
        -- #define vpiBinStrVal          1
        -- #define vpiOctStrVal          2
        -- #define vpiDecStrVal          3
        -- #define vpiHexStrVal          4
        -- 
        self.get_str = function (this, fmt)
            return ffi_string(C.c_get_value_str(this.hdl, fmt))
        end

        self.get_hex_str = function (this)
            return ffi_string(C.c_get_value_str(this.hdl, HexStr))
        end

        self.set_str = function (this, str)
            C.c_set_value_str(this.hdl, str)
        end

        self.set_hex_str = function (this, str)
            C.c_set_value_hex_str(this.hdl, str)
        end

        self.get_index = function (this, index, force_multi_beat)
            assert(false, f("[%s] Normal handle does not support <CallableHDL>:get_index()", this.fullpath))
        end

        self.get_index_all = function (this, index, force_multi_beat)
            assert(false, f("[%s] Normal handle does not support <CallableHDL>:get_index_all()", this.fullpath))
        end

        self.get_index_str = function (this, index, fmt)
            assert(false, f("[%s] Normal handle does not support <CallableHDL>:get_str(fmt), instead using <CallableHDL>:get_index_str(index, fmt)", this.fullpath))
        end

        self.set_index = function(this, index, value, force_single_beat)
            assert(false, f("[%s] Normal handle does not support <CallableHDL>:set_index()", this.fullpath))
        end

        self.set_index_unsafe = function (this, index, value, force_single_beat)
            assert(false, f("[%s] Normal handle does not support <CallableHDL>:set_index_unsafe()", this.fullpath))
        end

        self.set_index_str = function (this, index, str)
            assert(false, f("[%s] Normal handle does not support <CallableHDL>:set_index_str(index, str), instead using <CallableHDL>:set_str(str)", this.fullpath))
        end

    else -- self.is_array == true
        if self.beat_num == 1 then
            -- 
            -- get array value by index, the index value is start with 0
            -- 
            self.get_index = function (this, index)
                local chosen_hdl = this.array_hdls[index + 1]
                return C.c_get_value(chosen_hdl)
            end

            self.set_index = function(this, index, value)
                local chosen_hdl = this.array_hdls[index + 1]
                C.c_set_value(chosen_hdl, value)
            end

            self.set_index_unsafe = self.set_index

            self.get_index_all = function (this, force_multi_beat)
                local ret = table_new(this.array_size, 0)
                for index = 0, this.array_size - 1 do
                    ret[index + 1] = this.get_index(this, index, force_multi_beat)
                end
                return ret
            end
            
            self.get_index_bitvec = function (this, index)
                local chosen_hdl = this.array_hdls[index + 1]
                if this.array_bitvecs[index + 1] then
                    this.array_bitvecs[index + 1]:_update_u32_vec(C.c_get_value(chosen_hdl))
                    return this.array_bitvecs[index + 1]
                else
                    this.array_bitvecs[index + 1] = BitVec(C.c_get_value(chosen_hdl), this.width)
                    return this.array_bitvecs[index + 1]
                end
            end

            self.set_index_bitfield = function (this, index, s, e, v)
                local chosen_hdl = this.array_hdls[index + 1]
                C.c_set_value(chosen_hdl, this:get_index_bitvec(index):_set_bitfield(s, e, v).u32_vec[1])
            end

            self.set_index_bitfield_hex_str = function (this, index, s, e, hex_str)
                local chosen_hdl = this.array_hdls[index + 1]
                C.c_set_value(chosen_hdl, this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str).u32_vec[1])
            end
        elseif self.beat_num == 2 then
            self.get_index = function (this, index, force_multi_beat)
                local chosen_hdl = this.array_hdls[index + 1]
                if force_multi_beat then
                    C.c_get_value_multi(chosen_hdl, this.c_results, this.beat_num)
                    return this.c_results
                else
                    return C.c_get_value64(chosen_hdl)
                end
            end

            self.set_index = function(this, index, value, force_single_beat)
                local chosen_hdl = this.array_hdls[index + 1]
                if force_single_beat then
                    if type(value) == "table" then
                        assert(false)
                    end
                    C.c_set_value64(chosen_hdl, value)
                else
                    -- value is a table where <lsb ... msb>
                    if type(value) ~= "table" then
                        assert(false, type(value) .. " =/= table \n" .. this.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua or you can call <CallableHDL>:set(<value>, <force_single_beat>) with <force_single_beat> == true, name => " .. this.fullpath)
                    end
                    
                    if #value ~= 2 then
                        assert(false, "len: " .. #value .. " =/= " .. this.beat_num)
                    end

                    C.c_set_value_multi_beat_2(chosen_hdl, value[1], value[2])
                end
            end

            self.set_index_unsafe = function(this, index, value, force_single_beat)
                local chosen_hdl = this.array_hdls[index + 1]
                if force_single_beat then
                    C.c_set_value64(chosen_hdl, value)
                else
                    -- value is a table where <lsb ... msb>
                    C.c_set_value_multi_beat_2(chosen_hdl, value[1], value[2])
                end
            end

            self.get_index_all = function (this, force_multi_beat)
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

            self.get_index_bitvec = function (this, index)
                local chosen_hdl = this.array_hdls[index + 1]
                C.c_get_value_multi(chosen_hdl, this.c_results, this.beat_num)

                if this.array_bitvecs[index + 1] then
                    this.array_bitvecs[index + 1]:_update_u32_vec(this.c_results)
                    return this.array_bitvecs[index + 1]
                else
                    this.array_bitvecs[index + 1] = BitVec(this.c_results, this.width)
                    return this.array_bitvecs[index + 1]
                end
            end

            self.set_index_bitfield = function (this, index, s, e, v)
                local chosen_hdl = this.array_hdls[index + 1]
                local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
                C.c_set_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
            end

            self.set_index_bitfield_hex_str = function (this, index, s, e, hex_str)
                local chosen_hdl = this.array_hdls[index + 1]
                local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
                C.c_set_value_multi_beat_2(chosen_hdl, bv.u32_vec[1], bv.u32_vec[2])
            end
        else -- self.beat_num >= 3
            assert(self.beat_num > 2)

            self.get_index = function (this, index)
                local chosen_hdl = this.array_hdls[index + 1]
                C.c_get_value_multi(chosen_hdl, this.c_results, this.beat_num)
                return this.c_results
            end

            self.get_index_bitvec = function (this, index)
                local chosen_hdl = this.array_hdls[index + 1]
                C.c_get_value_multi(chosen_hdl, this.c_results, this.beat_num)

                if this.array_bitvecs[index + 1] then
                    this.array_bitvecs[index + 1]:_update_u32_vec(this.c_results)
                    return this.array_bitvecs[index + 1]
                else
                    this.array_bitvecs[index + 1] = BitVec(this.c_results, this.width)
                    return this.array_bitvecs[index + 1]
                end
            end

            self.set_index = function(this, index, value, force_single_beat)
                local chosen_hdl = this.array_hdls[index + 1]
                if force_single_beat then
                    if type(value) == "table" then
                        assert(false)
                    end
                    C.c_set_value64(chosen_hdl, value)
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
                        C.c_set_value_multi_beat_3(chosen_hdl, value[1], value[2], value[3])
                    elseif beat_num == 4 then -- 32 * 4 = 128 bits
                        C.c_set_value_multi_beat_4(chosen_hdl, value[1], value[2], value[3], value[4])
                    elseif beat_num == 5 then -- 32 * 5 = 160 bits
                        C.c_set_value_multi_beat_5(chosen_hdl, value[1], value[2], value[3], value[4], value[5])
                    elseif beat_num == 6 then -- 32 * 6 = 192 bits
                        C.c_set_value_multi_beat_6(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                    elseif beat_num == 7 then -- 32 * 7 = 224 bits
                        C.c_set_value_multi_beat_7(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                    elseif beat_num == 8 then -- 32 * 8 = 256 bits
                        C.c_set_value_multi_beat_8(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                    else
                        for i = 1, this.beat_num do
                            this.c_results[i - 1] = value[i]
                        end
                        C.c_set_value_multi(chosen_hdl, this.c_results, this.beat_num)
                    end
                end
            end

            self.set_index_unsafe = function(this, index, value, force_single_beat)
                local chosen_hdl = this.array_hdls[index + 1]
                if force_single_beat then
                    C.c_set_value64(chosen_hdl, value)
                else
                    -- value is a table where <lsb ... msb>
                    local beat_num = this.beat_num

                    if beat_num == 3 then     -- 32 * 3 = 96 bits
                        C.c_set_value_multi_beat_3(chosen_hdl, value[1], value[2], value[3])
                    elseif beat_num == 4 then -- 32 * 4 = 128 bits
                        C.c_set_value_multi_beat_4(chosen_hdl, value[1], value[2], value[3], value[4])
                    elseif beat_num == 5 then -- 32 * 5 = 160 bits
                        C.c_set_value_multi_beat_5(chosen_hdl, value[1], value[2], value[3], value[4], value[5])
                    elseif beat_num == 6 then -- 32 * 6 = 192 bits
                        C.c_set_value_multi_beat_6(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                    elseif beat_num == 7 then -- 32 * 7 = 224 bits
                        C.c_set_value_multi_beat_7(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                    elseif beat_num == 8 then -- 32 * 8 = 256 bits
                        C.c_set_value_multi_beat_8(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                    else
                        for i = 1, this.beat_num do
                            this.c_results[i - 1] = value[i]
                        end
                        C.c_set_value_multi(chosen_hdl, this.c_results, this.beat_num)
                    end
                end
            end

            self.get_index_all = function (this)
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

            self.set_index_bitfield = function (this, index, s, e, v)
                local bv = this:get_index_bitvec(index):_set_bitfield(s, e, v)
                this:set_index_unsafe(index, bv.u32_vec)
            end

            self.set_index_bitfield_hex_str = function (this, index, s, e, hex_str)
                local bv = this:get_index_bitvec(index):_set_bitfield_hex_str(s, e, hex_str)
                this:set_index_unsafe(index, bv.u32_vec)
            end
        end

        self.get_index_str = function (this, index, fmt)
            local chosen_hdl = this.array_hdls[index + 1]
            return ffi_string(C.c_get_value_str(chosen_hdl, fmt))
        end

        self.get_index_hex_str = function (this, index)
            local chosen_hdl = this.array_hdls[index + 1]
            return ffi_string(C.c_get_value_str(chosen_hdl, HexStr))
        end

        self.set_index_str = function (this, index, str)
            local chosen_hdl = this.array_hdls[index + 1]
            C.c_set_value_str(chosen_hdl, str)
        end

        self.set_index_hex_str = function (this, index, str)
            local chosen_hdl = this.array_hdls[index + 1]
            C.c_set_value_hex_str(chosen_hdl, str)
        end

        self.get = function(this)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:get(force_multi_beat), instead using <CallableHDL>:get_index(index, force_multi_beat)", this.fullpath))
        end

        self.get_bitvec = function(this)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:get_bitvec(), instead using <CallableHDL>:get_index_bitvec(index)", this.fullpath))
        end

        self.set = function (this, value, force_single_beat)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:set(value), instead using <CallableHDL>:set_index(index)", this.fullpath))
        end

        self.set_unsafe = function (this, value, force_single_beat)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:set_unsafe(value), instead using <CallableHDL>:set_index_unsafe(index)", this.fullpath))
        end

        self.get_str = function (this, fmt)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:get_str(fmt), instead using <CallableHDL>:get_index_str(index, fmt)", this.fullpath))
        end

        self.get_hex_str = function (this)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:get_hex_str(), instead using <CallableHDL>:get_index_hex_str(index, fmt)", this.fullpath))
        end

        self.set_str = function (this, str)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:set_str(str), instead using <CallableHDL>:set_index_str(index, str)", this.fullpath))
        end

        self.set_bitfield = function (this, s, e, v)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:set_bitfield(s, e, v), instead using <CallableHDL>:set_index_bitfield(index, s, e, v)", this.fullpath))
        end

        self.set_bitfield_hex_str = function (this, s, e, hex_str)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:set_bitfield_hex_str(s, e, hex_str), instead using <CallableHDL>:set_index_bitfield_hex_str(index, hex_str)", this.fullpath))
        end

        self.set_hex_str = function (this, str)
            assert(false, f("[%s] Array handle does not support <CallableHDL>:set_hex_str(str), instead using <CallableHDL>:set_index_hex_str(index, str)", this.fullpath))
        end
    end

    self.set_index_all = function (this, values, force_single_beat)
        force_single_beat = force_single_beat or false
        for index = 0, this.array_size - 1 do
            this.set_index(this, index, values[index + 1], force_single_beat)
        end
    end

    self.set_index_unsafe_all = function (this, values, force_single_beat)
        force_single_beat = force_single_beat or false
        for index = 0, this.array_size - 1 do
            this.set_index_unsafe(this, index, values[index + 1], force_single_beat)
        end
    end

    if self.width == 1 then
        -- 
        -- Example:
        --      local clock = ("tb_top.clock"):chdl()
        --      clock:posedge()
        --      
        --      local clock = CallableHDL("tb_top.clock", "name of clock chdl")
        --      clock:posedge()
        --      
        --      clock:posedge(10)
        --      clock:posedge(123, function (c)
        --          -- body
        --          print("current is => " .. c)
        --       end)
        -- 
        self.posedge = function (this, times, func)
            local _times = times or 1
            if _times == 1 then
                await_posedge_hdl(this.hdl)
            else
                local has_func = func ~= nil
                for i = 1, _times do
                    if has_func then
                        func(i)
                    end
                    await_posedge_hdl(this.hdl)
                end
            end
        end

        -- 
        -- Example: the same as posedge
        -- 
        self.negedge= function (this, times, func)
            local _times = times or 1
            if _times == 1 then
                await_negedge_hdl(this.hdl)
            else
                local has_func = func ~= nil
                for i = 1, _times do
                    if has_func then
                        func(i)
                    end
                    await_negedge_hdl(this.hdl)
                end
            end
        end

        -- 
        -- Example:
        --      local clock = ("tb_top.clock"):chdl()
        --      clodk:always_posedge()
        -- 
        self.always_posedge = function (this)
            if this.always_fired == false then
                this.always_fired = true
                always_await_posedge_hdl(this.hdl)
            else
                await_noop()
            end
        end

        -- 
        -- Example:
        --      local clock_chdl = ("tb_top.clock"):chdl()
        --          |_  or  local clock_chdl = dut.clock:chdl()
        --      local condition_meet = clock_chdl:posedge_until(100, function func()
        --          return dut.cycles() >= 100
        --      end)
        -- 
        self.posedge_until = function (this, max_limit, func)
            assert(max_limit ~= nil)
            assert(type(max_limit) == "number")
            assert(max_limit >= 1)

            assert(func ~= nil)
            assert(type(func) == "function") 

            local condition_meet = false
            for i = 1, max_limit do
                condition_meet = func(i)
                assert(condition_meet ~= nil and type(condition_meet) == "boolean")

                if not condition_meet then
                    await_posedge_hdl(this.hdl)
                else
                    break
                end
            end

            return condition_meet
        end

        self.negedge_until = function (this, max_limit, func)
            assert(max_limit ~= nil)
            assert(type(max_limit) == "number")
            assert(max_limit >= 1)

            assert(func ~= nil)
            assert(type(func) == "function") 

            local condition_meet = false
            for i = 1, max_limit do
                condition_meet = func(i)
                assert(condition_meet ~= nil and type(condition_meet) == "boolean")
                
                if not condition_meet then
                    await_negedge_hdl(this.hdl)
                else
                    break 
                end
            end

            return condition_meet
        end
    else
        self.posedge = function(this, times)
            assert(false, f("hdl bit width == %d > 1, <chdl>:posedge() only support 1-bit hdl", this.width))
        end

        self.negedge= function(this, times)
            assert(false, f("hdl bit width == %d > 1, <chdl>:negedge() only support 1-bit hdl", this.width))
        end

        self.always_posedge = function (this)
            assert(false, f("hdl bit width == %d > 1, <chdl>:always_posedge() only support 1-bit hdl", this.width))
        end

        self.posedge_until = function (this, max_limit, func)
            assert(false, f("hdl bit width == %d > 1, <chdl>:posedge_until() only support 1-bit hdl", this.width))
        end

        self.negedge_until = function (this, max_limit, func)
            assert(false, f("hdl bit width == %d > 1, <chdl>:negedge_until() only support 1-bit hdl", this.width))
        end
    end

    if self.is_array then
        self.dump_str = function (this)
            local s = f("[%s] => ", this.fullpath)
            
            for i = 1, this.array_size do
                s = s .. f("(%d): 0x%s ", i - 1, this.get_index_str(i, HexStr))
            end
            
            return s
        end
    else
        self.dump_str = function (this)
            return f("[%s] => 0x%s", this.fullpath, this:get_str(HexStr))
        end
    end

    self.dump = function (this)
        print(this:dump_str())
    end

    self.get_width = function (this)
        return this.width
    end

    self.expect = function (this, value)
        local typ = type(value)
        assert(typ == "number" or typ == "cdata")

        if this.is_multi_beat and this.beat_num > 2 then
            assert(false, "`<CallableHDL>:expect(value)` can only be used for hdl with 1 or 2 beat, use `<CallableHDL>:expect_[hex/bin/dec]_str(value_str)` instead! beat_num => " .. this.beat_num)    
        end

        if this:get() ~= value then
            assert(false, f("[%s] expect => %d, but got => %d", this.fullpath, value, this:get()))
        end
    end

    self.expect_not = function (this, value)
        local typ = type(value)
        assert(typ == "number" or typ == "cdata")

        if this.is_multi_beat and this.beat_num > 2 then
            assert(false, "`<CallableHDL>:expect_not(value)` can only be used for hdl with 1 or 2 beat, use `<CallableHDL>:expect_not_[hex/bin/dec]_str(value_str)` instead! beat_num => " .. this.beat_num)    
        end

        if this:get() == value then
            assert(false, f("[%s] expect not => %d, but got => %d", this.fullpath, value, this:get()))
        end
    end

    self.expect_hex_str = function(this, hex_value_str)
        assert(type(hex_value_str) == "string")
        if this:get_hex_str():lower():gsub("^0*", "") ~= hex_value_str:lower():gsub("^0*", "") then
            assert(false, f("[%s] expect => %s, but got => %s", this.fullpath, hex_value_str, this:get_str(HexStr)))
        end
    end

    self.expect_bin_str = function(this, bin_value_str)
        assert(type(bin_value_str) == "string")
        if this:get_str(BinStr):gsub("^0*", "") ~= bin_value_str:gsub("^0*") then
            assert(false, f("[%s] expect => %s, but got => %s", this.fullpath, bin_value_str, this:get_str(BinStr)))
        end
    end

    self.expect_dec_str = function(this, dec_value_str)
        assert(type(dec_value_str) == "string")
        if this:get_str(DecStr):gsub("^0*", "") ~= dec_value_str:gsub("^0*", "") then
            assert(false, f("[%s] expect => %s, but got => %s", this.fullpath, dec_value_str, this:get_str(DecStr)))
        end
    end

    self.expect_not_hex_str = function(this, hex_value_str)
        assert(type(hex_value_str) == "string")
        if this:get_hex_str():lower():gsub("^0*", "") == hex_value_str:lower():gsub("^0*", "") then
            assert(false, f("[%s] expect not => %s, but got => %s", this.fullpath, hex_value_str, this:get_str(HexStr)))
        end
    end

    self.expect_not_bin_str = function(this, bin_value_str)
        assert(type(bin_value_str) == "string")
        if this:get_str(BinStr):gsub("^0*", "") == bin_value_str:gsub("^0*") then
            assert(false, f("[%s] expect not => %s, but got => %s", this.fullpath, bin_value_str, this:get_str(BinStr)))
        end
    end

    self.expect_not_dec_str = function(this, dec_value_str)
        assert(type(dec_value_str) == "string")
        if this:get_str(DecStr):gsub("^0*", "") == dec_value_str:gsub("^0*", "") then
            assert(false, f("[%s] expect not => %s, but got => %s", this.fullpath, dec_value_str, this:get_str(DecStr)))
        end
    end

    self._if = function (this, condition)
        local _condition = false
        if type(condition) == "boolean" then
            _condition = condition
        elseif type(condition) == "function" then
            _condition = condition()

            local _condition_type = type(_condition)
            if _condition_type ~= "boolean" then
                assert(false, "invalid condition function return type: " .. _condition_type)
            end
        else
            assert(false, "invalid condition type: " .. type(condition))
        end

        if _condition then
            return this
        else
            return setmetatable({}, {
                __index = function(t, k)
                    return function ()
                        -- an empty function
                    end
                end
            })
        end
    end

    self.is = function (this, value)
        local typ = type(value)
        assert(typ == "number" or typ == "cdata")
        
        if this.is_multi_beat and this.beat_num > 2 then
            assert(false, "<CallableHDL>:is(value) can only be used for hdl with 1 or 2 beat")    
        end

        return this:get() == value
    end

    self.is_not = function (this, value)
        local typ = type(value)
        assert(typ == "number" or typ == "cdata")
        
        if this.is_multi_beat and this.beat_num > 2 then
            assert(false, "<CallableHDL>:is_not(value) can only be used for hdl with 1 or 2 beat")    
        end

        return this:get() ~= value
    end

    self.is_hex_str = function (this, hex_value_str)
        assert(type(hex_value_str) == "string")
        return this:get_hex_str():lower():gsub("^0*", "") == hex_value_str:lower():gsub("^0*", "")
    end

    self.is_bin_str = function (this, bin_value_str)
        assert(type(bin_value_str) == "string")
        return this:get_str(BinStr):gsub("^0*", "") == bin_value_str:gsub("^0*")
    end

    self.is_dec_str = function (this, dec_value_str)
        assert(type(dec_value_str) == "string")
        return this:get_str(DecStr):gsub("^0*", "") == dec_value_str:gsub("^0*", "")
    end
end

function CallableHDL:__call(force_multi_beat)
    -- 
    -- This method is deprecated, invoke <CallableHDL>:get() to get the signal value
    -- 
    assert(self.is_array == false, "For multidimensional array use <CallableHDL>:get_index()")
    
    force_multi_beat = force_multi_beat or false

    if self.is_multi_beat then
        if self.beat_num <= 2 and not force_multi_beat then
            return tonumber(C.c_get_value64(self.hdl))
        else
            C.c_get_value_multi(self.hdl, self.c_results, self.beat_num)
            return self.c_results
        end
    else
        return C.c_get_value(self.hdl)
    end
end

return CallableHDL
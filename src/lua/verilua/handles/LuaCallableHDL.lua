local ffi = require "ffi"
local debug = require "debug"
local utils = require "LuaUtils"
local class = require "pl.class"

local C = ffi.C
local compare_value_str = utils.compare_value_str

local HexStr = _G.HexStr
local BinStr = _G.BinStr
local DecStr = _G.DecStr
local verilua_debug = _G.verilua_debug
local await_posedge_hdl = _G.await_posedge_hdl
local await_negedge_hdl = _G.await_negedge_hdl
local always_await_posedge_hdl = _G.always_await_posedge_hdl
local await_noop = _G.await_noop

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

  void c_get_value_parallel(long long *hdls, uint32_t *values, int length);
  void c_get_value64_parallel(long long *hdls, uint64_t *values, int length);

  void c_set_value_parallel(long long *hdls, uint32_t *values, int length);
  void c_set_value64_parallel(long long *hdls, uint64_t *values, int length);

  void c_get_value_multi_1(long long handle, uint32_t *ret, int n);
  void c_get_value_multi_2(long long handle, uint32_t *ret, int n);

  void c_set_value_multi_1(long long handle, uint32_t *values, int length);
  void c_set_value_multi_1_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2); 
  void c_set_value_multi_1_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
  void c_set_value_multi_1_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
  void c_set_value_multi_1_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
  void c_set_value_multi_1_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
  void c_set_value_multi_1_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);

  void c_set_value_str(long long handle, const char *str);
  const char *c_get_value_str(long long handle, int format);
]]

local BeatWidth = 32
local type, assert, tonumber, print, format = type, assert, tonumber, print, string.format
local setmetatable = setmetatable
local table, math = table, math
local ffi_str = ffi.string
local ffi_new = ffi.new

local CallableHDL = class()

function CallableHDL:_init(fullpath, name, hdl)
    self.__type = "CallableHDL"
    self.fullpath = fullpath
    self.name = name or "Unknown"
    self.always_fired = false -- used by <chdl>:always_posedge()

    local tmp_hdl = hdl or C.c_handle_by_name_safe(fullpath)
    if tmp_hdl == -1 then
        print(debug.traceback("", 8))
        assert(false, format("No handle found => %s", fullpath))
    end
    self.hdl = tmp_hdl
    self.hdl_type = ffi_str((C.c_get_hdl_type(self.hdl)))

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
        self.array_hdls = {}
        for i = 1, self.array_size do
            self.array_hdls[i] = C.c_handle_by_index(self.fullpath, self.hdl, i - 1)
        end
    else
        assert(false, format("Unknown hdl_type => %s fullpath => %s name => %s", self.hdl_type, self.fullpath, self.name))
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

    -- 
    -- is_multi_beat == true 
    -- is_array == true
    -- 
    if self.is_multi_beat == true and self.is_array == true then
        self.get = function (this, force_multi_beat) 
            assert(false, format("[%s] Array handle does not support <CallableHDL>:get(force_multi_beat), instead using <CallableHDL>:get_index(index, force_multi_beat)", this.fullpath))
        end

        -- 
        -- get array value by index, the index value is start with 0
        -- 
        self.get_index = function (this, index, force_multi_beat)
            local chosen_hdl = this.array_hdls[index + 1]
            if this.beat_num <= 2 and not force_multi_beat then
                return tonumber(C.c_get_value64(chosen_hdl))
            else
                do
                    C.c_get_value_multi_2(chosen_hdl, this.c_results, this.beat_num)
                    return this.c_results
                end
            end
        end

        self.get_index_all = function (this, force_multi_beat)
            force_multi_beat = force_multi_beat or false
            local ret = {}
            for index = 0, this.array_size - 1 do
                if this.beat_num <= 2 and not force_multi_beat then
                    table.insert(ret, this.get_index(this, index, force_multi_beat))
                else
                    this.get_index(this, index, force_multi_beat)
                    
                    local tmp = {}
                    for i = 1, this.beat_num do
                        tmp[i] = this.c_results[i]
                    end

                    table.insert(ret, tmp)
                end
            end
            return ret
        end

        self.set = function (this, value, force_single_beat)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:set(value), instead using <CallableHDL>:set_index(index)", this.fullpath))
        end

        self.set_unsafe = function (this, value, force_single_beat)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:set_unsafe(value), instead using <CallableHDL>:set_index_unsafe(index)", this.fullpath))
        end

        self.set_index = function(this, index, value, force_single_beat)
            force_single_beat = force_single_beat or false
            local chosen_hdl = this.array_hdls[index + 1]
            if force_single_beat and this.beat_num == 2 then
                if type(value) == "table" then
                    assert(false)
                end
                C.c_set_value64(chosen_hdl, value)
            else
                if force_single_beat then
                    if type(value) == "table" then
                        assert(false)
                    end
                    C.c_set_value_force_single(chosen_hdl, value, this.beat_num)
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
                        C.c_set_value_multi_1_beat_3(chosen_hdl, value[1], value[2]);
                    elseif beat_num == 4 then -- 32 * 4 = 128 bits
                        C.c_set_value_multi_1_beat_4(chosen_hdl, value[1], value[2], value[3], value[4])
                    elseif beat_num == 5 then -- 32 * 5 = 160 bits
                        C.c_set_value_multi_1_beat_5(chosen_hdl, value[1], value[2], value[3], value[4], value[5])
                    elseif beat_num == 6 then -- 32 * 6 = 192 bits
                        C.c_set_value_multi_1_beat_6(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                    elseif beat_num == 7 then -- 32 * 7 = 224 bits
                        C.c_set_value_multi_1_beat_7(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                    elseif beat_num == 8 then -- 32 * 8 = 256 bits
                        C.c_set_value_multi_1_beat_8(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                    else
                        do
                            for i = 1, this.beat_num do
                                this.c_results[i - 1] = value[i]
                            end
                            C.c_set_value_multi_1(chosen_hdl, this.c_results, this.beat_num)
                        end
                    end
                end
            end
        end

        self.set_index_unsafe = function (this, index, value, force_single_beat)
            force_single_beat = force_single_beat or false
            local chosen_hdl = this.array_hdls[index + 1]
            if force_single_beat and this.beat_num == 2 then
                C.c_set_value64(chosen_hdl, value)
            else
                if force_single_beat then
                    C.c_set_value_force_single(chosen_hdl, value, this.beat_num)
                else
                    -- value is a table where <lsb ... msb>
                    local beat_num = this.beat_num

                    if beat_num == 3 then
                        C.c_set_value_multi_1_beat_3(chosen_hdl, value[1], value[2]);
                    elseif beat_num == 4 then
                        C.c_set_value_multi_1_beat_4(chosen_hdl, value[1], value[2], value[3], value[4])
                    elseif beat_num == 5 then
                        C.c_set_value_multi_1_beat_5(chosen_hdl, value[1], value[2], value[3], value[4], value[5])
                    elseif beat_num == 6 then
                        C.c_set_value_multi_1_beat_6(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                    elseif beat_num == 7 then
                        C.c_set_value_multi_1_beat_7(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                    elseif beat_num == 8 then
                        C.c_set_value_multi_1_beat_8(chosen_hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                    else
                        do
                            for i = 1, this.beat_num do
                                this.c_results[i - 1] = value[i]
                            end
                            C.c_set_value_multi_1(chosen_hdl, this.c_results, this.beat_num)
                        end
                    end
                end
            end
        end

        -- 
        -- #define vpiBinStrVal          1
        -- #define vpiOctStrVal          2
        -- #define vpiDecStrVal          3
        -- #define vpiHexStrVal          4
        -- 
        self.get_str = function (this, fmt)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:get_str(fmt), instead using <CallableHDL>:get_index_str(index, fmt)", this.fullpath))
        end

        self.get_index_str = function (this, index, fmt)
            local chosen_hdl = this.array_hdls[index + 1]
            return ffi_str(C.c_get_value_str(chosen_hdl, fmt))
        end

        self.set_str = function (this, str)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:set_str(str), instead using <CallableHDL>:set_index_str(index, str)", this.fullpath))
        end

        self.set_index_str = function (this, index, str)
            local chosen_hdl = this.array_hdls[index + 1]
            C.c_set_value_str(chosen_hdl, str)
        end

    -- 
    -- is_multi_beat == true 
    -- is_array == false
    -- 
    elseif self.is_multi_beat == true and self.is_array == false then
        self.get = function (this, force_multi_beat)
            if this.beat_num <= 2 and not force_multi_beat then
                return tonumber(C.c_get_value64(this.hdl))
            else
                do
                    C.c_get_value_multi_2(this.hdl, this.c_results, this.beat_num)
                    return this.c_results
                end
            end
        end

        self.get_index = function (this, index, force_multi_beat)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:get_index()", this.fullpath))
        end

        self.get_index_all = function (this, index, force_multi_beat)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:get_index_all()", this.fullpath))
        end

        self.set = function (this, value, force_single_beat)
            force_single_beat = force_single_beat or false
            if force_single_beat and this.beat_num == 2 then
                if type(value) == "table" then
                    assert(false)
                end
                C.c_set_value64(this.hdl, value)
            else
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
                        C.c_set_value_multi_1_beat_3(this.hdl, value[1], value[2]);
                    elseif beat_num == 4 then
                        C.c_set_value_multi_1_beat_4(this.hdl, value[1], value[2], value[3], value[4])
                    elseif beat_num == 5 then
                        C.c_set_value_multi_1_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
                    elseif beat_num == 6 then
                        C.c_set_value_multi_1_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                    elseif beat_num == 7 then
                        C.c_set_value_multi_1_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                    elseif beat_num == 8 then
                        C.c_set_value_multi_1_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                    else
                        do
                            for i = 1, this.beat_num do
                                this.c_results[i - 1] = value[i]
                            end
                            C.c_set_value_multi_1(this.hdl, this.c_results, this.beat_num)
                        end
                    end
                end
            end
        end

        -- 
        -- Unsafe usage of CallableHDL:set()
        -- Do not check value type and lenght of value table. 
        -- Usually has higher performance than CallableHDL:set()
        -- 
        self.set_unsafe = function (this, value, force_single_beat)
            force_single_beat = force_single_beat or false
            if force_single_beat and this.beat_num == 2 then
                C.c_set_value64(this.hdl, value)
            else
                if force_single_beat then
                    C.c_set_value_force_single(this.hdl, value, this.beat_num)
                else
                    -- value is a table where <lsb ... msb>
                    local beat_num = this.beat_num

                    if beat_num == 3 then
                        C.c_set_value_multi_1_beat_3(this.hdl, value[1], value[2]);
                    elseif beat_num == 4 then
                        C.c_set_value_multi_1_beat_4(this.hdl, value[1], value[2], value[3], value[4])
                    elseif beat_num == 5 then
                        C.c_set_value_multi_1_beat_5(this.hdl, value[1], value[2], value[3], value[4], value[5])
                    elseif beat_num == 6 then
                        C.c_set_value_multi_1_beat_6(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6])
                    elseif beat_num == 7 then
                        C.c_set_value_multi_1_beat_7(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7])
                    elseif beat_num == 8 then
                        C.c_set_value_multi_1_beat_8(this.hdl, value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8])
                    else
                        do
                            for i = 1, this.beat_num do
                                this.c_results[i - 1] = value[i]
                            end
                            C.c_set_value_multi_1(this.hdl, this.c_results, this.beat_num)
                        end
                    end
                end
            end
        end

        self.set_index = function(this, index, value, force_single_beat)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:set_index()", this.fullpath))
        end

        self.set_index_unsafe = function (this, index, value, force_single_beat)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:set_index_unsafe()", this.fullpath))
        end
    
        -- 
        -- #define vpiBinStrVal          1
        -- #define vpiOctStrVal          2
        -- #define vpiDecStrVal          3
        -- #define vpiHexStrVal          4
        -- 
        self.get_str = function (this, fmt)
            return ffi_str(C.c_get_value_str(this.hdl, fmt))
        end

        self.get_index_str = function (this, index, fmt)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:get_str(fmt), instead using <CallableHDL>:get_index_str(index, fmt)", this.fullpath))
        end

        self.set_str = function (this, str)
            C.c_set_value_str(this.hdl, str)
        end

        self.set_index_str = function (this, index, str)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:set_index_str(index, str), instead using <CallableHDL>:set_str(str)", this.fullpath))
        end

    -- 
    -- is_multi_beat == false
    -- is_array == true
    -- 
    elseif self.is_multi_beat == false and self.is_array == true then
        self.get = function(this)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:get(force_multi_beat), instead using <CallableHDL>:get_index(index, force_multi_beat)", this.fullpath))
        end

        self.get_index = function (this, index)
            local chosen_hdl = this.array_hdls[index + 1]
            return C.c_get_value(chosen_hdl)
        end

        self.get_index_all = function (this, force_multi_beat)
            force_multi_beat = force_multi_beat or false
            local ret = {}
            for index = 0, this.array_size - 1 do
                table.insert(ret, this.get_index(this, index, force_multi_beat))
            end
            return ret
        end

        self.set = function (this, value)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:set(value), instead using <CallableHDL>:set_index(index)", this.fullpath))
        end

        self.set_unsafe = function (this, value)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:set_unsafe(value), instead using <CallableHDL>:set_index_unsafe(index)", this.fullpath))
        end

        self.set_index = function(this, index, value)
            local chosen_hdl = this.array_hdls[index + 1]
            C.c_set_value(chosen_hdl, value)
        end

        self.set_index_unsafe = function (this, index, value)
            local chosen_hdl = this.array_hdls[index + 1]
            C.c_set_value(chosen_hdl, value)
        end

        -- 
        -- #define vpiBinStrVal          1
        -- #define vpiOctStrVal          2
        -- #define vpiDecStrVal          3
        -- #define vpiHexStrVal          4
        -- 
        self.get_str = function (this, fmt)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:get_str(fmt), instead using <CallableHDL>:get_index_str(index, fmt)", this.fullpath))
        end

        self.get_index_str = function (this, index, fmt)
            local chosen_hdl = this.array_hdls[index + 1]
            return ffi_str(C.c_get_value_str(chosen_hdl, fmt))
        end

        self.set_str = function (this, str)
            assert(false, format("[%s] Array handle does not support <CallableHDL>:set_str(str), instead using <CallableHDL>:set_index_str(index, str)", this.fullpath))
        end

        self.set_index_str = function (this, index, str)
            local chosen_hdl = this.array_hdls[index + 1]
            C.c_set_value_str(chosen_hdl, str)
        end

    -- 
    -- is_multi_beat == false
    -- is_array == false
    -- 
    elseif self.is_multi_beat == false and self.is_array == false then
        self.get = function(this)
            return C.c_get_value(this.hdl)
        end

        self.get_index = function (this, index)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:get_index()", this.fullpath))
        end

        self.get_index_all = function (this, index)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:get_index_all()", this.fullpath))
        end

        self.set = function (this, value)
            C.c_set_value(this.hdl, value)
        end

        self.set_unsafe = function (this, value)
            C.c_set_value(this.hdl, value)
        end

        self.set_index = function(this, index, value)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:set_index()", this.fullpath))
        end

        self.set_index_unsafe = function (this, index, value)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:set_index_unsafe()", this.fullpath))
        end

        -- 
        -- #define vpiBinStrVal          1
        -- #define vpiOctStrVal          2
        -- #define vpiDecStrVal          3
        -- #define vpiHexStrVal          4
        -- 
        self.get_str = function (this, fmt)
            return ffi_str(C.c_get_value_str(this.hdl, fmt))
        end

        self.get_index_str = function (this, index, fmt)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:get_str(fmt), instead using <CallableHDL>:get_index_str(index, fmt)", this.fullpath))
        end

        self.set_str = function (this, str)
            C.c_set_value_str(this.hdl, str)
        end

        self.set_index_str = function (this, index, str)
            assert(false, format("[%s] Normal handle does not support <CallableHDL>:set_index_str(index, str), instead using <CallableHDL>:set_str(str)", this.fullpath))
        end
    else
        assert(false)
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
            assert(false, format("hdl bit width == %d > 1, <chdl>:posedge() only support 1-bit hdl", this.width))
        end

        self.negedge= function(this, times)
            assert(false, format("hdl bit width == %d > 1, <chdl>:negedge() only support 1-bit hdl", this.width))
        end

        self.always_posedge = function (this)
            assert(false, format("hdl bit width == %d > 1, <chdl>:always_posedge() only support 1-bit hdl", this.width))
        end

        self.posedge_until = function (this, max_limit, func)
            assert(false, format("hdl bit width == %d > 1, <chdl>:posedge_until() only support 1-bit hdl", this.width))
        end

        self.negedge_until = function (this, max_limit, func)
            assert(false, format("hdl bit width == %d > 1, <chdl>:negedge_until() only support 1-bit hdl", this.width))
        end
    end

    if self.is_array then
        self.dump_str = function (this)
            local s = ("[%s] => "):format(this.fullpath)
            
            for i = 1, this.array_size do
                s = s .. ("(%d): 0x%s "):format(i - 1, this.get_index_str(i, HexStr))
            end
            
            return s
        end
    else
        self.dump_str = function (this)
            return ("[%s] => 0x%s"):format(this.fullpath, this:get_str(HexStr))
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
            assert(false, format("[%s] expect => %d, but got => %d", this.fullpath, value, this:get()))
        end
    end

    self.expect_not = function (this, value)
        local typ = type(value)
        assert(typ == "number" or typ == "cdata")

        if this.is_multi_beat and this.beat_num > 2 then
            assert(false, "`<CallableHDL>:expect_not(value)` can only be used for hdl with 1 or 2 beat, use `<CallableHDL>:expect_not_[hex/bin/dec]_str(value_str)` instead! beat_num => " .. this.beat_num)    
        end

        if this:get() == value then
            assert(false, format("[%s] expect not => %d, but got => %d", this.fullpath, value, this:get()))
        end
    end

    self.expect_hex_str = function(this, hex_value_str)
        assert(type(hex_value_str) == "string")
        if not compare_value_str("0x" .. this:get_str(HexStr), hex_value_str) then
            assert(false, format("[%s] expect => %s, but got => %s", this.fullpath, hex_value_str, this:get_str(HexStr)))
        end
    end

    self.expect_bin_str = function(this, bin_value_str)
        assert(type(bin_value_str) == "string")
        if not compare_value_str("0b" .. this:get_str(BinStr), bin_value_str) then
            assert(false, format("[%s] expect => %s, but got => %s", this.fullpath, bin_value_str, this:get_str(BinStr)))
        end
    end

    self.expect_dec_str = function(this, dec_value_str)
        assert(type(dec_value_str) == "string")
        if not compare_value_str(this:get_str(DecStr), dec_value_str) then
            assert(false, format("[%s] expect => %s, but got => %s", this.fullpath, dec_value_str, this:get_str(DecStr)))
        end
    end

    self.expect_not_hex_str = function(this, hex_value_str)
        assert(type(hex_value_str) == "string")
        if compare_value_str("0x" .. this:get_str(HexStr), hex_value_str) then
            assert(false, format("[%s] expect not => %s, but got => %s", this.fullpath, hex_value_str, this:get_str(HexStr)))
        end
    end

    self.expect_not_bin_str = function(this, bin_value_str)
        assert(type(bin_value_str) == "string")
        if compare_value_str("0b" .. this:get_str(BinStr), bin_value_str) then
            assert(false, format("[%s] expect not => %s, but got => %s", this.fullpath, bin_value_str, this:get_str(BinStr)))
        end
    end

    self.expect_not_dec_str = function(this, dec_value_str)
        assert(type(dec_value_str) == "string")
        if compare_value_str(this:get_str(DecStr), dec_value_str) then
            assert(false, format("[%s] expect not => %s, but got => %s", this.fullpath, dec_value_str, this:get_str(DecStr)))
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
        return compare_value_str("0x" .. this:get_str(HexStr), hex_value_str)
    end

    self.is_bin_str = function (this, bin_value_str)
        assert(type(bin_value_str) == "string")
        return compare_value_str("0b" .. this:get_str(BinStr), bin_value_str)
    end

    self.is_dec_str = function (this, dec_value_str)
        assert(type(dec_value_str) == "string")
        return compare_value_str(this:get_str(DecStr), dec_value_str)
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
            do
                C.c_get_value_multi_2(self.hdl, self.c_results, self.beat_num)
                -- _get_value_multi_8(self.hdl, self.c_results, self.beat_num)
                return self.c_results
            end
            
            -- do
            --     C.c_get_value_multi_1(self.hdl, self.c_results, self.beat_num)
                
            --     local ret = {}
            --     for i = 1, self.beat_num do
            --         table.insert(ret, self.c_results[i-1])
            --     end
                
            --     return ret
            -- end
            
            -- return vpi.get_value_multi(self.hdl, self.beat_num) -- This will return a table with multi beat datas, and each is 32-bit size data
        end
    else
        -- return ffi.C.get_value(self.hdl)
        -- return vpi.get_value(self.hdl)
        return C.c_get_value(self.hdl)
    end
end

-- You can get performance gain in this SIMD like signal value retrival functions. (about ~8% better performance)
function get_signal_value64_parallel(hdls)
    local length = #hdls
    local input_hdls = ffi_new("long long[?]", length)
    local output_values = ffi_new("uint64_t[?]", length)
    for i = 0, length-1 do
        input_hdls[i] = hdls[i+1]
    end
    
    C.c_get_value64_parallel(input_hdls, output_values, length)

    local results = {}
    for i = 0, length-1 do
        results[i+1] = tonumber(output_values[i])
    end
    
    return table.unpack(results)
end

function get_signal_value_parallel(hdls)
    local length = #hdls
    local input_hdls = ffi_new("long long[?]", length)
    local output_values = ffi_new("uint32_t[?]", length)
    for i = 0, length-1 do
        input_hdls[i] = hdls[i+1]
    end
    
    C.c_get_value_parallel(input_hdls, output_values, length)

    local results = {}
    for i = 0, length-1 do
        results[i+1] = tonumber(output_values[i])
    end
    
    return table.unpack(results)
end

-- This will not provide any performance gain instead will cause performance drop. 
-- TODO: still don't known why we can't get performance gain by reducing the interaction of C and Lua.
--       There exist some performance gaps in this functions.
function set_signal_value64_parallel(hdls, values)
    local length = #hdls
    assert(length == #values)
    
    local input_hdls = ffi_new("long long[?]", length)
    local input_values = ffi_new("uint64_t[?]", length)
    for i = 0, length-1 do
        input_hdls[i] = hdls[i+1]
        input_values[i] = values[i+1]
    end
    
    C.c_set_value64_parallel(input_hdls, input_values, length)
end

-- This will not provide any performance gain instead will cause performance drop.
function set_signal_value_parallel(hdls, values)
    local length = #hdls
    assert(length == #values)
    
    local input_hdls = ffi_new("long long[?]", length)
    local input_values = ffi_new("uint32_t[?]", length)
    for i = 0, length-1 do
        input_hdls[i] = hdls[i+1]
        input_values[i] = values[i+1]
    end
    
    C.c_set_value_parallel(input_hdls, input_values, length)
end

return CallableHDL
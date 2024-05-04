local class = require "pl.class"
local ffi = require "ffi"
local C = ffi.C

ffi.cdef[[
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
]]

CallableHDL = class()

local CallableHDL = CallableHDL
local BeatWidth = 32
local type, assert, tonumber, print = type, assert, tonumber, print
local table, math, vpi = table, math, vpi

function CallableHDL:_init(fullpath, name, hdl)
    self.verbose = false
    self.fullpath = fullpath
    self.name = name or "Unknown"

    self.hdl = hdl or vpi.handle_by_name(fullpath)
    self.width = vpi.get_signal_width(self.hdl)
    self.beat_num = math.ceil(self.width / BeatWidth)
    self.is_multi_beat = not (self.beat_num == 1)

    self.c_results = ffi.new("uint32_t[?]", self.beat_num + 1) -- create a new array to store the result
                                                               -- c_results[0] is the lenght of the beat data since a normal lua table use 1 as the first index of array while ffi cdata still use 0

    local _ = self.verbose and print("New CallableHDL => ", "name: " .. self.name, "fullpath: " .. self.fullpath, "width: " .. self.width, "beat_num: " .. self.beat_num, "is_multi_beat: " .. tostring(self.is_multi_beat))
end

function CallableHDL:__call(force_multi_beat)
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

function CallableHDL:set(value, force_single_beat)
    force_single_beat = force_single_beat or false
    if self.is_multi_beat then
        if force_single_beat and self.beat_num == 2 then
            if type(value) == "table" then
                assert(false)
            end
            C.c_set_value64(self.hdl, value)
        else
            if force_single_beat then
                if type(value) == "table" then
                    assert(false)
                end
                C.c_set_value_force_single(self.hdl, value, self.beat_num)
            else
                -- value is a table where <lsb ... msb>
                if type(value) ~= "table" then
                    assert(false, type(value) .. " =/= table \n" .. self.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua")
                end
                
                local beat_num = self.beat_num
                if #value ~= beat_num then
                    assert(false, "len: " .. #value .. " =/= " .. self.beat_num)
                end

                if beat_num == 3 then
                    C.c_set_value_multi_1_beat_3(
                        self.hdl,
                        value[1], value[2]);
                elseif beat_num == 4 then
                    C.c_set_value_multi_1_beat_4(
                        self.hdl,
                        value[1], value[2], value[3], value[4])
                elseif beat_num == 5 then
                    C.c_set_value_multi_1_beat_5(
                        self.hdl,
                        value[1], value[2], value[3], value[4],
                        value[5])
                elseif beat_num == 6 then
                    C.c_set_value_multi_1_beat_6(
                        self.hdl,
                        value[1], value[2], value[3], value[4],
                        value[5], value[6])
                elseif beat_num == 7 then
                    C.c_set_value_multi_1_beat_7(
                        self.hdl,
                        value[1], value[2], value[3], value[4],
                        value[5], value[6], value[7])
                elseif beat_num == 8 then
                    C.c_set_value_multi_1_beat_8(
                        self.hdl,
                        value[1], value[2], value[3], value[4],
                        value[5], value[6], value[7], value[8]
                    )
                else
                    do
                        for i = 1, self.beat_num do
                            self.c_results[i - 1] = value[i]
                        end
                        C.c_set_value_multi_1(self.hdl, self.c_results, self.beat_num)
                    end
                end

                -- do
                --     for i = 1, self.beat_num do
                --         self.c_results[i - 1] = value[i]
                --     end
                --     C.c_set_value_multi_1(self.hdl, self.c_results, self.beat_num)
                -- end

                -- vpi.set_value_multi(self.hdl, value)

            end
        end
    else
        C.c_set_value(self.hdl, value)
    end
end


-- 
-- Unsafe usage of CallableHDL:set()
-- Do not check value type and lenght of value table. 
-- Usually has higher performance than CallableHDL:set()
-- 
function CallableHDL:set_no_check(value, force_single_beat)
    force_single_beat = force_single_beat or false
    if self.is_multi_beat then
        if force_single_beat and self.beat_num == 2 then
            C.c_set_value64(self.hdl, value)
        else
            if force_single_beat then
                C.c_set_value_force_single(self.hdl, value, self.beat_num)
            else
                -- value is a table where <lsb ... msb>

                local beat_num = self.beat_num
                if beat_num == 3 then
                    C.c_set_value_multi_1_beat_3(
                        self.hdl,
                        value[1], value[2]);
                elseif beat_num == 4 then
                    C.c_set_value_multi_1_beat_4(
                        self.hdl,
                        value[1], value[2], value[3], value[4])
                elseif beat_num == 5 then
                    C.c_set_value_multi_1_beat_5(
                        self.hdl,
                        value[1], value[2], value[3], value[4],
                        value[5])
                elseif beat_num == 6 then
                    C.c_set_value_multi_1_beat_6(
                        self.hdl,
                        value[1], value[2], value[3], value[4],
                        value[5], value[6])
                elseif beat_num == 7 then
                    C.c_set_value_multi_1_beat_7(
                        self.hdl,
                        value[1], value[2], value[3], value[4],
                        value[5], value[6], value[7])
                elseif beat_num == 8 then
                    C.c_set_value_multi_1_beat_8(
                        self.hdl,
                        value[1], value[2], value[3], value[4],
                        value[5], value[6], value[7], value[8]
                    )
                else
                    do
                        for i = 1, self.beat_num do
                            self.c_results[i - 1] = value[i]
                        end
                        C.c_set_value_multi_1(self.hdl, self.c_results, self.beat_num)
                    end
                end

                -- do
                --     for i = 1, self.beat_num do
                --         self.c_results[i - 1] = value[i]

                --     end
                --     C.c_set_value_multi_1(self.hdl, self.c_results, self.beat_num)
                -- end

                -- do
                --     local c_value = ffi.new("uint32_t[?]", self.beat_num, value)
                --     C.c_set_value_multi_1(self.hdl, c_value, self.beat_num)
                -- end

                -- vpi.set_value_multi(self.hdl, value)
            end
        end
    else
        C.c_set_value(self.hdl, value)
    end
end

-- You can get performance gain in this SIMD like signal value retrival functions. (about ~8% better performance)
function get_signal_value64_parallel(hdls)
    local length = #hdls
    local input_hdls = ffi.new("long long[?]", length)
    local output_values = ffi.new("uint64_t[?]", length)
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
    local input_hdls = ffi.new("long long[?]", length)
    local output_values = ffi.new("uint32_t[?]", length)
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
    
    local input_hdls = ffi.new("long long[?]", length)
    local input_values = ffi.new("uint64_t[?]", length)
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
    
    local input_hdls = ffi.new("long long[?]", length)
    local input_values = ffi.new("uint32_t[?]", length)
    for i = 0, length-1 do
        input_hdls[i] = hdls[i+1]
        input_values[i] = values[i+1]
    end
    
    C.c_set_value_parallel(input_hdls, input_values, length)
end
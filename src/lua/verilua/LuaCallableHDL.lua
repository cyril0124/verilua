local class = require("pl.class")
local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
  long long c_get_signal_value(const char *path);
  void c_set_value(long long handle, uint32_t value);
  void c_set_value64(long long handle, uint64_t value);
  void c_set_value_force_single(long long handle, uint32_t value, uint32_t size);
  uint32_t c_get_value(long long handle);
  uint64_t c_get_value64(long long handle);
  unsigned int c_get_signal_width(long long handle);
  void c_get_value_parallel(long long *hdls, uint32_t *values, int length);
  void c_get_value64_parallel(long long *hdls, uint64_t *values, int length);
  void c_set_value_parallel(long long *hdls, uint32_t *values, int length);
  void c_set_value64_parallel(long long *hdls, uint64_t *values, int length);
  void c_get_value_multi_1(long long handle, int n, uint32_t *c_results);
]]


CallableHDL = class()

local BeatWidth = 32

-- TODO: Optimize multi beat logic
function CallableHDL:_init(fullpath, name, hdl)
    self.verbose = false
    self.fullpath = fullpath
    self.name = name or "Unknown"

    self.hdl = hdl or vpi.handle_by_name(fullpath)
    self.width = vpi.get_signal_width(self.hdl)
    self.beat_num = math.ceil(self.width / BeatWidth)
    self.is_multi_beat = not (self.beat_num == 1)

    self.c_results = ffi.new("uint32_t[?]", self.beat_num) -- create a new array to store the result

    local _ = self.verbose and print("New CallableHDL => ", "name: " .. self.name, "fullpath: " .. self.fullpath, "width: " .. self.width, "beat_num: " .. self.beat_num, "is_multi_beat: " .. tostring(self.is_multi_beat))
end

function CallableHDL:__call(force_multi_beat)
    force_multi_beat = force_multi_beat or false
    -- print("and "..tostring(force_multi_beat))
    if self.is_multi_beat then
        if self.beat_num <= 2 and not force_multi_beat then
            return tonumber(C.c_get_value64(self.hdl))
        else
            C.c_get_value_multi_1(self.hdl, self.beat_num, self.c_results)
            
            local ret = {}
            for i = 1, self.beat_num do
                table.insert(ret, self.c_results[i-1])
            end
            
            return ret
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
    if self.is_multi_beat and not force_single_beat then
        -- value is a table where <lsb ... msb>
        if type(value) ~= "table" then
            assert(false, type(value) .. " =/= table \n" .. self.name .. " is a multibeat hdl, <value> should be a multibeat value which is represented as a <table> in verilua")
        end

        if #value ~= self.beat_num then
            assert(false, "len: " .. #value .. " =/= " .. self.beat_num)
        end
        
        vpi.set_value_multi(self.hdl, value)
    else
        if type(value) == "table" then
            assert(false, self.fullpath .. " type is " .. type(value))
        end
        
        if force_single_beat == true then
            C.c_set_value_force_single(self.hdl, value, self.beat_num)
        else
            if self.beat_num <= 2 then
                C.c_set_value64(self.hdl, value)
            else
                C.c_set_value(self.hdl, value)
            end
        end
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
local class = require("pl.class")
local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
  long long get_signal_value(const char *path);
  void set_value(long long handle, long long value);
  unsigned int get_value(long long handle);
  unsigned int get_signal_width(long long handle);
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

    local _ = self.verbose and print("New CallableHDL => ", "name: " .. self.name, "fullpath: " .. self.fullpath, "width: " .. self.width, "beat_num: " .. self.beat_num, "is_multi_beat: " .. tostring(self.is_multi_beat))
end

function CallableHDL:__call()
    if self.is_multi_beat then
        return vpi.get_value_multi(self.hdl, self.beat_num) -- This will return a table with multi beat datas, and each is 32-bit size data
    else
        -- return ffi.C.get_value(self.hdl)
        return C.get_value(self.hdl)
        -- return vpi.get_value(self.hdl)
    end
end

function CallableHDL:set(value, force_single_beat)
    force_single_beat = force_single_beat or false
    if self.is_multi_beat and not force_single_beat then
        assert(#value == self.beat_num, "len: " .. #value .. " =/= " .. self.beat_num)
        vpi.set_value_multi(self.hdl, value)
    else
        assert(type(value) ~= "table", self.fullpath .. " type is " .. type(value))
        -- vpi.set_value(self.hdl, value)
        -- ffi.C.set_value(self.hdl, value)
        C.set_value(self.hdl, value)
    end
end


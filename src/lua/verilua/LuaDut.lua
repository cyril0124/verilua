require "LuaSchedulerCommon"
local CallableHDL = require "LuaCallableHDL"
local stringx = require "pl.stringx"
local ffi = require "ffi"

local C = ffi.C
local await_posedge = await_posedge
local await_negedge = await_negedge
local assert, type, tonumber, setmetatable = assert, type, tonumber, setmetatable
local sfind, ssub, format = string.find, string.sub, string.format

ffi.cdef[[
    long long c_handle_by_name(const char* name);
    void c_set_value_by_name(const char *path, uint32_t value);
    uint64_t c_get_value_by_name(const char *path);
    void c_force_value_by_name(const char *path, long long value);
    void c_release_value_by_name(const char *path);
]]

local top_with_dot = cfg.top .. "."
local dot_set_len = #(".set")
local dot_set_force_len = #(".set_force")
local dot_set_release_len = #(".set_release")

local function create_proxy(path)
    local local_path = path
    return setmetatable({
        -- 
        -- Example:
        --      local alias_signal = dut.path.to.signal
        --      alias_signal:set(123)        -- set value into 123, Notice: you cannot use alias_signal since Lua will treat this as a variable reassignment
        --      alias_signal:set "123"
        --      alias_signal:set("0x123")
        --      alias_signal:set("0b1111")
        --      local value = alias_signal() -- read value 
        -- 
        set = function (t, v)
            assert(v ~= nil)
            C.c_set_value_by_name(local_path, tonumber(v))
        end,

        -- 
        -- Example:
        --      local cycles = dut.cycles
        --      cycles:set_force(0)
        --      ...
        --      cycles:set_release()
        --      
        --      dut.path.to.cycles:set_force(123)
        --      ...
        --      dut.path.to.cycles:set_release()
        -- 
        set_force = function (t, v)
            assert(v ~= nil)
            C.c_force_value_by_name(local_path, tonumber(v))
        end,
        set_release = function (t)
            C.c_release_value_by_name(local_path)
        end,

        -- 
        -- Example:
        --      local value = dut.cycles:get()
        -- 
        get = function (t)
            return tonumber(C.c_get_value_by_name(local_path))
        end,

        -- 
        -- Example:
        --      local hex_str = dut.cycles:get_hex()
        --      assert(hex_str == "0x123")
        -- 
        get_hex = function (t)
            return format("0x%x", tonumber(C.c_get_value_by_name(local_path)))
        end,

        -- 
        -- Example:
        --      dut.clock:posedge()
        --      dut.reset:negedge()
        --      dut.path.to.some.signal:posedge()
        -- 
        posedge = function(t, v)
            local _v = v or 1
            local _v_type = type(_v)

            assert(_v_type == "number")
            assert(_v >= 1)

            for i = 1, _v do
                await_posedge(local_path)
            end
        end,
        negedge = function(t, v)
            local _v = v or 1
            local _v_type = type(_v)

            assert(_v_type == "number")
            assert(_v >= 1)

            for i = 1, _v do
                await_negedge(local_path)
            end
        end,

        -- 
        -- Example: 
        --      local hdl = dut.cycles:hdl()
        -- 
        hdl = function (t)
            local hdl = ffi.C.c_handle_by_name_safe(local_path)
            if hdl == -1 then
                assert(false, format("No handle found => %s", local_path))
            end
            return hdl
        end,

        -- 
        -- Example:
        --      local cycles_chdl = dut.cycles:chdl()
        --      print("value of cycles is " .. cycles_chdl:get())
        --      cycles_chdl:set(123)
        -- 
        chdl = function (t)
            return CallableHDL(local_path, "")
        end,

        -- 
        -- Example:
        --      local path = dut.path.to.signal:name()
        --      assert(path == "tb_top.path.to.signal")
        -- 
        name = function (t)
           return local_path 
        end,

    }, {
        __index = function(t, k)
            return create_proxy(local_path .. '.' .. k)
        end,

        __newindex = function(t, k, v)
            local fullpath = local_path .. '.' .. k
            -- print('assign ' .. v .. ' to ' .. fullpath .. "  " .. local_path) -- debug info
            C.c_set_value_by_name(fullpath, v)
        end,

        __call = function(t, v)
            local data_type = v or "integer"
            if data_type == "integer" then
                return tonumber(C.c_get_value_by_name(local_path))
            elseif data_type == "hex" then
                local val = C.c_get_value_by_name(local_path)
                return string.format("0x%x", val)
            elseif data_type == "name" then
                return local_path
            elseif data_type == "hdl" then
                return C.c_handle_by_name(local_path)
            else
                assert(false, "invalid data type: " .. data_type)
            end
        end,

        __tostring = function ()
            return local_path
        end
    })
end


return {
    create_proxy = create_proxy
}
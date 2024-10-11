local CallableHDL = require "LuaCallableHDL"
local utils = require "LuaUtils"
local stringx = require "pl.stringx"
local ffi = require "ffi"

local C = ffi.C
local ffi_str = ffi.string

local BeatWidth = 32
local HexStr = HexStr
local BinStr = BinStr
local DecStr = DecStr
local compare_value_str = utils.compare_value_str
local await_posedge = await_posedge
local await_negedge = await_negedge
local assert, type, tonumber, setmetatable = assert, type, tonumber, setmetatable
local tinsert = table.insert
local format = string.format

ffi.cdef[[
    long long c_handle_by_name(const char* name);
    void c_set_value_by_name(const char *path, uint64_t value);
    uint64_t c_get_value_by_name(const char *path);
    void c_force_value_by_name(const char *path, long long value);
    void c_release_value_by_name(const char *path);
    void c_set_value_str_by_name(const char *path, const char *str);
    void c_force_value_str_by_name(const char *path, const char *str);
    const char *c_get_value_str(long long handle, int format);
    unsigned int c_get_signal_width(long long handle);
]]

local set_force_enable = false
local force_path_table = {}

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
            if set_force_enable then
                tinsert(force_path_table, local_path)
                C.c_force_value_by_name(local_path, tonumber(v))
            else
                C.c_set_value_by_name(local_path, tonumber(v))
            end
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
            if set_force_enable then
                tinsert(force_path_table, local_path)
            end
            C.c_force_value_by_name(local_path, tonumber(v))
        end,
        set_release = function (t)
            C.c_release_value_by_name(local_path)
        end,

        -- 
        -- Example:
        --      dut:force_all()
        --          dut.cycles:set(1)
        --          dut.path.to.signal:set(1)
        --      
        --      dut.clock:posedge()
        --      dut:release_all()
        -- 
        force_all = function (t)
            assert(set_force_enable == false)
            set_force_enable = true
        end,
        release_all = function(t)
            assert(set_force_enable == true)
            set_force_enable = false

            for i, path in ipairs(force_path_table) do
                C.c_release_value_by_name(path)
            end
        end,

        -- 
        -- Normal value assign operations inside this region will all be treat as force operation.
        -- This method can automatically release all the forced signals hence you are free from calling dut:release_all() manually.
        --
        -- Example:
        --      dut:force_region(function()
        --          dut.clock:negedge()
        --          dut.cycles:set(1)
        --      end)
        -- 
        force_region = function(t, code_func)
            assert(type(code_func) == "function")
            t:force_all()
            code_func()
            t:release_all()
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
        --      local bin_str = dut.cycles:get_str(BinStr)
        --      local dec_str = dut.cycles:get_str(DecStr)
        --      local hex_str = dut.cycles:get_str(HexStr)
        -- 
        get_str = function (t, fmt)
            local hdl = C.c_handle_by_name_safe(local_path)
            if hdl == -1 then
                assert(false, format("No handle found => %s", local_path))
            end
            return ffi_str(C.c_get_value_str(hdl, fmt))
        end,


        -- 
        -- Example:
        --      dut.cycles:set_str("0x123")
        --      dut.cycles:set_str("0b101010")
        -- 
        set_str = function(t, str)
            if set_force_enable then
                tinsert(force_path_table, local_path)
                C.c_force_value_str_by_name(local_path, str)
            else
                C.c_set_value_str_by_name(local_path, str)
            end
        end,
        set_force_str = function(t, str)
            C.c_force_value_str_by_name(local_path, str)
        end,

        -- 
        -- Example:
        --      dut.clock:posedge()
        --      dut.reset:negedge()
        --      dut.path.to.some.signal:posedge()
        --      dut.clock:posedge(10)
        --      dut.clock:posedge(10, function (c)
        --         print("current count is " .. c)
        --      end)
        -- 
        posedge = function(t, v, func)
            local _v = v or 1
            local _v_type = type(_v)

            assert(_v_type == "number")
            assert(_v >= 1)

            local do_func = false
            if func ~= nil then
                assert(type(func) == "function") 
                do_func = true 
            end

            for i = 1, _v do
                if do_func then
                    func(i)
                end
                await_posedge(local_path)
            end
        end,
        negedge = function(t, v, func)
            local _v = v or 1
            local _v_type = type(_v)

            assert(_v_type == "number")
            assert(_v >= 1)

            local do_func = false
            if func ~= nil then
                assert(type(func) == "function") 
                do_func = true 
            end

            for i = 1, _v do
                if do_func then
                    func(i)
                end
                await_negedge(local_path)
            end
        end,

        -- 
        -- Example:
        --      local condition_meet = dut.clock:posedge_until(100, function func()
        --          return dut.cycles() >= 100
        --      end)
        -- 
        posedge_until = function (t, max_limit, func)
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
                    await_posedge(local_path)
                else
                    break
                end
            end

            return condition_meet
        end,
        negedge_until = function (t, max_limit, func)
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
                    await_negedge(local_path)
                else
                    break 
                end
            end

            return condition_meet
        end,

        -- 
        -- Example: 
        --      local hdl = dut.cycles:hdl()
        -- 
        hdl = function (t)
            local hdl = C.c_handle_by_name_safe(local_path)
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

        -- 
        -- Example:
        --      local width = dut.cycles:get_width()
        --      assert(width == 64)
        -- 
        get_width = function (t)
            return tonumber(C.c_get_signal_width(C.c_handle_by_name(local_path)))
        end,

        dump_str = function (t)
            local hdl = C.c_handle_by_name(local_path)
            local s = ("[%s] => "):format(local_path)
            s = s .. "0x" .. ffi_str(C.c_get_value_str(hdl, HexStr))
            return s
        end,

        -- 
        -- Example: 
        --      dut.path.to.signal:dump()
        --          => [tb_top.path.to.signal] => 0x1234
        -- 
        dump = function(t)
            print(t:dump_str())
        end,

        -- 
        -- Example:
        --      dut.paht.to.signal:expect(1) -- signal value should be 1 otherwise there will be a assert false
        -- 
        expect = function(t, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")

            local beat_num = t:get_width() / BeatWidth
            if beat_num > 2 then
                assert(false, "`dut.<path>:expect(value)` can only be used for hdl with 1 or 2 beat, use `dut.<path>:expect_[hex/bin/dec]_str(value_str)` instead! beat_num => " .. beat_num)    
            end
            
            if t:get() ~= value then
                assert(false, format("[%s] expect => %d, but got => %d", local_path, value, t:get()))
            end
        end,

        expect_not = function(t, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")

            local beat_num = t:get_width() / BeatWidth
            if beat_num > 2 then
                assert(false, "`dut.<path>:expect_not(value)` can only be used for hdl with 1 or 2 beat, use `dut.<path>:expect_not_[hex/bin/dec]_str(value_str)` instead! beat_num => " .. beat_num)    
            end
            
            if t:get() == value then
                assert(false, format("[%s] expect not => %d, but got => %d", local_path, value, t:get()))
            end
        end,

        -- 
        -- Example:
        --      dut.path.to.signal:expect_hex_str("0x1234") -- signal value should be 0x1234 otherwise there will be a assert false
        --      dut.path.to.signal.expect_bin_str("0b1111")
        --      dut.path.to.signal.expect_dec_str("1234")
        -- 
        expect_hex_str = function(this, hex_value_str)
            assert(type(hex_value_str) == "string")
            if not compare_value_str( "0x" .. this:get_str(HexStr), hex_value_str) then
                assert(false, format("[%s] expect => %s, but got => %s", local_path, hex_value_str, this:get_str(HexStr)))
            end
        end,
    
        expect_bin_str = function(this, bin_value_str)
            assert(type(bin_value_str) == "string")
            if not compare_value_str( "0b" .. this:get_str(BinStr), bin_value_str) then
                assert(false, format("[%s] expect => %s, but got => %s", local_path, bin_value_str, this:get_str(BinStr)))
            end
        end,
    
        expect_dec_str = function(this, dec_value_str)
            assert(type(dec_value_str) == "string")
            if not compare_value_str(this:get_str(DecStr), dec_value_str) then
                assert(false, format("[%s] expect => %s, but got => %s", local_path, dec_value_str, this:get_str(DecStr)))
            end
        end,

        expect_not_hex_str = function(this, hex_value_str)
            assert(type(hex_value_str) == "string")
            if compare_value_str( "0x" .. this:get_str(HexStr), hex_value_str) then
                assert(false, format("[%s] expect not => %s, but got => %s", local_path, hex_value_str, this:get_str(HexStr)))
            end
        end,
    
        expect_not_bin_str = function(this, bin_value_str)
            assert(type(bin_value_str) == "string")
            if compare_value_str( "0b" .. this:get_str(BinStr), bin_value_str) then
                assert(false, format("[%s] expect not => %s, but got => %s", local_path, bin_value_str, this:get_str(BinStr)))
            end
        end,
    
        expect_not_dec_str = function(this, dec_value_str)
            assert(type(dec_value_str) == "string")
            if compare_value_str(this:get_str(DecStr), dec_value_str) then
                assert(false, format("[%s] expect not => %s, but got => %s", local_path, dec_value_str, this:get_str(DecStr)))
            end
        end,

        -- 
        -- Example:
        --      dut.path.to.signal:_if(some_condition == true):expect(1)
        --
        --                 or
        --
        --      dut.path.to.signal:_if(function() return some_condition == true end):expect(1)
        --
        --              equals to 
        --
        --      if some_condition == true then
        --          dut.path.to.signal:expect(1) 
        --      end
        --  
        _if = function (t, condition)
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
                return t
            else
                return setmetatable({}, {
                    __index = function(t, k)
                        return function ()
                            -- an empty function
                        end
                    end
                })
            end
        end,

        -- 
        -- Example:
        --      assert(dut.path.to.signal:is(1))
        --      assert(dut.another_signal:is_not(1))
        --      
        --      You can also combine this with "_if":
        --          dut.path.to.signal:_if(dut.signal:is(1)):expect(123)
        -- 
        is = function (t, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")

            return t:get() == value
        end,
        is_not = function (t, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")

            return t:get() ~= value
        end,

        -- 
        -- Example:
        --      assert(dut.path.to.signal:is_hex_str("0x1"))
        --      assert(dut.another_signal:is_bin_str("0b101"))
        --      assert(dut.another_signal:is_dec_str("1"))
        --      
        --      You can also combine this with "_if":
        --          dut.path.to.signal:_if(dut.signal:is_hex_str("0x1")):expect(123)
        --
        is_hex_str = function(t, hex_value_str)
            return compare_value_str( "0x" .. t:get_str(HexStr), hex_value_str)
        end,

        is_bin_str = function(t, bin_value_str)
            return compare_value_str( "0b" .. t:get_str(BinStr), bin_value_str)
        end,

        is_dec_str = function(t, dec_value_str)
            return compare_value_str(t:get_str(DecStr), dec_value_str)
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
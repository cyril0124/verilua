local ffi = require "ffi"
local stringx = require "pl.stringx"
local assert, type, tonumber = assert, type, tonumber
local sfind, ssub = string.find, string.sub

ffi.cdef[[
    long long c_handle_by_name(const char* name);
    void c_set_value_by_name(const char *path, uint64_t value);
    uint64_t c_get_value_by_name(const char *path);
]]

local top_with_dot = cfg.top .. "."

local function create_proxy(path)
    local local_path = path
    return setmetatable({}, {
        __index = function(t, k)
            return create_proxy(local_path .. '.' .. k)
        end,

        __newindex = function(t, k, v)
            local fullpath = local_path .. '.' .. k
            -- print('assign ' .. v .. ' to ' .. fullpath .. "  " .. local_path) -- debug info
            ffi.C.c_set_value_by_name(fullpath, v)
        end,

        __call = function(t, v)
            -- print( "get " .. local_path) -- debug info
            local v_type = type(v)
            if v_type == "number" or (v_type == "string" and v ~= "name") then -- assign value
                if type(t.path) == "table" then
                    -- 
                    -- local alias_signal = dut.path.to.signal
                    -- alias_signal.set(123)        -- set value into 123, Notice: you cannot use alias_signal since Lua will treat this as a variable reassignment
                    --       or
                    -- alias_signal.set "123"
                    -- local value = alias_signal() -- read value 
                    -- 
                    if stringx.endswith(local_path, ".set") then
                        local value
                        do
                            if v_type == "string" then
                                if stringx.startswith(v, "0x") then
                                    value = tonumber(v, 16)
                                elseif stringx.startswith(v, "0b") then
                                    value = tonumber(v, 2)
                                else
                                    value = tonumber(v) 
                                end
                            else
                                value = v
                            end
                        end
                        ffi.C.c_set_value_by_name(ssub(local_path, 1, #local_path - 4), tonumber(v))
                    else
                        assert(false, "Unhandled condition")
                    end
                else
                    -- vpi.set_value_by_name(cfg.top .. "." .. t.path, tonumber(v))
                    ffi.C.c_set_value64_by_name(top_with_dot .. t.path, tonumber(v))
                end
                return
            else -- read signal value
                local data_type = v or "integer"
                if data_type == "integer" then
                    return ffi.C.c_get_value_by_name(local_path)
                elseif data_type == "hex" then
                    local val = ffi.C.c_get_value_by_name(local_path)
                    return string.format("0x%x", val)
                elseif data_type == "name" then
                    return local_path
                elseif data_type == "hdl" then
                    return ffi.C.c_handle_by_name(local_path)
                else
                    assert(false, "invalid data type: " .. data_type)
                end
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
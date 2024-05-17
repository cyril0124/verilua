local ffi = require "ffi"
local C = ffi.C
local stringx = require "pl.stringx"
local assert, type, tonumber = assert, type, tonumber
local sfind, ssub = string.find, string.sub

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
    return setmetatable({}, {
        __index = function(t, k)
            return create_proxy(local_path .. '.' .. k)
        end,

        __newindex = function(t, k, v)
            local fullpath = local_path .. '.' .. k
            -- print('assign ' .. v .. ' to ' .. fullpath .. "  " .. local_path) -- debug info
            C.c_set_value_by_name(fullpath, v)
        end,

        __call = function(t, v)
            -- print( "get " .. local_path) -- debug info
            local v_type = type(v)
            if v_type == "number" or (v_type == "string" and v ~= "name") then -- assign value
                if type(t.path) == "table" then
                    -- 
                    -- Example:
                    --      local alias_signal = dut.path.to.signal
                    --      alias_signal.set(123)        -- set value into 123, Notice: you cannot use alias_signal since Lua will treat this as a variable reassignment
                    --      alias_signal.set "123"
                    --      alias_signal.set("0x123")
                    --      alias_signal.set("0b1111")
                    --      local value = alias_signal() -- read value 
                    -- 
                    if stringx.endswith(local_path, ".set") then
                        C.c_set_value_by_name(local_path:sub(1, #local_path - dot_set_len), tonumber(v))

                    -- 
                    -- Example:
                    --      local cycles = dut.cycles
                    --      cycles.set_force(0)
                    --      ...
                    --      cycles.set_release()
                    --      
                    --      dut.path.to.cycles.set_force(123)
                    --      ...
                    --      dut.path.to.cycles.set_release()
                    -- 
                    elseif stringx.endswith(local_path, ".set_force") then
                        C.c_force_value_by_name(local_path:sub(1, #local_path - dot_set_force_len), tonumber(v))
                    else
                        local data_type = v or "integer"
                        if data_type == "integer" then
                            if stringx.endswith(local_path, ".set_release") then
                                C.c_release_value_by_name(local_path:sub(1, #local_path - dot_set_release_len))
                            else
                                return tonumber(C.c_get_value_by_name(local_path))
                            end
                        elseif data_type == "hex" then
                            local val = C.c_get_value_by_name(local_path)
                            return string.format("0x%x", val)
                        elseif data_type == "name" then
                            return local_path
                        elseif data_type == "hdl" then
                            return C.c_handle_by_name(local_path)
                        else
                            assert(false, "Unhandled condition => " .. local_path .. " v => " .. v)
                        end
                    end
                else
                    -- vpi.set_value_by_name(cfg.top .. "." .. t.path, tonumber(v))
                    C.c_set_value64_by_name(top_with_dot .. t.path, tonumber(v))
                end
                return
            else -- read signal value
                local data_type = v or "integer"
                if data_type == "integer" then
                    if stringx.endswith(local_path, ".set_release") then
                        C.c_release_value_by_name(local_path:sub(1, #local_path - dot_set_release_len))
                    else
                        return tonumber(C.c_get_value_by_name(local_path))
                    end
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
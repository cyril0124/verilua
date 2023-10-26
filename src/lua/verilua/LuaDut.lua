require("LuaSimConfig")
local VERILUA_CFG, VERILUA_CFG_PATH = LuaSimConfig.get_cfg()
local cfg = require(VERILUA_CFG)

require("LuaScheduler")


function create_proxy(path)
    local local_path = path
    return setmetatable({}, {
        __index = function(t, k)
            return create_proxy(local_path .. '.' .. k)
        end,

        __newindex = function(t, k, v)
            local fullpath = local_path .. '.' .. k
            -- print('assign ' .. v .. ' to ' .. fullpath .. "  " .. local_path) -- debug info
            
            vpi.write_signal(fullpath, v)
        end,

        __call = function(t, v)
            -- print( "get " .. local_path) -- debug info

            if type(v) == "number" then -- assign value
                vpi.write_signal(cfg.top .. "." .. t.path, v)
                return
            else -- read signal value
                data_type = v or "integer"
                if data_type == "integer" then
                    return vpi.read_signal(local_path)
                elseif data_type == "hex" then
                    val = vpi.read_signal(local_path)
                    return string.format("0x%x", val)
                elseif data_type == "name" then
                    return local_path
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


function dut_get_signal_value(path)
    return vpi.read_signal(self.top_path .. "." .. path)
end


function dut_set_signal_value(path, value)
    vpi.write_signal(self.top_path .. "." .. path, value)
end


-- local dut = create_proxy('Top')
local dut = create_proxy('tb_top')


return dut
_G.package.path = package.path .. ";" .. os.getenv("VERILUA_HOME") .. "/src/lua/thirdparty_lib/?.lua"

local sb = require "string.buffer"
local inspect = require "inspect"
-- local table_new = require "table.new"

-- local pp = function(...) print(inspect(...)) end

---@type verilua.utils.SignalDB.data
local signal_db_table = {}

---@param signal_db_file string
function _G.print_signal_db(signal_db_file)
    local file = io.open(signal_db_file, "r")
    local signal_db_data = {}
    if file then
        local data = file:read("*a")
        file:close()
        signal_db_data = sb.decode(data) --[[@as table]]
    else
        error("[signal_db_gen] [decode] Failed to open 'signala_db.ldb'")
    end

    print(inspect(signal_db_data))
end

---@param out_file string
function _G.encode_signal_db(out_file)
    local encoded_table = sb.encode(signal_db_table)
    local file = io.open(out_file, "w")
    if file then
        file:write(encoded_table)
        file:close()
    else
        error("[encode] Failed to open " .. out_file)
    end
end

---@param size integer
---@param hier_path_vec table<integer, string>
---@param bitwidth_vec table<integer, integer>
---@param vpi_type_str_vec table<integer, string>
function _G.insert_signal_db(size, hier_path_vec, bitwidth_vec, vpi_type_str_vec)
    for i = 1, size do
        ---@type string[]
        local hier_path = {}
        for part in string.gmatch(hier_path_vec[i], "[^.]+") do
            hier_path[#hier_path + 1] = part
        end

        local curr = signal_db_table
        local end_idx = #hier_path
        for j, v in ipairs(hier_path) do
            -- final signal name
            if j == end_idx then
                -- `v` is the signal name
                ---@type verilua.utils.SignalInfo
                local signal_info = {
                    v,
                    bitwidth_vec[i],
                    vpi_type_str_vec[i],
                }
                curr[#curr + 1] = signal_info
            else
                -- intermediate signal hierarchy path
                -- `v` is the instance name
                if not curr[v] then
                    curr[v] = {}
                end
                curr = curr[v]
            end
        end
    end
end

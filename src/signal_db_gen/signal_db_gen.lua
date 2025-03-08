_G.package.path = package.path .. ";" .. os.getenv("VERILUA_HOME") .. "/src/lua/thirdparty_lib/?.lua"

local sb = require "string.buffer"
local inspect = require "inspect"
local table_new = require "table.new"

local pp = function(...) print(inspect(...)) end
local signal_db_table = {}

function _G.print_signal_db(signal_db_file)
    local file = io.open(signal_db_file, "r")
    local signal_db_data = {}
    if file then
        local data = file:read("*a")
        file:close()
        signal_db_data = sb.decode(data)
    else
        error("[signal_db_gen] [decode] Failed to open 'signala_db.ldb'")
    end

    print(inspect(signal_db_data))
end

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

local function type_str_to_vpi_type(type_str, hier_path)
    if type_str:match("^logic") or type_str:match("^bit") then
        return "vpiNet"
    elseif type_str:match("^reg") then
        return "vpiReg"
    else
        error("Unsupported type: " .. type_str .. " at <" .. hier_path .. ">")
    end
end

function _G.insert_signal_db(size, hier_path_vec, bitwidth_vec, type_str_vec)
    for i = 1, size do
        local hier_path = {}
        for part in string.gmatch(hier_path_vec[i], "[^.]+") do
            table.insert(hier_path, part)
        end
        local curr = signal_db_table
        local end_idx = #hier_path

        for j, v in ipairs(hier_path) do
            -- final signal name
            if j == end_idx then
                -- `v` is the signal name
                table.insert(curr, {v, bitwidth_vec[i], type_str_to_vpi_type(type_str_vec[i], hier_path_vec[i])})
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
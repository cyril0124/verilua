local ffi = require "ffi"
local utils = {}
local this = utils

local bit, io, math, string, os = bit, io, math, string, os
local tostring, tonumber, ipairs, type, pairs, assert, print = tostring, tonumber, ipairs, type, pairs, assert, print
local tconcat = table.concat
local tohex = bit.tohex


-- 
-- t: table, values to be serialized
-- conn: char / str, connector for the serialization
-- 
function utils.serialize(t, conn)
    local serialized = t
    local conn = conn or "_"
    -- for k, v in pairs(t) do
    --     table.insert(serialized, tostring(k) .. "=" .. tostring(v))
    -- end
    -- table.sort(serialized)
    return tconcat(serialized, conn)
end

function utils.reverse_table(tab)
    local size = #tab
    local new_tab = {}

    for i, v in ipairs(tab) do
        new_tab[size - i + 1] = v
    end

    return new_tab
end

-- 
-- reverse == true(Default)
--     MSB <=> LSB
-- reverse == falase
--     LSB <=> MSB
-- 
function utils.to_hex_str(t, reverse)
    reverse = reverse or true

    if type(t) ~= "table" then
        return tohex(t)
    end

    local t_copy = {}
    for i = 1, #t do
        t_copy[i] = tohex(t[i])
    end

    if reverse then
        local i, n = 1, #t
        while i < n do
            t_copy[i], t_copy[n] = t_copy[n], t_copy[i]
            i, n = i + 1, n - 1
        end
    end

    return tconcat(t_copy, " ")
end

function utils.log2Ceil(n)
    if n < 1 then
        return 0
    else
        local log_val = math.log(n) / math.log(2)
        local ceil_val = math.ceil(log_val)
        return ceil_val
    end
end

function utils.bitfield32(begin, endd, val)
    return bit.rshift( bit.lshift(val, 32 - endd), begin + 32- endd )
end

function utils.bitfield64(begin, endd, val)
    local val64 = ffi.new('uint64_t', val)
    return bit.rshift( bit.lshift(val64, 64 - endd), begin + 64- endd )
end

-- 
-- Merge hi(32-bit) and lo(32-bit) into a 64-bit result
-- 
function utils.to64bit(hi, lo)
    return bit.lshift(hi, 32) + lo
end

-- 
-- LSB <==> MSB
-- 
function utils.to_hex(hex_table)
    local ret = ""
    if type(hex_table) == "table" then
        for index, value in ipairs(hex_table) do
            ret = ret .. string.format("%x ", value)
        end
    else
        ret = ret .. string.format("%x", hex_table)
    end
    return ret
end

function utils.print_hex(hex_table)
    io.write(this.to_hex(hex_table).."\n")
end

function utils.num_to_binstr(num)
    local num = tonumber(num)
    if num == 0 then return "0" end
    local binstr = ""
    while num > 0 do
        local bit = num % 2
        binstr = tostring(bit) .. binstr
        num = math.floor(num / 2)
    end
    return binstr
end

-- 
-- progress: float value, range from (0, 1)
-- length: int value, length of the progress bar
-- 
function utils.get_progress_bar(progress, length)
    -- https://cn.piliapp.com/symbol/
    local completed = math.floor(progress * length)
    local remaining = length - completed
    local progressBar = "┃" .. string.rep("█", completed) .. "▉" .. string.rep(" ", remaining) .. "┃"
    return progressBar
end

function utils.print_progress_bar(progress, length)
    print(utils.get_progress_bar(progress, length))
end


-- 
-- Usage Example:
--   Direction = setmetatable({
--       name = "Direction",
--       INPUT = 0,
--       OUTPUT = 1
--   }, { __call = utils.enum_search })
-- 
function utils.enum_search(t, v)
    for name, value in pairs(t) do
        if value == v then
            return name
        end
    end
    assert(false, "Key no found: " .. v .. " in " .. t.name)
end

-- 
-- format: <Year><Month><Day>_<Hour><Minute>
-- Example:
--   local str = utils.get_datetime_str()
--         str == "20240124_2301" 
-- 
function utils.get_datetime_str()
    local datetime = os.date("%Y%m%d_%H%M")
    return datetime
end


local path = require "pl.path"
function utils.abspath(...)
    return path.abspath(...)
end


function utils.read_file_str(filename)
    local file = io.open(utils.abspath(filename), "r") 
    if not file then
        assert(false, "cannot open " .. utils.abspath(filename))
    end
    local content = file:read("*a")
    file:close()
    return content
end


return utils
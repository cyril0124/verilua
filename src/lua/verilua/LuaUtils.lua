local utils = {}
local this = utils
local concat = table.concat
local tohex = bit.tohex

function utils.serialize(t, conn)
    local serialized = t
    local conn = conn or "_"
    -- for k, v in pairs(t) do
    --     table.insert(serialized, tostring(k) .. "=" .. tostring(v))
    -- end
    -- table.sort(serialized)
    return table.concat(serialized, conn)
end

function utils.reverse_table(tab)
    local size = #tab
    local new_tab = {}

    for i, v in ipairs(tab) do
        new_tab[size - i + 1] = v
    end

    return new_tab
end


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

    return concat(t_copy, " ")
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

-- Merge hi(32-bit) and lo(32-bit) into a 64-bit result
function utils.to64bit(hi, lo)
    return bit.lshift(hi, 32) + lo
end

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


return utils
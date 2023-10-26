local tablex = require("pl.tablex")
local utils = {}

ANSI_COLOR_RED     = "\27[31m"
ANSI_COLOR_GREEN   = "\27[32m"
ANSI_COLOR_YELLOW  = "\27[33m"
ANSI_COLOR_BLUE    = "\27[34m"
ANSI_COLOR_MAGENTA = "\27[35m"
ANSI_COLOR_CYAN    = "\27[36m"
ANSI_COLOR_RESET   = "\27[0m"

local colors = {
    reset = "\27[0m",
    black = "\27[30m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m"
}

local colors_list = {}
for _, color in pairs(colors) do
    table.insert(colors_list, color)
end

function verilua_colorful(...)
    local background_color = "\27[47m"
    local text = table.concat({...}, " ")
    for i = 1, #text do
        local color = colors_list[math.random(#colors_list)]
        io.write(color .. background_color .. text:sub(i, i) .. "\27[0m")
    end
    io.write("\n")
end

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

function utils:to_hex_str(t, reverse)
    reverse = reverse or true

    local t = tablex.deepcopy(t)

    if type(t) ~= "table" then
        return bit.tohex(t)
        -- return string.format("%x", t)
    end

    for i, v in ipairs(t) do
        t[i] = bit.tohex(v)
        -- t[i] = string.format("%x", v)
    end

    if reverse then
        return table.concat(utils.reverse_table(t) , " ")
    else
        return table.concat(t, " ")
    end
end


function utils:log2Ceil(n)
    if n < 1 then
        return 0
    else
        local log_val = math.log(n) / math.log(2)
        local ceil_val = math.ceil(log_val)
        return ceil_val
    end
end

function utils:bitfield32(begin, endd, val)
    return bit.rshift( bit.lshift(val, 32 - endd), begin + 32- endd )
end

function verilua_info(...)
    print(colors.cyan .. os.date() .. " [VERILUA INFO]", ...)
    io.write(colors.reset)
end

function verilua_warning(...)
    print(colors.yellow .. os.date() ..  "[VERILUA WARNING]", ...)
    io.write(colors.reset)
end

function verilua_error(...)
    local error_print = function(...)
        print(colors.red .. os.date() ..  "[VERILUA ERROR]", ...)
        io.write(colors.reset)
        io.flush()
    end
    assert(false, error_print(...))
end

function verilua_assert(cond, ...)
    if cond == nil or cond == false then
        verilua_error(...)
    end
end

return utils
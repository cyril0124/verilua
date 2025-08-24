local table = _G.table

table.clear = require("table.clear")
table.new = require("table.new")

---@param ... table
---@return table
table.join = function(...)
    local result = {}
    for _, t in ipairs({ ... }) do
        if type(t) == "table" then
            for k, v in pairs(t) do
                if type(k) == "number" then
                    table.insert(result, v)
                else
                    result[k] = v
                end
            end
        else
            table.insert(result, t)
        end
    end
    return result
end

---@generic T
---@param t table<integer, T>
---@param v T
---@return boolean
table.contains = function(t, v)
    for _, _v in ipairs(t) do
        if _v == v then
            return true
        end
    end
    return false
end

-- `table.nkeys` is provided by openresty luajit2(https://github.com/openresty/luajit2)
local has_table_nkeys, table_nkeys = pcall(require, "table.nkeys")
if has_table_nkeys then
    table.nkeys = table_nkeys
else
    table.nkeys = function(t)
        local count = 0
        for _, _ in pairs(t) do
            count = count + 1
        end
        return count
    end
end

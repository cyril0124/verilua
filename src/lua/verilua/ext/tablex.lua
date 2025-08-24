-- TODO: Remove this
-- https://github.com/evo-lua/evo-runtime/blob/b101a992fdb465f571a612c091ada6a12df2407b/Runtime/Extensions/tablex.lua#L82

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

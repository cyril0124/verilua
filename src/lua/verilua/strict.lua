--
-- Copy from https://github.com/terralang/terra/tree/master/src/strict.lua with some modifications
--

--
-- strict.lua (adapted from LuaJIT-2.0.0-beta10)
-- checks uses of undeclared global variables
-- All global variables must be 'declared' through a regular assignment
-- (even assigning nil will do) in a main chunk before being used
-- anywhere or assigned to inside a function.
--

local f = string.format
local getinfo, error, rawset, rawget = debug.getinfo, error, rawset, rawget

if getmetatable(_G) ~= nil then -- if another package has already altered the global environment then don't try to install the strict module
    return
end

local mt = { strict = true }
Strict = mt
setmetatable(_G, mt)

mt.__declared = {}

local function what()
    local d = getinfo(3, "S")
    return d and d.what or "C"
end

local function what_src()
    local d = getinfo(3, "S")
    return d.source
end

local function what_line()
    local d = getinfo(3, "l")
    return d and d.currentline or 0
end

mt.__newindex = function(t, n, v)
    if not mt.__declared[n] then
        local w = what()
        if mt.strict and w ~= "main" and w ~= "C" then
            error(f(
                [[Attempting to assign to previously undeclared global variable '%s' from inside a function.
If this variable is local to the function, it needs to be tagged with the 'local' keyword.
If it is a global variable, it needs to be defined at the global scope before being used in a function.
]], tostring(n)), 2)
        end
        mt.__declared[n] = true
    end
    rawset(t, n, v)
end

mt.__index = function(t, n)
    if mt.strict and not mt.__declared[n] and what() ~= "C" then
        local source = what_src()
        -- Ignore luarocks installed library files
        if not (source:sub(1, 1) == "@" and source:find("/share/lua/5.1/") ~= nil) then
            local ANSI_RED = "\27[31m"
            local ANSI_RESET = "\27[0m"
            local err_info = "Global variable '" ..
                n ..
                "' is not declared. Global variables must be 'declared' through a regular assignment (even to nil) at global scope before being used."

            source = source:sub(2, -1) -- Remove the '@' prefix_str

            -- Print error info before calling `error` to avoid the `error` being cut off by `pcall` or `xpcall`
            print(ANSI_RED .. "[UNDEFINED GLOBAL]" .. ANSI_RESET,
                f("\n\t%s\n\tsource: %s:%d", err_info, source, what_line()))
            error(err_info, 2)
        end
    end
    return rawget(t, n)
end

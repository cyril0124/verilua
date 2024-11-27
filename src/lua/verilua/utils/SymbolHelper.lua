local ffi = require "ffi"

local C = ffi.C
local type = type
local error = error
local tonumber = tonumber
local ffi_cast = ffi.cast
local ffi_string = ffi.string

ffi.cdef[[
    char *get_executable_name(void);
    uint64_t get_symbol_address(const char *filename, const char *symbol);
]]

local get_executable_name = function()
    return ffi_string(C.get_executable_name())
end

local get_global_symbol_addr = function(symbol_name)
    local executable_name = get_executable_name()
    return tonumber(C.get_symbol_address(executable_name, symbol_name))
end

local ffi_cast = function (type_str, value)
    if type(value) == "number" then
        return ffi_cast(type_str, ffi.cast("const char*", value))
    elseif type(value) == "string" then
        local symbol_addr = get_global_symbol_addr(value)
        return ffi_cast(type_str, symbol_addr)
    elseif type(value) == "cdata" then
        return ffi_cast(type_str, value)
    else
        error("[SymbolHelper] Unsupported type for ffi_cast: " .. type(value))
    end
end

--
-- `SymbolHelper` is provided by Verilua to get the global symbol address of the C function.
-- The C function is defined for DPI-C usage or as a normal C function in the testbench code. 
-- And this is a tricky way to call the C function from Lua instead of from the testbench(SystemVerilog). 
-- Although this way is not recommended, it is still a way to call the C function from Lua 
-- if you don't want to call it from SystemVerilog.
-- 
-- Example:
--      local symbol_helper = require "verilua.utils.SymbolHelper"
--      local path = symbol_helper.get_executable_name()
--      local addr = symbol_helper.get_global_symbol_addr("some_function")
--      printf("addr => 0x%x\n", addr)
--      local some_function = symbol_helper.ffi_cast("char (*)()", "some_function")
--      local a = some_function()
--      assert(false, path)
-- 

return {
    get_executable_name = get_executable_name,
    get_global_symbol_addr = get_global_symbol_addr,
    ffi_cast = ffi_cast,
}
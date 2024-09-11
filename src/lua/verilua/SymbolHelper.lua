local ffi = require "ffi"

local tonumber = tonumber
local C = ffi.C
local ffi_string = ffi.string
local ffi_cast = ffi.cast

ffi.cdef[[
    char *get_executable_name(void);
    uint64_t get_symbol_address(const char *filename, const char *symbol);
]]

local function get_executable_name()
    return ffi_string(C.get_executable_name())
end

local function get_global_symbol_addr(symbol_name)
    local executable_name = get_executable_name()
    return tonumber(C.get_symbol_address(executable_name, symbol_name))
end

local function _ffi_cast(type_str, value)
    if type(value) == "number" then
        return ffi_cast(type_str, ffi.cast("const char*", value))
    elseif type(value) == "string" then
        local symbol_addr = get_global_symbol_addr(value)
        return ffi_cast(type_str, symbol_addr)
    elseif type(value) == "cdata" then
        return ffi_cast(type_str, value)
    else
        error("Unsupported type for ffi_cast: " .. type(value))
    end
end

-- Example:
--      local symbol_helper = require "SymbolHelper"
--      local path = symbol_helper.get_executable_name()
--      local addr = symbol_helper.get_global_symbol_addr("some_function")
--      printf("addr => 0x%x\n", addr)
--      local some_function = symbol_helper.ffi_cast("char (*)()", "some_function")
--      local a = some_function()
--      assert(false, path)

return {
    get_executable_name = get_executable_name,
    get_global_symbol_addr = get_global_symbol_addr,
    ffi_cast = _ffi_cast,
}
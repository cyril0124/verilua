local ffi = require "ffi"

local C = ffi.C
local type = type
local error = error
local ffi_cast = ffi.cast
local ffi_string = ffi.string

ffi.cdef [[
    char *get_executable_name(void);
    char *get_self_cmdline(void);
    uint64_t get_symbol_address(const char *filename, const char *symbol);
]]

local get_executable_name = function()
    return ffi_string(C.get_executable_name())
end

local get_self_cmdline = function()
    return ffi_string(C.get_self_cmdline())
end

local executable_name = nil
local get_global_symbol_addr = function(symbol_name)
    if not executable_name then
        executable_name = get_executable_name()
    end
    return C.get_symbol_address(executable_name, symbol_name)
end

local ffi_cast = function(type_str, value)
    if type(value) == "number" then
        return ffi_cast(type_str, ffi.cast("const char*", value))
    elseif type(value) == "string" then
        -- Get symbol address and cast it to the type_str according to the symbol name(value)
        local symbol_addr = get_global_symbol_addr(value)
        if symbol_addr == 0 then
            assert(false, "[SymbolHelper] Symbol not found: " .. value)
        end

        return ffi_cast(type_str, symbol_addr)
    elseif type(value) == "cdata" then
        return ffi_cast(type_str, value)
    else
        error("[SymbolHelper] Unsupported type for ffi_cast: " .. type(value))
    end
end

--- `SymbolHelper` is provided by Verilua to get the global symbol address of the C function.
--- The C function is defined for DPI-C usage or as a normal C function in the testbench code.
--- And this is a tricky way to call the C function from Lua instead of from the testbench(SystemVerilog).
--- Although this way is not recommended, it is still a way to call the C function from Lua
--- if you don't want to call it from SystemVerilog.
---
--- e.g.
--- ```lua
---      local symbol_helper = require "verilua.utils.SymbolHelper"
---      local path = symbol_helper.get_executable_name()
---      local addr = symbol_helper.get_global_symbol_addr("some_function")
---      printf("addr => 0x%x\n", addr)
---      local some_function = symbol_helper.ffi_cast("char (*)()", "some_function")
---      local a = some_function()
---      assert(false, path)
--- ```
---

--- Attempts to get a function pointer through FFI cast or declaration.
--- First tries to find the symbol in the global symbol table and cast it.
--- If not found, falls back to FFI declaration.
---@nodiscard Return value should not be discarded
---@param func_ptr_str string The function pointer type string, e.g. "void (*)(const char*)"
---@param ffi_func_decl_str string The FFI function declaration string, e.g. "void my_func(const char*);"
---@param func_name string The function name to search for, e.g. "my_func"
---@return function The function pointer
local try_ffi_cast = function(func_ptr_str, ffi_func_decl_str, func_name)
    if get_global_symbol_addr(func_name) ~= 0 then
        return ffi_cast(func_ptr_str, func_name) --[[@as function]]
    else
        ffi.cdef(ffi_func_decl_str)
        assert(ffi.C[func_name], "[SymbolHelper.try_ffi_cast] Failed to get symbol: " .. ffi_func_decl_str)
        return ffi.C[func_name]
    end
end

---@class (exact) verilua.utils.SymbolHelper
---@field get_executable_name fun(): string
---@field get_self_cmdline fun(): string
---@field get_global_symbol_addr fun(symbol_name: string): integer
---@field ffi_cast fun(type_str: ffi.ct*, value: string|integer|ffi.cdata*): ffi.cdata*
---@field try_ffi_cast fun(func_ptr_str: string, ffi_func_decl_str: string, func_name: string): function
local SymbolHelper = {
    get_executable_name = get_executable_name,
    get_self_cmdline = get_self_cmdline,
    get_global_symbol_addr = get_global_symbol_addr,
    ffi_cast = ffi_cast,
    try_ffi_cast = try_ffi_cast,
}

return SymbolHelper

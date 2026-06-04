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

--- Parse a full C function declaration into its symbol name and the matching
--- function-pointer type string.
---
--- Examples:
---   "void *svSetScope(void *scope);" -> name="svSetScope",
---                                       ptr_type="void *(*)(void *scope)"
---   "uint64_t f();"                  -> name="f", ptr_type="uint64_t (*)()"
---
--- The pointer type is built by replacing the function name with `(*)`.
--- Parameter names are kept verbatim because LuaJIT's `ffi.typeof` /
--- `ffi.cast` tolerate parameter names in function-pointer type strings.
---
--- Errors loudly when the input cannot be parsed as a C function declaration
--- (no silent fallback). Heuristic: the function name is the last identifier
--- immediately before the first `(`. This handles every declaration shape
--- currently used in the Verilua codebase.
---@param decl string Full C function declaration, e.g. "void foo(int x);"
---@return string func_name
---@return string func_ptr_str
local _parse_func_decl = function(decl)
    if type(decl) ~= "string" then
        error("[SymbolHelper._parse_func_decl] decl must be a string, got " .. type(decl))
    end

    -- Capture: <rettype-ending-in-space-or-*><name>(<params>) with optional
    -- trailing `;`. The `[%s%*]` anchor guarantees there is a real return
    -- type before the name and rejects pure pointer-type strings such as
    -- "void (*)()" (which have no identifier before the first `(`).
    local rettype, name, params = decl:match("^%s*(.-[%s%*])([%a_][%w_]*)%s*%((.*)%)%s*;?%s*$")
    if not name then
        error("[SymbolHelper._parse_func_decl] cannot parse C function declaration: " .. decl)
    end

    local ptr_type = rettype .. "(*)(" .. params .. ")"
    return name, ptr_type
end

--- Attempts to get a function pointer through FFI cast or declaration.
--- First tries to find the symbol in the global symbol table and cast it.
--- If not found, falls back to FFI declaration.
---
--- Two call forms are supported:
---
--- 1. Minimal form: pass only the full C declaration. The function name and
---    function-pointer type are derived from the declaration. Recommended
---    for new code because the declaration already names the function.
---
---    ```lua
---    local f = SymbolHelper.try_ffi_cast("void *svSetScope(void *scope);")
---    ```
---
--- 2. Legacy 3-arg form: pass the function-pointer type, the FFI declaration
---    and the symbol name explicitly. Kept for backward compatibility.
---
---    ```lua
---    local f = SymbolHelper.try_ffi_cast(
---        "void *(*)(void *)",
---        "void *svSetScope(void *scope);",
---        "svSetScope"
---    )
---    ```
---@nodiscard Return value should not be discarded
---@param func_ptr_str string Function-pointer type, e.g. "void (*)(const char*)"
---@param ffi_func_decl_str string FFI declaration, e.g. "void my_func(const char*);"
---@param func_name string Symbol name to search for, e.g. "my_func"
---@return function The function pointer
---@overload fun(decl: string): function
local try_ffi_cast = function(func_ptr_str, ffi_func_decl_str, func_name)
    -- Minimal form: a single argument carrying the full C declaration.
    -- Detected by arity (args 2 and 3 are nil). String content is *not* used
    -- to disambiguate, because legacy `func_ptr_str` like "void (*)(int)" is
    -- not reliably distinguishable from a decl by inspection alone.
    if ffi_func_decl_str == nil and func_name == nil then
        local decl = func_ptr_str
        local name, ptr_type = _parse_func_decl(decl)
        ffi_func_decl_str = decl
        func_name = name
        func_ptr_str = ptr_type
    else
        assert(
            type(func_ptr_str) == "string"
            and type(ffi_func_decl_str) == "string"
            and type(func_name) == "string",
            "[SymbolHelper.try_ffi_cast] expected 1 decl arg, or 3 string args (func_ptr_str, ffi_func_decl_str, func_name)"
        )
    end

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
---@field try_ffi_cast fun(func_ptr_str_or_decl: string, ffi_func_decl_str?: string, func_name?: string): function
---@field _parse_func_decl fun(decl: string): string, string
local SymbolHelper = {
    get_executable_name = get_executable_name,
    get_self_cmdline = get_self_cmdline,
    get_global_symbol_addr = get_global_symbol_addr,
    ffi_cast = ffi_cast,
    try_ffi_cast = try_ffi_cast,
    -- Exposed primarily for unit testing of the parser; safe to call but not
    -- part of the documented public API.
    _parse_func_decl = _parse_func_decl,
}

return SymbolHelper

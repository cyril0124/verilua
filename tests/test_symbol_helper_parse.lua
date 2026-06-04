---@diagnostic disable: unnecessary-assert

local lester = require "lester"
local SymbolHelper = require "verilua.utils.SymbolHelper"

local describe, it = lester.describe, lester.it
local assert = assert

-- This unit test focuses on the pure logic that derives `func_ptr_str` and
-- `func_name` from a full C function declaration string. The integration
-- behavior (ELF lookup + ffi.cdef fallback) is exercised in
-- `tests/test_symbol_helper`.
local parse_func_decl = SymbolHelper._parse_func_decl
assert(parse_func_decl, "SymbolHelper._parse_func_decl is not exposed")

describe("SymbolHelper.parse_func_decl", function()
    it("parses simple void no-arg decl", function()
        local name, ptr_type = parse_func_decl("void foo();")
        assert(name == "foo", name)
        assert(ptr_type == "void (*)()", ptr_type)
    end)

    it("parses pointer-return type", function()
        local name, ptr_type = parse_func_decl("void *svSetScope(void *scope);")
        assert(name == "svSetScope", name)
        -- Param names are kept; LuaJIT's ffi.typeof tolerates them.
        assert(ptr_type == "void *(*)(void *scope)", ptr_type)
    end)

    it("parses const pointer-return type", function()
        local name, ptr_type = parse_func_decl("const char *get_name(int id);")
        assert(name == "get_name", name)
        assert(ptr_type == "const char *(*)(int id)", ptr_type)
    end)

    it("parses multi-arg with names", function()
        local name, ptr_type = parse_func_decl(
            "void wave_vpi_ctrl_set_jit_options(const char* opt_name, uint64_t value);"
        )
        assert(name == "wave_vpi_ctrl_set_jit_options", name)
        assert(ptr_type == "void (*)(const char* opt_name, uint64_t value)", ptr_type)
    end)

    it("works without trailing semicolon", function()
        local name, ptr_type = parse_func_decl("uint64_t f(uint32_t x)")
        assert(name == "f", name)
        assert(ptr_type == "uint64_t (*)(uint32_t x)", ptr_type)
    end)

    it("tolerates leading and trailing whitespace", function()
        local name, ptr_type = parse_func_decl("   bool dpi_exporter_sensitive_trigger();   ")
        assert(name == "dpi_exporter_sensitive_trigger", name)
        assert(ptr_type == "bool (*)()", ptr_type)
    end)

    it("handles unsigned multi-token return types", function()
        local name, ptr_type = parse_func_decl("unsigned int counter_get(unsigned int id);")
        assert(name == "counter_get", name)
        assert(ptr_type == "unsigned int (*)(unsigned int id)", ptr_type)
    end)

    it("rejects strings that are not full decls", function()
        -- A bare pointer-type string is NOT a valid decl; the parser must fail
        -- loudly so callers get a clear error instead of a silent miscast.
        local ok, err = pcall(parse_func_decl, "void (*)()")
        assert(not ok, "parser must fail on a function-pointer type string")
        assert(tostring(err):find("SymbolHelper"), err)
    end)

    it("rejects empty / nonsense strings", function()
        local ok = pcall(parse_func_decl, "")
        assert(not ok)
        local ok2 = pcall(parse_func_decl, "not a c declaration")
        assert(not ok2)
    end)
end)

-- Note: end-to-end coverage of `try_ffi_cast` (both minimal and legacy
-- forms) lives in `tests/test_symbol_helper/main.lua`, which runs inside a
-- real simulator that has the Verilua C runtime linked in. This file stays
-- focused on the pure parser logic so it can run under plain luajit.

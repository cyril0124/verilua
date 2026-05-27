local ffi = require "ffi"
local SymbolHelper = require "verilua.utils.SymbolHelper"

-- Build the external .so at runtime (not linked into simulator)
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
assert(script_dir, "cannot determine script directory")
local build_ext_dir = script_dir .. "build_ext"
local ext_so = build_ext_dir .. "/libext.so"
os.execute("mkdir -p " .. build_ext_dir)
local compile_rc = os.execute(string.format("gcc -shared -fPIC -o %s %s", ext_so, script_dir .. "ext_lib.c"))
assert(compile_rc == true or compile_rc == 0, "Failed to compile ext_lib.c")

fork {
    function()
        print("=== SymbolHelper Test ===")

        -- 1. get_global_symbol_addr: finds DPI-C symbols linked into the simulator binary
        local addr_add = SymbolHelper.get_global_symbol_addr("sym_add")
        assert(addr_add ~= 0, "FAIL: sym_add should be in main ELF")
        print("[PASS] get_global_symbol_addr finds linked DPI-C symbol (sym_add)")

        local addr_mul = SymbolHelper.get_global_symbol_addr("sym_mul")
        assert(addr_mul ~= 0, "FAIL: sym_mul should be in main ELF")
        assert(addr_add ~= addr_mul, "FAIL: sym_add and sym_mul should have different addresses")
        print("[PASS] get_global_symbol_addr finds multiple symbols with distinct addresses")

        -- 2. get_global_symbol_addr: returns 0 for nonexistent symbols
        local addr_fake = SymbolHelper.get_global_symbol_addr("__nonexistent_xyz__")
        assert(addr_fake == 0, "FAIL: nonexistent symbol should return 0")
        print("[PASS] get_global_symbol_addr returns 0 for nonexistent symbol")

        -- 3. ffi_cast: cast linked symbol to callable function pointer
        local sym_add = SymbolHelper.ffi_cast("int (*)(int, int)", "sym_add")
        assert(sym_add(17, 25) == 42, "FAIL: sym_add(17,25) should be 42")
        print("[PASS] ffi_cast: call DPI-C function sym_add(17,25) = 42")

        local sym_mul = SymbolHelper.ffi_cast("int (*)(int, int)", "sym_mul")
        assert(sym_mul(6, 7) == 42, "FAIL: sym_mul(6,7) should be 42")
        print("[PASS] ffi_cast: call DPI-C function sym_mul(6,7) = 42")

        -- 4. ffi_cast: errors on missing symbol
        local ok, err = pcall(function()
            SymbolHelper.ffi_cast("void (*)()", "__nonexistent_func__")
        end)
        assert(not ok, "FAIL: ffi_cast should error on missing symbol")
        assert(tostring(err):find("Symbol not found"), "FAIL: error should mention 'Symbol not found'")
        print("[PASS] ffi_cast errors on missing symbol")

        -- 5. try_ffi_cast: resolves linked symbol via ELF path
        local add2 = SymbolHelper.try_ffi_cast(
            "int (*)(int, int)",
            "int sym_add(int a, int b);",
            "sym_add"
        )
        assert(add2(100, 200) == 300, "FAIL: try_ffi_cast sym_add(100,200) should be 300")
        print("[PASS] try_ffi_cast resolves linked symbol via ELF path")

        -- 6. try_ffi_cast: call SV-exported function
        sim.set_dpi_scope("tb_top.u_top")
        local sv_square = SymbolHelper.try_ffi_cast(
            "int (*)(int)",
            "int sv_square(int x);",
            "sv_square"
        )
        assert(sv_square(7) == 49, "FAIL: sv_square(7) should be 49")
        print("[PASS] try_ffi_cast: call SV-exported function sv_square(7) = 49")

        -- 7. ffi.cdef is required before calling via handle
        local ext_lib_no_cdef = ffi.load(ext_so)
        local ok3, err3 = pcall(function()
            return ext_lib_no_cdef.ext_undeclared_func(1)
        end)
        assert(not ok3, "FAIL: accessing undeclared symbol should error")
        assert(tostring(err3):find("ext_undeclared_func"), "FAIL: error should mention the symbol name")
        print("[PASS] ffi.load handle errors without ffi.cdef (ext_undeclared_func)")

        -- After cdef, the same handle works
        ffi.cdef [[ int32_t ext_undeclared_func(int32_t x); ]]
        assert(ext_lib_no_cdef.ext_undeclared_func(7) == 21, "FAIL: ext_undeclared_func(7) should be 21")
        print("[PASS] ffi.load handle works after ffi.cdef (ext_undeclared_func)")

        -- 8. get_global_symbol_addr: cannot find symbols from ffi.load .so
        ffi.cdef [[ int32_t ext_only_func(int32_t x); ]]
        local ext_lib = ffi.load(ext_so)
        -- Verify the .so itself works via handle
        assert(ext_lib.ext_only_func(5) == 1005, "FAIL: ext_only_func(5) should be 1005")

        local addr_ext = SymbolHelper.get_global_symbol_addr("ext_only_func")
        assert(addr_ext == 0, "FAIL: ext_only_func should NOT be found in main ELF")
        print("[PASS] get_global_symbol_addr returns 0 for ffi.load (RTLD_LOCAL) symbol")

        -- 9. try_ffi_cast: fails for RTLD_LOCAL .so symbol
        local ok2, _ = pcall(function()
            SymbolHelper.try_ffi_cast(
                "int32_t (*)(int32_t)",
                "int32_t ext_only_func(int32_t x);",
                "ext_only_func"
            )
        end)
        assert(not ok2, "FAIL: try_ffi_cast should fail for RTLD_LOCAL symbol")
        print("[PASS] try_ffi_cast fails for RTLD_LOCAL-only .so symbol")

        -- 10. ffi.load with RTLD_GLOBAL makes symbol visible to try_ffi_cast fallback
        local ext_lib_global = ffi.load(ext_so, true)
        local ext_func = SymbolHelper.try_ffi_cast(
            "int32_t (*)(int32_t)",
            "int32_t ext_only_func(int32_t x);",
            "ext_only_func"
        )
        assert(ext_func(42) == 1042, "FAIL: ext_only_func(42) should be 1042")
        print("[PASS] try_ffi_cast succeeds for RTLD_GLOBAL .so symbol via ffi.C fallback")

        -- But get_global_symbol_addr still returns 0 (ELF-only)
        local addr_ext2 = SymbolHelper.get_global_symbol_addr("ext_only_func")
        assert(addr_ext2 == 0, "FAIL: RTLD_GLOBAL does not affect ELF lookup")
        print("[PASS] get_global_symbol_addr still returns 0 even after RTLD_GLOBAL load")

        -- 11. get_executable_name / get_self_cmdline
        local exe = SymbolHelper.get_executable_name()
        assert(#exe > 0, "FAIL: get_executable_name should return non-empty string")
        print("[PASS] get_executable_name: " .. exe)

        local cmdline = SymbolHelper.get_self_cmdline()
        assert(#cmdline > 0, "FAIL: get_self_cmdline should return non-empty string")
        print("[PASS] get_self_cmdline: " .. cmdline)

        _ = ext_lib
        _ = ext_lib_global

        print("=== All SymbolHelper tests passed ===")

        -- Cleanup
        os.execute("rm -rf " .. build_ext_dir)

        sim.finish()
    end
}

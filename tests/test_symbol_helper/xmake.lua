---@diagnostic disable

local sim = os.getenv("SIM") or "verilator"

target("top", function()
    add_rules("verilua")
    set_default(false)

    on_config(function(target)
        if sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
        end
    end)

    if sim == "verilator" then
        add_ldflags("-u sym_add", "-u sym_mul", "-u sv_square")
    end

    add_files("top.sv")
    add_files("dpic.cpp")

    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "./main.lua")
end)

target("test", function()
    set_kind("phony")
    set_default(true)

    on_build(function(target)
        -- Do nothing
    end)

    on_run(function()
        if sim ~= "vcs" and sim ~= "xcelium" and sim ~= "verilator" then
            return
        end

        os.exec("xmake b -P . top")
        local ret = os.iorun("xmake r -P . top")

        local function find_and_check(content)
            if not ret:find(content, 1, true) then
                raise("test failed, not found <%s>, output:\n%s", content, ret)
            end
        end

        find_and_check("[PASS] get_global_symbol_addr finds linked DPI-C symbol (sym_add)")
        find_and_check("[PASS] get_global_symbol_addr finds multiple symbols with distinct addresses")
        find_and_check("[PASS] get_global_symbol_addr returns 0 for nonexistent symbol")
        find_and_check("[PASS] ffi_cast: call DPI-C function sym_add(17,25) = 42")
        find_and_check("[PASS] ffi_cast: call DPI-C function sym_mul(6,7) = 42")
        find_and_check("[PASS] ffi_cast errors on missing symbol")
        find_and_check("[PASS] try_ffi_cast resolves linked symbol via ELF path")
        find_and_check("[PASS] try_ffi_cast: call SV-exported function sv_square(7) = 49")
        find_and_check("[PASS] ffi.load handle errors without ffi.cdef (ext_undeclared_func)")
        find_and_check("[PASS] ffi.load handle works after ffi.cdef (ext_undeclared_func)")
        find_and_check("[PASS] get_global_symbol_addr returns 0 for ffi.load (RTLD_LOCAL) symbol")
        find_and_check("[PASS] try_ffi_cast fails for RTLD_LOCAL-only .so symbol")
        find_and_check("[PASS] try_ffi_cast succeeds for RTLD_GLOBAL .so symbol via ffi.C fallback")
        find_and_check("[PASS] get_global_symbol_addr still returns 0 even after RTLD_GLOBAL load")
        find_and_check("All SymbolHelper tests passed")

        print(ret)
    end)
end)

fork {
    function()
        local SymbolHelper = require "verilua.utils.SymbolHelper"

        -- Call C function from verilua side
        local dpic_func = SymbolHelper.try_ffi_cast("void (*)(const char *)", "void dpic_func(const char *content)",
            "dpic_func")
        dpic_func("1111")

        local dpic_func2 = SymbolHelper.try_ffi_cast("void (*)(const char *)", "void dpic_func2(const char *content)",
            "dpic_func2")
        dpic_func2("2222")

        -- Call SV function from verilua side
        local sv_func = SymbolHelper.try_ffi_cast("void (*)(const char *)", "void sv_func(const char *content)",
            "sv_func")
        sim.set_dpi_scope("tb_top.u_top") -- set scope to call SV function [Required]
        sv_func("3333")

        await_rd()
        sim.finish()
    end
}

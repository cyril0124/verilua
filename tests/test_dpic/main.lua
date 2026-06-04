fork {
    function()
        local SymbolHelper = require "verilua.utils.SymbolHelper"

        -- Call C function from verilua side
        -- Legacy 3-arg form (kept here to keep covering backward compatibility).
        local dpic_func = SymbolHelper.try_ffi_cast("void (*)(const char *)", "void dpic_func(const char *content)",
            "dpic_func")
        dpic_func("1111")

        -- Minimal decl-only form: function name and pointer type are derived from the decl.
        local dpic_func2 = SymbolHelper.try_ffi_cast("void dpic_func2(const char *content);")
        dpic_func2("2222")

        -- Call SV function from verilua side (minimal form).
        local sv_func = SymbolHelper.try_ffi_cast("void sv_func(const char *content);")
        sim.set_dpi_scope("tb_top.u_top") -- set scope to call SV function [Required]
        sv_func("3333")

        await_rd()
        sim.finish()
    end
}

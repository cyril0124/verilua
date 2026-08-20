-- dpi_exporter config for the vl-verilator-dpi mem_direct test: export only
-- the clock; everything else stays un-exported and is reached via mem_direct.
add_pattern {
    module = "tb_top",
    signals = "clk"
}

-- meta_only group: reg16 gets static meta (width/type) but no DPI accessor or
-- tick sampling; dpi_exporter pins it via the generated dpi_exporter.public.vlt
-- (public_flat_rd) and its value is accessed through mem_direct.
add_pattern {
    name = "meta_only_grp",
    module = "top",
    signals = "reg16",
    meta_only = true
}

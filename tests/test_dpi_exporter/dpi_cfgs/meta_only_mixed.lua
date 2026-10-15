-- meta_only group mixed with a normal group: meta_only signals must not appear
-- in tick sampling or DPI accessors; they are registered in the meta table
-- (metaOnly = true) and pinned via the generated dpi_exporter.public.vlt.
add_pattern {
    name = "o_signals",
    module = "B",
    signals = "(o_.*)|(.*valid1)"
}

add_pattern {
    name = "a_meta_only",
    module = "A",
    signals = "(i_value_.*)|(test)",
    meta_only = true
}

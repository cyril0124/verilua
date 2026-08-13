-- clock must be exported: dummy_vpi handle_by_name only resolves exported signals.
add_pattern {
    name = "tb",
    module = "tb_top",
    signals = "clock",
}

add_pattern {
    name = "export",
    module = "top",
    signals = "count|valid|wide64|wide128",
}

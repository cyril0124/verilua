-- Export read signals; clock/reset stay on VPI for edge/drive.
add_pattern {
    name = "export",
    module = "top",
    signals = "count|valid|wide64|wide128",
}

-- meta_only: meta registered, no DPI accessor/tick sampling; value access
-- falls back to the real VPI handle in this (non-dummy_vpi) flow.
add_pattern {
    name = "export_meta_only",
    module = "top",
    signals = "meta16",
    meta_only = true,
}

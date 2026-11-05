-- meta_only group coexisting with a sensitive group: the sensitive group keeps
-- its own fully-sampled dpi_exporter_tick_<name>, while the DEFAULT tick
-- (holding only meta_only signals here) degenerates to a no-arg call.
add_pattern {
    name = "i_signals",
    module = "B",
    sensitive_signals = ".*valid",
    signals = "(i_.*)|(.*valid)"
}

add_pattern {
    name = "a_meta_only",
    module = "A",
    signals = "(i_value_.*)|(test)",
    meta_only = true
}

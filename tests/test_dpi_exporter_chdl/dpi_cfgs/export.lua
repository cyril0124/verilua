-- Export read signals; clock/reset stay on VPI for edge/drive.
add_pattern {
    name = "export",
    module = "top",
    signals = "count|valid|wide64|wide128",
}

add_pattern {
    signals = ".*",
    module = "top"
}

add_pattern {
    signals = ".*",
    writable_signals = "value",
    module = "empty",
}

add_pattern {
    writable_signals = "valid",
    module = "empty",
}

add_pattern {
    signals = ".*",
    writable_signals = "value.*",
    module = "empty2",
}
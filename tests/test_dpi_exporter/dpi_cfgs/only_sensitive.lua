add_pattern {
    name = "o_signals",
    module = "B",
    sensitive_signals = ".*valid1",
    signals = "(o_.*)|(.*valid1)"
}

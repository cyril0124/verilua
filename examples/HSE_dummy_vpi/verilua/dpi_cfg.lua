add_pattern {
    module = "Another",
    signals = ".*",
}

add_pattern {
    module = "Top",
    signals = "(clock|count.*)",
}

add_pattern {
    module = "Sub",
    signals = "(value.*|signal)",
}

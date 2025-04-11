dpi_exporter_config = {
    {
        module = "Another",
    },

    {
        module = "Top",
        clock = "clock",
        signals = {"clock", "count.*"}
    },

    {
        module = "Sub",
        signals = { "value.*", "signal" },
    },
}
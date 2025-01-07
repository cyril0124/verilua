dpi_exporter_config = {
    {
        module = "Another",
    },

    {
        module = "Top",
        clock = "clock",
        signal = {"clock", "count.*"}
    },
    
    {
        module = "Sub",
        signal = { "value.*", "signal" },
    },
}
dpi_exporter_config = {
    {
        module = "top",
        signals = {
            "clock",
            "cycles",
            "accumulator",
            "acc_valid",
            "acc_value"
        }
    },

    {
        module = "empty",
        signals = {
            "clock",
            "cycles",
            "accumulator"
        },
        writable_signals = {
            "valid",
            "value"
        }
    }
}
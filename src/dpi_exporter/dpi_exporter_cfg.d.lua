---@class regex_pattern: string A string that represents a regular expression pattern used for signal matching

---@class (exact) dpi_exporter_config.module_cfg
---@field module string The name of the module
---@field is_top_module? boolean Whether this module is the top-level module (optional)
---@field signals? table<regex_pattern> Patterns for signals to export (optional)
---@field writable_signals? table<regex_pattern> Patterns for writable signals (optional)
---@field disable_signal? table<regex_pattern> Patterns for signals to disable (optional)

---@class (exact) dpi_exporter_config
---@field clock? string Name of the clock signal
---@field [number] dpi_exporter_config.module_cfg Configuration for a specific module in the DPI exporter
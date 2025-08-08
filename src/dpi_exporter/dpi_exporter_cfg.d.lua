---@diagnostic disable: lowercase-global

---@class dpi_exporter.regex_pattern: string A string that represents a regular expression pattern used for signal matching

---@class (exact) dpi_exporter.concise_signal_pattern
---@field name? string
---@field clock? string
---@field module string
---@field signals? dpi_exporter.regex_pattern
---@field writable_signals? dpi_exporter.regex_pattern
---@field disable_signals? dpi_exporter.regex_pattern
---@field sensitive_signals? dpi_exporter.regex_pattern

---@class (exact) dpi_exporter.sensitive_trigger_params
---@field name string name of the sensitive trigger
---@field group_names string[]

---@param params dpi_exporter.concise_signal_pattern
---@return string name of the added pattern
function add_pattern(params) return "" end

-- Alias name for `add_pattern`
---@param params dpi_exporter.concise_signal_pattern
---@return string name of the added pattern
function add_signals(params) return "" end

---@param params dpi_exporter.sensitive_trigger_params
function add_senstive_trigger(params) end

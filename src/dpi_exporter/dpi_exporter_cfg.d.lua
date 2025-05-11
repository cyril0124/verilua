---@diagnostic disable: lowercase-global

---@class regex_pattern: string A string that represents a regular expression pattern used for signal matching

---@class (exact) concise_signal_pattern
---@field name? string
---@field clock? string
---@field module string
---@field signals? regex_pattern
---@field writable_signals? regex_pattern
---@field disable_signals? regex_pattern
---@field sensitive_signals? regex_pattern

---@param params concise_signal_pattern
function add_pattern(params) end
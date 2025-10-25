local SymbolHelper = require "SymbolHelper"

assert(cfg.simulator == "wave_vpi", "WaveVpiCtrl.lua can only be used with the wave_vpi simulator")

local function try_ffi_cast(type_str, type_str_ffi, value)
    if SymbolHelper.get_global_symbol_addr(value) ~= 0 then
        return SymbolHelper.ffi_cast(type_str, value)
    else
        ffi.cdef(type_str_ffi)
        assert(ffi.C[value], "[WaveVpiCtrl] Failed to get symbol: " .. type_str_ffi)
        return ffi.C[value]
    end
end

---@alias verilua.WaveVpiJitOptionNames
--- | "enable"
--- | "verbose"
--- | "max_opt_threads"
--- | "hot_access_threshold"
--- | "compile_window_size"
--- | "recompile_window_size"

---@class (exact) verilua.WaveVpiJitOptions
---@field set fun(self: verilua.WaveVpiJitOptions, opt_name: verilua.WaveVpiJitOptionNames, value: integer|boolean)
---@field get fun(self: verilua.WaveVpiJitOptions, opt_name: verilua.WaveVpiJitOptionNames): integer|boolean
---@field protected set_jit_options_cfunc? fun(opt_name: string, value: integer)
---@field protected get_jit_options_cfunc? fun(opt_name: string): integer

---@class (exact) verilua.WaveVpiCtrl
--- WaveVpiCtrl is a singleton class that provides control over the wave_vpi simulator, which is used by verilua to simulate waveform file.
---
---@field get_max_cursor_index fun(self: verilua.WaveVpiCtrl): integer
---@field set_cursor_index fun(self: verilua.WaveVpiCtrl, index: integer)
---@field jit_options verilua.WaveVpiJitOptions
---@field to_end fun(self: verilua.WaveVpiCtrl) Move the cursor to the end of the waveform file .
---@field to_percent fun(self: verilua.WaveVpiCtrl, percent: number) Move the cursor to the specified percent of the waveform file .
---@field protected get_max_cursor_index_cfunc fun(): integer
---@field protected set_cursor_index_cfunc fun(index: integer)
---@field protected set_cursor_index_percent_cfunc fun(percent: number)
local WaveVpiCtrl = {
    jit_options = {
        set = function(self, opt_name, value)
            if not self.set_jit_options_cfunc then
                self.set_jit_options_cfunc = try_ffi_cast(
                    "void (*)(const char*, uint64_t)",
                    "void wave_vpi_ctrl_set_jit_options(const char* opt_name, uint64_t value);",
                    "wave_vpi_ctrl_set_jit_options"
                ) --[[@as fun(opt_name: string, value: integer)]]
            end

            local v_type = type(value)
            if opt_name == "enable" then
                assert(v_type == "boolean", "`enable` must be a boolean")
                self.set_jit_options_cfunc(opt_name, value and 1 or 0)
            elseif opt_name == "verbose" then
                assert(v_type == "boolean", "`verbose` must be a boolean")
                self.set_jit_options_cfunc(opt_name, value and 1 or 0)
            elseif opt_name == "max_opt_threads" then
                assert(v_type == "number", "`max_opt_threads` must be a number")
                self.set_jit_options_cfunc(opt_name, value)
            elseif opt_name == "hot_access_threshold" then
                assert(v_type == "number", "`hot_access_threshold` must be a number")
                self.set_jit_options_cfunc(opt_name, value)
            elseif opt_name == "compile_window_size" then
                assert(v_type == "number", "`compile_window_size` must be a number")
                self.set_jit_options_cfunc(opt_name, value)
            elseif opt_name == "recompile_window_size" then
                assert(v_type == "number", "`recompile_window_size` must be a number")
                self.set_jit_options_cfunc(opt_name, value)
            else
                error("Unknown jit option: " .. opt_name)
            end
        end,

        get = function(self, opt_name)
            if not self.get_jit_options_cfunc then
                local get_jit_options_cfunc = try_ffi_cast(
                    "uint64_t (*)(const char*)",
                    "uint64_t wave_vpi_ctrl_get_jit_options(const char* opt_name);",
                    "wave_vpi_ctrl_get_jit_options"
                ) --[[@as fun(opt_name: string): integer]]

                self.get_jit_options_cfunc = get_jit_options_cfunc
            end

            local v
            if opt_name == "enable" or opt_name == "verbose" then
                v = self.get_jit_options_cfunc(opt_name) == 1
            else
                v = self.get_jit_options_cfunc(opt_name)
            end

            return v
        end
    },
}

function WaveVpiCtrl:get_max_cursor_index()
    if not self.get_max_cursor_index_cfunc then
        self.get_max_cursor_index_cfunc = try_ffi_cast(
            "uint64_t (*)()",
            "uint64_t wave_vpi_ctrl_get_max_cursor_index();",
            "wave_vpi_ctrl_get_max_cursor_index"
        ) --[[@as fun(index: integer): integer]]
    end

    return self.get_max_cursor_index_cfunc()
end

function WaveVpiCtrl:set_cursor_index(index)
    if not self.set_cursor_index_cfunc then
        self.set_cursor_index_cfunc = try_ffi_cast(
            "void (*)(uint64_t)",
            "void wave_vpi_ctrl_set_cursor_index(uint64_t index);",
            "wave_vpi_ctrl_set_cursor_index"
        ) --[[@as fun(index: integer)]]
    end

    self.set_cursor_index_cfunc(index)
end

function WaveVpiCtrl:to_end()
    local max_index = self:get_max_cursor_index()
    self:set_cursor_index(max_index - 1)
end

function WaveVpiCtrl:to_percent(percent)
    if not self.set_cursor_index_percent_cfunc then
        self.set_cursor_index_percent_cfunc = try_ffi_cast(
            "void (*)(double)",
            "void wave_vpi_ctrl_set_cursor_index_percent(double percent);",
            "wave_vpi_ctrl_set_cursor_index_percent"
        ) --[[@as fun(percent: number)]]
    end

    assert(percent <= 100)
    self.set_cursor_index_percent_cfunc(percent)
end

return WaveVpiCtrl

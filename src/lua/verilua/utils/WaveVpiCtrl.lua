---@diagnostic disable: unnecessary-assert

local SymbolHelper = require "SymbolHelper"
local Logger = require "verilua.utils.Logger"

local logger = Logger.new("WaveVpiCtrl")

local f = string.format

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

---@alias verilua.utils.WaveVpiJitOptionNames
--- | "enable"
--- | "verbose"
--- | "max_opt_threads"
--- | "hot_access_threshold"
--- | "compile_window_size"
--- | "recompile_window_size"

---@class (exact) verilua.utils.WaveVpiJitOptions
---@field set fun(self: verilua.utils.WaveVpiJitOptions, opt_name: verilua.utils.WaveVpiJitOptionNames, value: integer|boolean)
---@field get fun(self: verilua.utils.WaveVpiJitOptions, opt_name: verilua.utils.WaveVpiJitOptionNames): integer|boolean
---@field protected set_jit_options_cfunc? fun(opt_name: string, value: integer)
---@field protected get_jit_options_cfunc? fun(opt_name: string): integer

---@class (exact) verilua.utils.WaveVpiCtrl
--- WaveVpiCtrl is a singleton class that provides control over the wave_vpi simulator, which is used by verilua to simulate waveform file.
---
---@field get_cursor_index fun(self: verilua.utils.WaveVpiCtrl): integer
---@field get_max_cursor_index fun(self: verilua.utils.WaveVpiCtrl): integer
---@field get_max_cursor_time fun(self: verilua.utils.WaveVpiCtrl): integer Get the maximum time in the waveform file (in femtoseconds)
---@field set_cursor_index fun(self: verilua.utils.WaveVpiCtrl, index: integer, flush_scheduler: boolean?)
---@field jit_options verilua.utils.WaveVpiJitOptions
---@field to_end fun(self: verilua.utils.WaveVpiCtrl, flush_scheduler: boolean?) Move the cursor to the end of the waveform file .
---@field to_percent fun(self: verilua.utils.WaveVpiCtrl, percent: number, flush_scheduler: boolean?) Move the cursor to the specified percent of the waveform file .
---@field set_cursor_time fun(self: verilua.utils.WaveVpiCtrl, time: integer, flush_scheduler: boolean?) Move the cursor to the specified time (in femtoseconds)
---@field protected get_max_cursor_index_cfunc fun(): integer
---@field protected get_max_cursor_time_cfunc fun(): integer
---@field protected set_cursor_index_cfunc fun(index: integer)
---@field protected set_cursor_index_percent_cfunc fun(percent: number)
---@field protected set_cursor_time_cfunc fun(time: integer)
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

function WaveVpiCtrl:get_cursor_index()
    if not self.get_cursor_index_cfunc then
        self.get_cursor_index_cfunc = try_ffi_cast(
            "uint64_t (*)()",
            "uint64_t wave_vpi_ctrl_get_cursor_index();",
            "wave_vpi_ctrl_get_cursor_index"
        ) --[[@as fun(): integer]]
    end

    return self.get_cursor_index_cfunc()
end

function WaveVpiCtrl:get_max_cursor_index()
    if not self.get_max_cursor_index_cfunc then
        self.get_max_cursor_index_cfunc = try_ffi_cast(
            "uint64_t (*)()",
            "uint64_t wave_vpi_ctrl_get_max_cursor_index();",
            "wave_vpi_ctrl_get_max_cursor_index"
        ) --[[@as fun(): integer]]
    end

    return self.get_max_cursor_index_cfunc()
end

function WaveVpiCtrl:get_max_cursor_time()
    if not self.get_max_cursor_time_cfunc then
        self.get_max_cursor_time_cfunc = try_ffi_cast(
            "uint64_t (*)()",
            "uint64_t wave_vpi_ctrl_get_max_cursor_time();",
            "wave_vpi_ctrl_get_max_cursor_time"
        ) --[[@as fun(): integer]]
    end

    return self.get_max_cursor_time_cfunc()
end

local function do_flush_scheduler()
    local curr_task_id = scheduler.curr_task_id
    local task_infos = scheduler:get_running_tasks()
    for _, task_info in ipairs(task_infos) do
        if task_info.id ~= curr_task_id then
            scheduler:remove_task(task_info.id)
        end
    end
end

function WaveVpiCtrl:set_cursor_index(index, flush_scheduler)
    if not self.set_cursor_index_cfunc then
        self.set_cursor_index_cfunc = try_ffi_cast(
            "void (*)(uint64_t)",
            "void wave_vpi_ctrl_set_cursor_index(uint64_t index);",
            "wave_vpi_ctrl_set_cursor_index"
        ) --[[@as fun(index: integer)]]
    end

    local curr_index = self:get_cursor_index()
    if curr_index ~= 0 and not flush_scheduler then
        assert(false, f(
            "[WaveVpiCtrl::set_cursor_index] `flush_scheduler` must be `true` when index is not 0, curr_index: %d",
            curr_index
        ))
    end

    if flush_scheduler then
        logger:warning(f(
            [[::set_cursor_index
    `flush_scheduler` is `true`, all tasks except the current task will be removed!
    The cursor index is set from `%d` to %d.
    This may cause unexpected behavior.
]],
            self:get_cursor_index(),
            index
        ))
        do_flush_scheduler()
    end

    self.set_cursor_index_cfunc(index)
end

function WaveVpiCtrl:to_end(flush_scheduler)
    local max_index = self:get_max_cursor_index()
    self:set_cursor_index(max_index - 1, flush_scheduler)
end

function WaveVpiCtrl:to_percent(percent, flush_scheduler)
    if not self.set_cursor_index_percent_cfunc then
        self.set_cursor_index_percent_cfunc = try_ffi_cast(
            "void (*)(double)",
            "void wave_vpi_ctrl_set_cursor_index_percent(double percent);",
            "wave_vpi_ctrl_set_cursor_index_percent"
        ) --[[@as fun(percent: number)]]
    end

    assert(percent <= 100)

    if flush_scheduler then
        logger:warning(f(
            [[::to_percent
    `flush_scheduler` is `true`, all tasks except the current task will be removed!
    The cursor index is set from `%d` to (%d * %.2f).
    This may cause unexpected behavior.
]],
            self:get_cursor_index(),
            self:get_max_cursor_index(),
            percent / 100
        ))
        do_flush_scheduler()
    end

    self.set_cursor_index_percent_cfunc(percent)
end

function WaveVpiCtrl:set_cursor_time(time, flush_scheduler)
    if not self.set_cursor_time_cfunc then
        self.set_cursor_time_cfunc = try_ffi_cast(
            "void (*)(uint64_t)",
            "void wave_vpi_ctrl_set_cursor_time(uint64_t time);",
            "wave_vpi_ctrl_set_cursor_time"
        ) --[[@as fun(time: integer)]]
    end

    if time < 0 then
        assert(false, f(
            "[WaveVpiCtrl::set_cursor_time] time must be >= 0, got: %d",
            time
        ))
    end

    local max_time = self:get_max_cursor_time()
    if time > max_time then
        assert(false, f(
            "[WaveVpiCtrl::set_cursor_time] time exceeds maximum waveform time: %d > %d",
            time,
            max_time
        ))
    end

    local curr_index = self:get_cursor_index()
    if curr_index ~= 0 and not flush_scheduler then
        assert(false, f(
            "[WaveVpiCtrl::set_cursor_time] `flush_scheduler` must be `true` when index is not 0, curr_index: %d",
            curr_index
        ))
    end

    if flush_scheduler then
        logger:warning(f(
            [[::set_cursor_time
    `flush_scheduler` is `true`, all tasks except the current task will be removed!
    The cursor is set to time %d fs.
    This may cause unexpected behavior.
]],
            time
        ))
        do_flush_scheduler()
    end

    self.set_cursor_time_cfunc(time)
end

return WaveVpiCtrl

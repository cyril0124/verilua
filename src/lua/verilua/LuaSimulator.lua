---@diagnostic disable: assign-type-mismatch, unnecessary-assert

local io = require "io"
local os = require "os"
local ffi = require "ffi"
local path = require "pl.path"
local vpiml = require "verilua.vpiml.vpiml"
local SymbolHelper = require "verilua.utils.SymbolHelper"

local assert = assert
local table_insert = table.insert
local table_sort = table.sort

local cfg = _G.cfg
local simulator = cfg.simulator

local is_hse = cfg.is_hse
local is_wal = cfg.is_wal

local is_vcs = simulator == "vcs"
local is_xcelium = simulator == "xcelium"
local is_verilator = simulator == "verilator"
local is_iverilog = simulator == "iverilog"
local is_wave_vpi = simulator == "wave_vpi"
local is_nosim = simulator == "nosim"

---@type fun(scope_name: string?)
local set_dpi_scope
if is_verilator or is_vcs or is_xcelium then
    local svSetScope = SymbolHelper.try_ffi_cast(
        "void (*)(void *)",
        "void svSetScope(void *scope)",
        "svSetScope"
    )
    local svGetScopeFromName = SymbolHelper.try_ffi_cast(
        "void *(*)(const char *)",
        "void svGetScopeFromName(const char *name)",
        "svGetScopeFromName"
    )

    set_dpi_scope = function(scope_name)
        scope_name = scope_name or cfg.top
        svSetScope(svGetScopeFromName(scope_name))
    end
else
    set_dpi_scope = function(_)
        assert(false, string.format("Simulator: %s not support set_dpi_scope", simulator))
    end
end

ffi.cdef [[
    void simulation_initializeTrace(char *traceFilePath);
    void simulation_enableTrace(void);
    void simulation_disableTrace(void);

    void verilator_simulation_initializeTrace(char *traceFilePath);
    void verilator_simulation_enableTrace(void);
    void verilator_simulation_disableTrace(void);

    void c_simulator_control(long long cmd);

    void vpiml_iterate_vpi_type(const char *module_name, int type);
    typedef void (*vpiml_hierarchy_cb_t)(const char *full_path, const char *name, int level);
    void vpiml_collect_hierarchy(int max_level, vpiml_hierarchy_cb_t cb);
    int wildmatch(const char *pattern, const char *str);
]]

local default_wave_name = "test"

local initialize_trace = function(trace_file_path)
    assert(trace_file_path ~= nil)
    if is_vcs or is_xcelium then
        set_dpi_scope()
        ffi.C.simulation_initializeTrace(ffi.cast("char *", trace_file_path))
    elseif is_verilator then
        ffi.C.verilator_simulation_initializeTrace(ffi.cast("char *", trace_file_path))
    elseif is_iverilog then
        _G.await_time(0) -- waiting for simulation start

        local traceFilePath = trace_file_path or default_wave_name .. ".vcd"
        local file, err = io.open("iverilog_trace_name.txt", "w")

        assert(file, "Failed to open file: " .. tostring(err))

        file:write(traceFilePath .. "\n")
        file:close()

        dut.simulation_initializeTrace = 1
        dut.simulation_initializeTrace_latch = 0
    elseif is_wave_vpi or is_nosim then
        assert(false, "[initialize_trace] not support for wave_vpi/nosim")
    else
        assert(false, "Unknown simulator => " .. simulator)
    end
end

local enable_trace = function()
    if is_vcs or is_xcelium then
        set_dpi_scope()
        ffi.C.simulation_enableTrace()
    elseif is_verilator then
        ffi.C.verilator_simulation_enableTrace()
    elseif is_iverilog then
        dut.simulation_enableTrace = 1
        dut.simulation_enableTrace_latch = 0
    elseif is_wave_vpi or is_nosim then
        assert(false, "[enable_trace] not support for wave_vpi/nosim")
    else
        assert(false, "Unknown simulator => " .. simulator)
    end
end

local disable_trace = function()
    if is_vcs or is_xcelium then
        set_dpi_scope()
        ffi.C.simulation_disableTrace()
    elseif is_verilator then
        ffi.C.verilator_simulation_disableTrace()
    elseif is_iverilog then
        dut.simulation_disableTrace = 1
        dut.simulation_disableTrace_latch = 0

        dut.simulation_enableTrace = 0
        dut.simulation_enableTrace_latch = 0
    elseif is_wave_vpi or is_nosim then
        assert(false, "[disable_trace] not support for wave_vpi/nosim")
    else
        assert(false, "Unknown simulator => " .. simulator)
    end
end

local dump_wave = function(trace_file_path)
    if is_xcelium and trace_file_path then
        -- The reason is that $shm_open cannot accept string variable as the input file name.
        print(
            "[dump_wave] xcelium not support custom trace file name when dumping `.shm` wave, the default name is `waves.shm`"
        )
    end

    local _trace_file_path = trace_file_path or default_wave_name .. ".vcd"
    local trace_path = path.abspath(path.dirname(_trace_file_path))

    if not path.exists(trace_path) then
        path.mkdir(trace_path)
    end

    initialize_trace(_trace_file_path)
    enable_trace()
end

---@enum verilua.SimCtrl
local SimCtrl = {
    STOP = 66,
    FINISH = 67,
    RESET = 68,
    SET_INTERATIVE_SCOPE = 69
}

local simulator_control = function(sim_crtl)
    ffi.C.c_simulator_control(sim_crtl)
end

local finish = function()
    simulator_control(SimCtrl.FINISH)
end


-- Bypass initial phase, typically used at the outtest fork task
--- e.g.
--- ```lua
--- fork {
---     outtest_forked_task = function()
---         sim.bypass_initial()
---
---         fork {
---             inner_forked_task = function()
---                 -- ...
---             end
---         }
---
---         -- ....
---     end
--- }
--- ```
local already_bypass_initial = false
local bypass_initial = function()
    assert(not already_bypass_initial, "bypass_initial can only be called once!")
    already_bypass_initial = true
    await_nsim()
end

---@class verilua.PrintHierarchyOptions
---@field max_level? integer Maximum traversal depth. `0` means no limit.
---@field wildcard? string Wildcard pattern matched against full hierarchy path (e.g. `top.path.*.to.some`).

---@class verilua.NormalizedHierarchyOptions
---@field max_level integer
---@field wildcard? string

---@return "tree"|"compact"
local function get_print_hierarchy_style()
    local style = os.getenv("VERILUA_PRINT_HIER_STYLE")
    if style == "compact" then
        return "compact"
    end
    return "tree"
end

---@param options? verilua.PrintHierarchyOptions
---@return verilua.NormalizedHierarchyOptions
local function normalize_hierarchy_options(options)
    if options == nil then
        options = {}
    end
    assert(type(options) == "table", "[print_hierarchy/get_hierarchy] options must be a table")

    local max_level = 0
    ---@type string?
    local wildcard = nil

    if options.max_level ~= nil then
        assert(type(options.max_level) == "number", "[print_hierarchy/get_hierarchy] options.max_level must be number")
        max_level = options.max_level
    end
    if options.wildcard ~= nil then
        assert(type(options.wildcard) == "string", "[print_hierarchy/get_hierarchy] options.wildcard must be string")
        wildcard = options.wildcard
    end

    assert(max_level >= 0, "[print_hierarchy/get_hierarchy] max_level must be >= 0")
    assert(math.floor(max_level) == max_level, "[print_hierarchy/get_hierarchy] max_level must be an integer")

    return {
        max_level = max_level,
        wildcard = wildcard,
    }
end

---@param name string
---@param level integer
---@param style "tree"|"compact"
---@return string
local function render_hierarchy_line(name, level, style)
    if style == "compact" then
        local prefix = string.rep("  ", level)
        return string.format("[L%d] %s%s", level, prefix, name)
    end

    if level == 0 then
        return name
    else
        local prefix = string.rep("|   ", level - 1)
        return prefix .. "|-- " .. name
    end
end

---@param normalized_options verilua.NormalizedHierarchyOptions
---@return table<integer, string>
local function collect_hierarchy_paths(normalized_options)
    ---@type table<integer, string>
    local hierarchy_paths = {}
    local seen_paths = {}
    local callback = ffi.cast("vpiml_hierarchy_cb_t", function(full_path_c, _name_c, _level)
        local full_path = ffi.string(full_path_c)
        if normalized_options.wildcard ~= nil and ffi.C.wildmatch(normalized_options.wildcard, full_path) ~= 1 then
            return
        end

        if seen_paths[full_path] then
            return
        end
        seen_paths[full_path] = true
        table_insert(hierarchy_paths, full_path)
    end)
    ffi.C.vpiml_collect_hierarchy(normalized_options.max_level, callback)
    callback = nil

    return hierarchy_paths
end

---@param full_path string
---@return table<integer, string>
local function get_hierarchy_path_segments(full_path)
    local segments = {}
    for seg in full_path:gmatch("[^%.]+") do
        table_insert(segments, seg)
    end
    return segments
end

---@param all_paths table<integer, string>
---@param wildcard string
---@return table<integer, string>
local function build_wildcard_tree_paths(all_paths, wildcard)
    local visible_path_set = {}
    for _, full_path in ipairs(all_paths) do
        if ffi.C.wildmatch(wildcard, full_path) == 1 then
            local prefix = ""
            for _, seg in ipairs(get_hierarchy_path_segments(full_path)) do
                prefix = (prefix == "") and seg or (prefix .. "." .. seg)
                visible_path_set[prefix] = true
            end
        end
    end

    local visible_paths = {}
    for full_path, _ in pairs(visible_path_set) do
        table_insert(visible_paths, full_path)
    end
    table_sort(visible_paths)
    return visible_paths
end

---@param options? verilua.PrintHierarchyOptions
--- Returns hierarchy full paths, e.g. `tb_top.u_top.u_mid`.
---@return table<integer, string>
local get_hierarchy = function(options)
    local normalized_options = normalize_hierarchy_options(options)
    return collect_hierarchy_paths(normalized_options)
end

---@param options? verilua.PrintHierarchyOptions
local print_hierarchy = function(options)
    local normalized_options = normalize_hierarchy_options(options)
    local style = get_print_hierarchy_style()
    if normalized_options.wildcard then
        print(string.format("[print_hierarchy] max_level=%d style=%s wildcard=%s", normalized_options.max_level, style, normalized_options.wildcard))
    else
        print(string.format("[print_hierarchy] max_level=%d style=%s", normalized_options.max_level, style))
    end

    local hierarchy_paths = get_hierarchy(options)
    if normalized_options.wildcard ~= nil and style == "tree" then
        local all_paths = collect_hierarchy_paths {
            max_level = normalized_options.max_level,
            wildcard = nil,
        }
        hierarchy_paths = build_wildcard_tree_paths(all_paths, normalized_options.wildcard)
    end

    for _, full_path in ipairs(hierarchy_paths) do
        local _, level = full_path:gsub("%.", "")
        local name = full_path:match("([^%.]+)$") or full_path
        print(render_hierarchy_line(name, level, style))
    end
    print("")
end

local iterate_vpi_type = function(module_name, type)
    ffi.C.vpiml_iterate_vpi_type(module_name, type)
end

--- Time unit to exponent mapping
local UNIT_TO_EXPONENT = {
    fs = -15,
    ps = -12,
    ns = -9,
    us = -6,
    ms = -3,
    s = 0,
    sec = 0,
}

--- Get current simulation time
---@param unit? "fs"|"ps"|"ns"|"us"|"ms"|"s" Time unit ("fs", "ps", "ns", "us", "ms", "s"), default returns steps
---@return number Simulation time
local get_sim_time = function(unit)
    ---@diagnostic disable-next-line
    local steps = vpiml.vpiml_get_sim_time()

    if unit == nil or unit == "step" then
        return steps
    end

    local target_exp = UNIT_TO_EXPONENT[unit]
    if target_exp == nil then
        assert(false, "Unknown time unit: " .. tostring(unit))
    end

    ---@diagnostic disable-next-line
    local precision = vpiml.vpiml_get_time_precision()
    local scale = 10 ^ (precision - target_exp)

    return steps * scale
end

if is_hse or is_wal then
    initialize_trace = function()
        assert(false, "[initialize_trace] not supported for HSE/WAL scenario")
    end

    enable_trace = function()
        assert(false, "[enable_trace] not supported for HSE/WAL scenario")
    end

    disable_trace = function()
        assert(false, "[disable_trace] not supported for HSE/WAL scenario")
    end

    dump_wave = function()
        assert(false, "[dump_wave] not supported for HSE/WAL scenario")
    end

    iterate_vpi_type = function()
        assert(false, "[iterate_vpi_type] not supported for HSE/WAL scenario")
    end
end

if is_hse then
    print_hierarchy = function()
        assert(false, "[print_hierarchy] not supported for HSE scenario (dummy_vpi does not implement vpi_iterate/vpi_scan)")
    end

    get_hierarchy = function()
        assert(false, "[get_hierarchy] not supported for HSE scenario (dummy_vpi does not implement vpi_iterate/vpi_scan)")
        return {}
    end

    get_sim_time = function()
        assert(false, "[get_sim_time] not supported for HSE scenario")
        return 0
    end
end

if is_wal and not is_wave_vpi then
    print_hierarchy = function()
        assert(false, "[print_hierarchy] not supported for WAL(non-wave_vpi) scenario (dummy_vpi may not implement vpi_iterate/vpi_scan)")
    end

    get_hierarchy = function()
        assert(false, "[get_hierarchy] not supported for WAL(non-wave_vpi) scenario (dummy_vpi may not implement vpi_iterate/vpi_scan)")
        return {}
    end
end

---@class verilua.LuaSimulator
---@field SimCtrl table<string, integer>
---@field set_dpi_scope fun(scope_name?: string)
---@field initialize_trace fun(trace_file_path: string)
---@field enable_trace fun()
---@field disable_trace fun()
---@field dump_wave fun(trace_file_path?: string)
---@field simulator_control fun(sim_crtl: verilua.SimCtrl)
---@field finish fun()
---@field bypass_initial fun()
---@field get_mode fun(): integer
---@field print_hierarchy fun(options?: verilua.PrintHierarchyOptions)
---@field get_hierarchy fun(options?: verilua.PrintHierarchyOptions): table<integer, string>
---@field iterate_vpi_type fun(module_name: string, type: integer)
---@field get_sim_time fun(unit?: "fs"|"ps"|"ns"|"us"|"ms"|"s"): integer
local LuaSimulator = {
    set_dpi_scope     = set_dpi_scope,
    initialize_trace  = initialize_trace,
    enable_trace      = enable_trace,
    disable_trace     = disable_trace,
    dump_wave         = dump_wave,
    simulator_control = simulator_control,
    SimCtrl           = SimCtrl,
    finish            = finish,
    bypass_initial    = bypass_initial,
    print_hierarchy   = print_hierarchy,
    get_hierarchy     = get_hierarchy,
    iterate_vpi_type  = iterate_vpi_type,
    get_sim_time      = get_sim_time,
}

return LuaSimulator

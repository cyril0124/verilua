---@diagnostic disable: assign-type-mismatch, unnecessary-assert

local io = require "io"
local os = require "os"
local ffi = require "ffi"
local path = require "pl.path"
local utils = require "LuaUtils"

local assert = assert
local ffi_new = ffi.new

local cfg = _G.cfg
local simulator = cfg.simulator

local is_vcs = simulator == "vcs"
local is_xcelium = simulator == "xcelium"
local is_verilator = simulator == "verilator"
local is_iverilog = simulator == "iverilog"
local is_wave_vpi = simulator == "wave_vpi"
local is_nosim = simulator == "nosim"

---@type fun(scope_name: string?)
local set_dpi_scope
if is_verilator or is_vcs or is_xcelium then
    local svSetScope = utils.try_ffi_cast(
        "void (*)(void *)",
        "void svSetScope(void *scope)",
        "svSetScope"
    )
    local svGetScopeFromName = utils.try_ffi_cast(
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
]]

local initialize_trace = function(trace_file_path)
    assert(trace_file_path ~= nil)
    if is_vcs or is_xcelium then
        set_dpi_scope()
        ffi.C.simulation_initializeTrace(ffi.cast("char *", trace_file_path))
    elseif is_verilator then
        ffi.C.verilator_simulation_initializeTrace(ffi.cast("char *", trace_file_path))
    elseif is_iverilog then
        _G.await_time(0) -- waitting for simulation start

        local traceFilePath = trace_file_path or "dump.vcd"
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

    local _trace_file_path = trace_file_path or "test.vcd"
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
    if is_xcelium then
        os.exit(0)
    end
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

---@type any
local print_hierarchy_lib
local print_hierarchy = function(max_level)
    max_level = max_level or 0

    if not print_hierarchy_lib then
        local VERILUA_HOME = assert(os.getenv("VERILUA_HOME"), "[LuaSimulator] VERILUA_HOME is not set")
        print_hierarchy_lib = (utils.read_file_str(VERILUA_HOME .. "/src/lua/verilua/tcc_snippet/print_hierarchy.c"))
            :tcc_compile {
                {
                    sym = "print_hierarchy",
                    ptr = "void (*)(unsigned int*, int)"
                }
            }
    end
    print_hierarchy_lib.print_hierarchy(ffi_new("unsigned int*", nil), max_level)
end

local iterate_vpi_type = function(module_name, type)
    ffi.C.vpiml_iterate_vpi_type(module_name, type)
end

---@class (exact) verilua.LuaSimulator
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
---@field print_hierarchy fun(max_level?: integer)
---@field iterate_vpi_type fun(module_name: string, type: integer)
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
    iterate_vpi_type  = iterate_vpi_type
}

return LuaSimulator

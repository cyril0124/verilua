local io = require "io"
local os = require "os"
local ffi = require "ffi"
local path = require "pl.path"
local utils = require "LuaUtils"

local pcall = pcall
local assert = assert
local tonumber = tonumber
local ffi_new = ffi.new

local cfg = _G.cfg
local SchedulerMode = _G.SchedulerMode
local verilua_debug = _G.verilua_debug
local verilua_warning = _G.verilua_warning

local set_dpi_scope
if cfg.simulator == "vcs" then
    ffi.cdef[[
        int vcs_get_mode(void);

        void *svGetScopeFromName(char *str);
        void svSetScope(void *scope);
    ]]

    set_dpi_scope = function ()
        ffi.C.svSetScope(ffi.C.svGetScopeFromName(ffi.cast("char *", cfg.top)))
    end
end

ffi.cdef[[
    void simulation_initializeTrace(char *traceFilePath);
    void simulation_enableTrace(void);
    void simulation_disableTrace(void);

    void verilator_simulation_initializeTrace(char *traceFilePath);
    void verilator_simulation_enableTrace(void);
    void verilator_simulation_disableTrace(void);

    int verilator_get_mode(void);
    void c_simulator_control(long long cmd);

    void vpiml_iterate_vpi_type(const char *module_name, int type);
]]

local initialize_trace = function (trace_file_path)
    assert(trace_file_path ~= nil)
    if cfg.simulator == "vcs" then
        set_dpi_scope()
        ffi.C.simulation_initializeTrace(ffi.cast("char *", trace_file_path))
    elseif cfg.simulator == "verilator" then
        ffi.C.verilator_simulation_initializeTrace(ffi.cast("char *", trace_file_path))
    elseif cfg.simulator == "iverilog" then
        _G.await_time(0) -- waitting for simulation start
        
        local traceFilePath = trace_file_path or "dump.vcd"
        local file, err = io.open("iverilog_trace_name.txt", "w")
    
        if not file then
            assert(false, "Failed to open file: " .. err)
        end
    
        file:write(traceFilePath .. "\n")
        file:close()
    
        dut.simulation_initializeTrace = 1
        dut.simulation_initializeTrace_latch = 0
    elseif cfg.simulator == "wave_vpi" then
        assert(false, "[initialize_trace] not support for wave_vpi now")
    else
        assert(false, "Unknown simulator => " .. cfg.simulator)
    end
end

local enable_trace = function ()    
    if cfg.simulator == "vcs" then
        set_dpi_scope()
        ffi.C.simulation_enableTrace()
    elseif cfg.simulator == "verilator" then
        ffi.C.verilator_simulation_enableTrace()
    elseif cfg.simulator == "iverilog" then
        dut.simulation_enableTrace = 1
        dut.simulation_enableTrace_latch = 0
    elseif cfg.simulator == "wave_vpi" then
        assert(false, "[enable_trace] not support for wave_vpi now")
    else
        assert(false, "Unknown simulator => " .. cfg.simulator)
    end
end

local disable_trace = function ()
    if cfg.simulator == "vcs" then
        set_dpi_scope()
        ffi.C.simulation_disableTrace()
    elseif cfg.simulator == "verilator" then
        ffi.C.verilator_simulation_disableTrace()
    elseif cfg.simulator == "iverilog" then
        dut.simulation_disableTrace = 1
        dut.simulation_disableTrace_latch = 0

        dut.simulation_enableTrace = 0
        dut.simulation_enableTrace_latch = 0
    elseif cfg.simulator == "wave_vpi" then
        assert(false, "[disable_trace] not support for wave_vpi now")
    else
        assert(false, "Unknown simulator => " .. cfg.simulator)
    end
end

local dump_wave = function (trace_file_path)
    local _trace_file_path = trace_file_path or "test.vcd"
    local trace_path = path.abspath(path.dirname(_trace_file_path))
    
    if not path.exists(trace_path) then
        path.mkdir(trace_path)
    end

    initialize_trace(_trace_file_path)
    enable_trace()
end

local SimCtrl = {
    STOP = 66,
    FINISH = 67,
    RESET = 68,
    SET_INTERATIVE_SCOPE = 69
}

local simulator_control = function (sim_crtl)
    ffi.C.c_simulator_control(sim_crtl)
end

local finish = function ()
    simulator_control(SimCtrl.FINISH)
end

local get_mode = function()
    if cfg.simulator == "vcs" then
        set_dpi_scope()
        local success, mode = pcall(function () return ffi.C.vcs_get_mode() end)
        if not success then
            mode = SchedulerMode.NORMAL
            verilua_warning("cannot found ffi.C.vcs_get_mode(), using default mode NORMAL")
        end
        return tonumber(mode)
    else
        assert(cfg.simulator == "verilator", "For now, only support Verilator")
        local mode = ffi.C.verilator_get_mode()
        return tonumber(mode)
    end
end

local print_hierarchy_lib
local print_hierarchy = function (max_level)
    local max_level = max_level or 0
    if not print_hierarchy_lib then
        local VERILUA_HOME = assert(os.getenv("VERILUA_HOME"), "[LuaSimulator] VERILUA_HOME is not set")
        print_hierarchy_lib = (utils.read_file_str(VERILUA_HOME .. "/src/lua/verilua/tcc_snippet/print_hierarchy.c")):tcc_compile {
            {
                sym = "print_hierarchy",
                ptr = "void (*)(unsigned int*, int)"
            }
        }
    end
    print_hierarchy_lib.print_hierarchy(ffi_new("unsigned int*", nil), max_level)
end

local iterate_vpi_type = function (module_name, type)
    ffi.C.vpiml_iterate_vpi_type(module_name, type)
end

return {
    initialize_trace  = initialize_trace,
    enable_trace      = enable_trace,
    disable_trace     = disable_trace,
    dump_wave         = dump_wave,
    simulator_control = simulator_control,
    SimCtrl           = SimCtrl,
    finish            = finish,
    get_mode          = get_mode,
    print_hierarchy   = print_hierarchy,
    iterate_vpi_type  = iterate_vpi_type
}

require("LuaCallableHDL")
local scheduler = require "LuaScheduler"

if cfg.simulator == "vcs" then
    ffi.cdef[[
        void dpi_set_scope(char *str);
        int vcs_get_mode(void);
    ]]
end

ffi.cdef[[
    void simulation_initializeTrace(char *traceFilePath);
    void simulation_enableTrace(void);
    void simulation_disableTrace(void);

    void verilator_simulation_initializeTrace(char *traceFilePath);
    void verilator_simulation_enableTrace(void);
    void verilator_simulation_disableTrace(void);

    int verilator_get_mode(void);
]]

local cycles_chdl = nil
local use_step_cycles = false
local init = function ()
    verilua_info("LuaSimulator initialize...")
    
    use_step_cycles = cfg.mode == VeriluaMode.STEP and cfg.attach == true

    if not use_step_cycles then
        cycles_chdl = CallableHDL(cfg.top..".cycles", "cycles_chdl for LuaSimulator")
        assert(cycles_chdl ~= nil)
    else
        assert(scheduler.cycles ~= nil)
    end
end

local get_cycles = function()
    if not use_step_cycles then
        return cycles_chdl()
    else
        return scheduler.cycles
    end
end

local initialize_trace = function (trace_file_path)
    assert(trace_file_path ~= nil)
    if cfg.simulator == "vcs" then
        ffi.C.dpi_set_scope(ffi.cast("char *", cfg.top))
        ffi.C.simulation_initializeTrace(ffi.cast("char *", trace_file_path))
    elseif cfg.simulator == "verilator" then
        ffi.C.verilator_simulation_initializeTrace(ffi.cast("char *", trace_file_path))
    else
        assert(false, "Unknown simulator => " .. cfg.simulator)
    end
end

local enable_trace = function ()    
    if cfg.simulator == "vcs" then
        ffi.C.dpi_set_scope(ffi.cast("char *", cfg.top))
        ffi.C.simulation_enableTrace()
    elseif cfg.simulator == "verilator" then
        ffi.C.verilator_simulation_enableTrace()
    else
        assert(false, "Unknown simulator => " .. cfg.simulator)
    end
end

local disable_trace = function ()
    if cfg.simulator == "vcs" then
        ffi.C.dpi_set_scope(ffi.cast("char *", cfg.top))
        ffi.C.simulation_disableTrace()
    elseif cfg.simulator == "verilator" then
        ffi.C.verilator_simulation_disableTrace()
    else
        assert(false, "Unknown simulator => " .. cfg.simulator)
    end
end

local SimCtrl = {
    STOP = 66,
    FINISH = 67,
    RESET = 68,
    SET_INTERATIVE_SCOPE = 69
}

local simulator_control = function (sim_crtl)
    vpi.simulator_control(sim_crtl)
end

local get_mode = function()
    if cfg.simulator == "vcs" then
        ffi.C.dpi_set_scope(ffi.cast("char *", cfg.top))
        local mode = ffi.C.vcs_get_mode()
        return tonumber(mode)
    else
        assert(cfg.simulator == "verilator", "For now, only support Verilator")
        local mode = ffi.C.verilator_get_mode()
        return tonumber(mode)
    end
end

return {
    init              = init,
    get_cycles        = get_cycles,
    initialize_trace  = initialize_trace,
    enable_trace      = enable_trace,
    disable_trace     = disable_trace,
    simulator_control = simulator_control,
    SimCtrl           = SimCtrl,
    get_mode          = get_mode
}

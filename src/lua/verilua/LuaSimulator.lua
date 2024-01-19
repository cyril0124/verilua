require("LuaCallableHDL")

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
    int verilator_get_mode(void);
]]

local cycles_chdl = nil
local init = function ()
    verilua_info("LuaSimulator initialize...")
    cycles_chdl = CallableHDL(cfg.top..".cycles", "cycles_chdl for LuaSimulator")
    assert(cycles_chdl ~= nil)
end

local get_cycles = function()
    return cycles_chdl()
end

local initialize_trace = function (trace_file_path)
    assert(cfg.simulator == "vcs", "For now, only support VCS")
    assert(trace_file_path ~= nil)
    ffi.C.dpi_set_scope(ffi.cast("char *", cfg.top))
    ffi.C.simulation_initializeTrace(ffi.cast("char *", trace_file_path))
end

local enable_trace = function ()
    assert(cfg.simulator == "vcs", "For now, only support VCS")
    ffi.C.dpi_set_scope(ffi.cast("char *", cfg.top))
    ffi.C.simulation_enableTrace()
end

local disable_trace = function ()
    assert(cfg.simulator == "vcs", "For now, only support VCS")
    ffi.C.dpi_set_scope(ffi.cast("char *", cfg.top))
    ffi.C.simulation_disableTrace()
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

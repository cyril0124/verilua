#include "lua_vpi.h"


extern bool verilua_is_init;

// ---------------------------------------
// functions from verilator side
// ---------------------------------------
// TODO: default implementation
vl_func_t verilator_next_sim_step_impl = NULL;
vl_func_t verilator_get_mode_impl = NULL;
vl_func_t verilator_simulation_initializeTrace_impl = NULL;
vl_func_t verilator_simulation_enableTrace_impl = NULL;
vl_func_t verilator_simulation_disableTrace_impl = NULL;

namespace Verilua {
    
void alloc_verilator_func(vl_func_t func, std::string name) {
    if (verilua_is_init == true) {
        VL_FATAL(false, "you should alloc a verilator function before call verilua_init()");
    }

    VL_INFO("alloc verilator function name:{}\n", name);

    if (name == "next_sim_step") {
        verilator_next_sim_step_impl = func;
    } else if (name == "get_mode") {
        verilator_get_mode_impl = func;
    } else if (name == "simulation_initializeTrace") {
        verilator_simulation_initializeTrace_impl = func;
    } else if (name == "simulation_enableTrace") {
        verilator_simulation_enableTrace_impl = func;
    } else if (name == "simulation_disableTrace") {
        verilator_simulation_disableTrace_impl = func;
    } else {
        VL_FATAL(false, "name:{} did not match any functions", name);
    }
}

}

TO_LUA void verilator_next_sim_step(void) {
    if (verilator_next_sim_step_impl == NULL) {
        VL_FATAL(false, "verilator_next_sim_step_impl is NULL");
    }

    verilator_next_sim_step_impl(NULL);
}

TO_LUA int verilator_get_mode(void) {
    if (verilator_get_mode_impl == NULL) {
        VL_FATAL(false, "verilator_get_mode_impl is NULL");
    }

    int mode = 0;
    verilator_get_mode_impl((void *)&mode);
    return mode;
}

TO_LUA void verilator_simulation_initializeTrace(char *traceFilePath) {
    if (verilator_simulation_initializeTrace_impl == NULL) {
        VL_FATAL(false, "verilator_simulation_initializeTrace_impl is NULL");
    }
    verilator_simulation_initializeTrace_impl((void *)traceFilePath);
}

TO_LUA void verilator_simulation_enableTrace(void) {
    if (verilator_simulation_enableTrace_impl == NULL) {
        VL_FATAL(false, "verilator_simulation_enableTrace_impl is NULL");
    }
    verilator_simulation_enableTrace_impl(NULL);
}

TO_LUA void verilator_simulation_disableTrace(void) {
    if (verilator_simulation_disableTrace_impl == NULL) {
        VL_FATAL(false, "verilator_simulation_disableTrace_impl is NULL");
    }
    verilator_simulation_disableTrace_impl(NULL);
}


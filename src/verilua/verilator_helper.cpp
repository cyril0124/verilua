#include "lua_vpi.h"

// ---------------------------------------
// functions from verilator side
// ---------------------------------------
VerilatorFunc verilator_next_sim_step_impl              = nullptr;
VerilatorFunc verilator_get_mode_impl                   = nullptr;
VerilatorFunc verilator_simulation_initializeTrace_impl = nullptr;
VerilatorFunc verilator_simulation_enableTrace_impl     = nullptr;
VerilatorFunc verilator_simulation_disableTrace_impl    = nullptr;

std::unordered_map<std::string, VerilatorFunc *> verilator_func_map = {
    {"next_sim_step"             , &verilator_next_sim_step_impl             },
    {"get_mode"                  , &verilator_get_mode_impl                  },
    {"simulation_initializeTrace", &verilator_simulation_initializeTrace_impl},
    {"simulation_enableTrace"    , &verilator_simulation_enableTrace_impl    },
    {"simulation_disableTrace"   , &verilator_simulation_disableTrace_impl   }
};

namespace Verilua {
    
void alloc_verilator_func(VerilatorFunc func, const std::string& name) {
    if (VeriluaEnv::get_instance().initialized) {
        VL_FATAL(false, "you should alloc a verilator function before call verilua_init()");
    }

    VL_STATIC_DEBUG("alloc verilator function name:%s\n", name.c_str());

    auto it = verilator_func_map.find(name);
    if(it != verilator_func_map.end()) {
        *(it->second) = func;
        VL_STATIC_DEBUG("alloc verilator function name:%s\n", name.c_str());
    } else {
        VL_FATAL(false, "name:%s is not in verilator_func_map", name.c_str());
    }
}

}

TO_LUA void verilator_next_sim_step(void) {
    if (verilator_next_sim_step_impl == nullptr) {
        VL_FATAL(false, "verilator_next_sim_step_impl is nullptr");
    }

    verilator_next_sim_step_impl(nullptr);
}

TO_LUA int verilator_get_mode(void) {
    if (verilator_get_mode_impl == nullptr) {
        VL_FATAL(false, "verilator_get_mode_impl is nullptr");
    }

    int mode = 0;
    verilator_get_mode_impl((void *)&mode);
    return mode;
}

TO_LUA void verilator_simulation_initializeTrace(char *traceFilePath) {
    if (verilator_simulation_initializeTrace_impl == nullptr) {
        VL_FATAL(false, "verilator_simulation_initializeTrace_impl is nullptr");
    }
    verilator_simulation_initializeTrace_impl((void *)traceFilePath);
}

TO_LUA void verilator_simulation_enableTrace(void) {
    if (verilator_simulation_enableTrace_impl == nullptr) {
        VL_FATAL(false, "verilator_simulation_enableTrace_impl is nullptr");
    }
    verilator_simulation_enableTrace_impl(nullptr);
}

TO_LUA void verilator_simulation_disableTrace(void) {
    if (verilator_simulation_disableTrace_impl == nullptr) {
        VL_FATAL(false, "verilator_simulation_disableTrace_impl is nullptr");
    }
    verilator_simulation_disableTrace_impl(nullptr);
}


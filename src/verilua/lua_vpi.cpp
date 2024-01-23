#include "lua_vpi.h"
#include "signal_access.h"
#include "vpi_callback.h"

// data type:
//  _____________________
// | Lua    |    C       |
// |________|____________|
// | string |  char *    |
// | number |  long long |
// | float  |  double    |
// |________|____________|

lua_State *L;
bool verilua_is_init = false;
bool verilua_is_final = false;
sol::protected_function sim_event; 
sol::protected_function main_step; 

IDPool edge_cb_idpool(50);
std::unordered_map<int, vpiHandle> edge_cb_hdl_map;
std::unordered_map<std::string, long long> handle_cache;

#ifdef ACCUMULATE_LUA_TIME
#include <chrono>
double lua_time = 0.0;
double start_time_for_step = 0.0;
double end_time_for_step = 0.0;
#endif

void execute_sim_event(int *id) {
#ifdef ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif
    auto ret = sim_event(*id);
    if(!ret.valid()) {
        if (!verilua_is_final) {
            execute_final_callback();
        }
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
#ifdef ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    lua_time += time_taken;
#endif
}

void execute_sim_event(int id) {
#ifdef ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif
    auto ret = sim_event(id);
    if(!ret.valid()) {
        if (!verilua_is_final) {
            execute_final_callback();
        }
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
#ifdef ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    lua_time += time_taken;
#endif
}

inline void execute_final_callback() {
    VL_INFO("execute_final_callback\n");
    { // This is the working filed of LuaRef, when we leave this file, LuaRef will release the allocated memory thus not course segmentation fault when use lua_close(L).
        try {
            luabridge::LuaRef lua_finish_callback = luabridge::getGlobal(L, "finish_callback");
            lua_finish_callback();
            verilua_is_final = true;
        } catch (const luabridge::LuaException& e) {
            VL_FATAL(false, "Error calling finish_callback, {}", e.what());
        }
    }
}

inline void execute_main_step() {
#ifdef ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif
    auto ret = main_step();
    if(!ret.valid()) {
        if (!verilua_is_final) {
            execute_final_callback();
        }
        sol::error  err = ret;
        VL_FATAL(false, "Error calling main_step, {}", err.what());
    }
#ifdef ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    lua_time += time_taken;
#endif
}

VERILUA_EXPORT void verilua_main_step() {
    execute_main_step();
}

VERILUA_EXPORT void verilua_final() {
    VL_INFO("verilua_final\n");
    execute_final_callback();

#ifdef ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    end_time_for_step = std::chrono::duration_cast<std::chrono::duration<double>>(end.time_since_epoch()).count();
    double time_taken = end_time_for_step - start_time_for_step;
    double percent = lua_time * 100 / time_taken;

    VL_INFO("time_taken: {:.2f} sec   lua_time_taken: {:.2f} sec   lua_overhead: {:.2f}%\n", time_taken, lua_time, percent);
#endif
}

TO_LUA uint64_t bitfield64(uint64_t begin, uint64_t end, uint64_t val) {
    uint64_t mask = ((1ULL << (end - begin + 1)) - 1) << begin;
    return (val & mask) >> begin;
}

TO_LUA void c_simulator_control(long long cmd) {
    // #define vpiStop                  66   /* execute simulator's $stop */
    // #define vpiFinish                67   /* execute simulator's $finish */
    // #define vpiReset                 68   /* execute simulator's $reset */
    // #define vpiSetInteractiveScope   69   /* set simulator's interactive scope */
    vpi_control(cmd);
}

TO_LUA std::string c_get_top_module() {
    vpiHandle iter, top_module;

    // Get module handle 
    iter = vpi_iterate(vpiModule, NULL);
    VL_FATAL(iter != NULL, "No module exist...");

    // Scan the first module (Usually this will be the top module of your DUT)
    top_module = vpi_scan(iter);
    VL_FATAL(top_module != NULL, "Cannot find top module!");

    if(setenv("DUT_TOP", vpi_get_str(vpiName, top_module), 1)) {
        VL_FATAL(false, "setenv error for DUT_TOP");
    }
    
    if(const char* env_val = std::getenv("DUT_TOP")) {
        std::cout << "DUT_TOP is " << env_val << '\n';
        return std::string(env_val);
    }
    else {
        VL_FATAL(false, "Error while getenv(DUT_TOP)");
    }
}


VERILUA_EXPORT void verilua_init(void) {
    // Create lua virtual machine
    L = luaL_newstate();

    // Open all the necessary libraried required by lua script. (e.g. os / math / jit/ bit32 / string / coroutine)
    // Import all libraries if we pass no args in.
    luaL_openlibs(L);

    // Assign sol state
    sol::state_view lua(L);

    // Register functions for lua
    luabridge::getGlobalNamespace(L)
        .beginNamespace("vpi")
            .addFunction("get_top_module", c_get_top_module)
            .addFunction("get_value_by_name", c_get_value_by_name)
            .addFunction("set_value_by_name", c_set_value_by_name)
            .addFunction("simulator_control", c_simulator_control)
            .addFunction("register_time_callback", c_register_time_callback)
            .addFunction("register_edge_callback", c_register_edge_callback)
            .addFunction("register_edge_callback_hdl", c_register_edge_callback_hdl)
            .addFunction("register_edge_callback_hdl_always", c_register_edge_callback_hdl_always)
            .addFunction("register_read_write_synch_callback", c_register_read_write_synch_callback)
            .addFunction("handle_by_name", c_handle_by_name)
            .addFunction("get_value", c_get_value)
            .addFunction("set_value", c_set_value)
            .addFunction("get_value_multi_by_name", c_get_value_multi_by_name)
            .addFunction("set_value_multi_by_name", c_set_value_multi_by_name)
            .addFunction("get_value_multi", c_get_value_multi)
            .addFunction("set_value_multi", c_set_value_multi)
            .addFunction("get_signal_width", c_get_signal_width)
            .addFunction("bitfield64", bitfield64)
        .endNamespace();


    // Register breakpoint function for lua
    // DebugPort is 8818
    const char *debug_enable = getenv("VL_DEBUG");
    if (debug_enable != nullptr && (std::strcmp(debug_enable, "1") == 0 || std::strcmp(debug_enable, "enable") == 0) ) {
        VL_WARN("VL_DEBUG is enable\n");
        luabridge::getGlobalNamespace(L)
            .addFunction("bp", [](lua_State *L){
                    // Execute the Lua code when bp() is called
                    luaL_dostring(L,"require('LuaPanda').start('localhost', 8818); local ret = LuaPanda and LuaPanda.BP and LuaPanda.BP();");
                    return 0;
                }
        );
    } else {
        VL_WARN("VL_DEBUG is disable\n");
        luabridge::getGlobalNamespace(L)
            .addFunction("bp", [](lua_State *L){
                    // Execute the Lua code when bp() is called
                    luaL_dostring(L,"print(\"  \\27[31m [lua_vpi.cpp] ==> Invalid breakpoint! \\27[0m \")");
                    return 0;
                }
        );
    }

    
    const char *VERILUA_HOME = getenv("VERILUA_HOME");
    if (VERILUA_HOME == nullptr) {
        VL_FATAL(false, "Error: VERILUA_HOME environment variable is not set.");
    }
    VL_INFO("VERILUA_HOME is {}\n", VERILUA_HOME);

    std::string INIT_FILE = std::string(VERILUA_HOME) + "/src/lua/verilua/init.lua";
    VL_INFO("INIT_FILE is {}\n", INIT_FILE);

    try {
        lua.safe_script_file(INIT_FILE);
    } catch (const sol::error& err) {
        VL_FATAL(false, "Error calling INIT_FILE: {}, {}", INIT_FILE, err.what());
    }


    // Load lua main script
    const char *LUA_SCRIPT = getenv("LUA_SCRIPT");
    if (LUA_SCRIPT == nullptr) {
        VL_FATAL(false, "Error: LUA_SCRIPT environment variable is not set.");
    }
    VL_INFO("LUA_SCRIPT is {}\n", LUA_SCRIPT);

    try {
        lua.safe_script_file(LUA_SCRIPT);
    } catch (const sol::error& err) {
        VL_FATAL(false, "Error calling LUA_SCRIPT: {}, {}", LUA_SCRIPT, err.what());
    }

    sol::protected_function verilua_init = lua["verilua_init"];
    verilua_init.set_error_handler(lua["debug"]["traceback"]);
    
    auto ret = verilua_init();
    if(!ret.valid()) {
        sol::error  err = ret;
        VL_FATAL(false, "Error calling verilua_init, {}", err.what());
    }

    sim_event = lua["sim_event"];
    sim_event.set_error_handler(lua["debug"]["traceback"]); 
    main_step = lua["lua_main_step"];
    main_step.set_error_handler(lua["debug"]["traceback"]); 

#ifdef ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
    start_time_for_step = std::chrono::duration_cast<std::chrono::duration<double>>(start.time_since_epoch()).count();
#endif

    verilua_is_init = true;
}


void verilua_schedule_loop() {
    sol::state_view lua(L);
    sol::protected_function verilua_schedule_loop = lua["verilua_schedule_loop"];
    
    auto ret = verilua_schedule_loop();
    if(!ret.valid()) {
        sol::error  err = ret;
        VL_FATAL(false, "{}", err.what());
    }
}

// Only for test (LuaJIT FFI)
// "TO_LUA" is necessary since FFI can only access C type function
TO_LUA void hello() {
  printf("hello from C\n");
  fmt::print("hello from fmt:print\n");
}

#ifndef WITHOUT_BOOT_STRAP
void (*vlog_startup_routines[])() = {
    register_start_calllback,
    register_final_calllback, 
    nullptr
};
#endif

// For non-VPI compliant applications that cannot find vlog_startup_routines
VERILUA_EXPORT void vlog_startup_routines_bootstrap() {
    // call each routine in turn like VPI would
    for (auto it = &vlog_startup_routines[0]; *it != nullptr; it++) {
        auto routine = *it;
        routine();
    }
}


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
    if (verilator_simulation_enableTrace == NULL) {
        VL_FATAL(false, "verilator_simulation_enableTrace_impl is NULL");
    }
    verilator_simulation_enableTrace_impl(NULL);
}

TO_LUA void verilator_simulation_disableTrace(void) {
    if (verilator_simulation_disableTrace == NULL) {
        VL_FATAL(false, "verilator_simulation_disableTrace_impl is NULL");
    }
    verilator_simulation_disableTrace_impl(NULL);
}


// ---------------------------------------
// dpi releated functions
// ---------------------------------------
#include "svdpi.h"

TO_LUA void dpi_set_scope(char *str) {
    VL_INFO("set svScope name: {}\n", str);
    const svScope scope = svGetScopeFromName("tb_top");
    VL_FATAL(scope, "scope is NULL");
    svSetScope(scope);
}


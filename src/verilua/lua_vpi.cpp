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
sol::protected_function sim_event; 
sol::protected_function main_step; 

IdPool edge_cb_idpool(50);
std::unordered_map<int, vpiHandle> edge_cb_hdl_map;
std::unordered_map<std::string, long long> handle_cache;

void execute_sim_event(int *id) {
    auto ret = sim_event(*id);
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
    }
}

void execute_sim_event(int id) {
    auto ret = sim_event(id);
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
    }
}

inline void execute_final_callback() {
    { // This is the working filed of LuaRef, when we leave this file, LuaRef will release the allocated memory thus not course segmentation fault when use lua_close(L).
        try {
            luabridge::LuaRef lua_finish_callback = luabridge::getGlobal(L, "finish_callback");
            lua_finish_callback();
        } catch (const luabridge::LuaException& e) {
            fmt::print("[{}:{}] [execute_final_callback] Lua error: {}\n", __FILE__, __LINE__, e.what());
            assert(false);
        }
    }
}

inline void execute_main_step() {
    auto ret = main_step();
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
    }
}

void verilua_main_step() {
    execute_main_step();
}

void verilua_final() {
    execute_final_callback();
}

TO_LUA uint64_t bitfield64(uint64_t begin, uint64_t end, uint64_t val) {
    // printf("bitfield64: val is 0x%lx\n", val);
    uint64_t mask = ((1ULL << (end - begin + 1)) - 1) << begin;
    // printf("bitfield64: return 0x%lx\n", (val & mask) >> begin);
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
    m_assert(iter != NULL, "No module exist...\n");

    // Scan the first module (Usually this will be the top module of your DUT)
    top_module = vpi_scan(iter);
    m_assert(top_module != NULL, "Cannot find top module!\n");

    if(setenv("DUT_TOP", vpi_get_str(vpiName, top_module), 1)) {
        m_assert(false, "setenv error for DUT_TOP");
    }
    
    if(const char* env_val = std::getenv("DUT_TOP")) {
        std::cout << "DUT_TOP is " << env_val << '\n';
        return std::string(env_val);
    }
    else {
        m_assert(false, "Error while getenv(DUT_TOP)");
    }
}


void verilua_init(void) {
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
        luabridge::getGlobalNamespace(L)
            .addFunction("bp", [](lua_State *L){
                    // Execute the Lua code when bp() is called
                    luaL_dostring(L,"require('LuaPanda').start('localhost', 8818); local ret = LuaPanda and LuaPanda.BP and LuaPanda.BP();");
                    return 0;
                }
        );
    } else {
        luabridge::getGlobalNamespace(L)
            .addFunction("bp", [](lua_State *L){
                    // Execute the Lua code when bp() is called
                    luaL_dostring(L,"print(\" Invalid breakpoint! \")");
                    return 0;
                }
        );
    }

    
    const char *VERILUA_HOME = getenv("VERILUA_HOME");
    if (VERILUA_HOME == nullptr) {
        fprintf(stderr, "Error: VERILUA_HOME environment variable is not set.\n");
        exit(EXIT_FAILURE);
    }
    printf("[liblua_vpi.cpp] VERILUA_HOME is %s\n", VERILUA_HOME);

    std::string INIT_FILE = std::string(VERILUA_HOME) + "/src/lua/verilua/init.lua";
    printf("[liblua_vpi.cpp] INIT_FILE is %s\n", INIT_FILE.c_str());

    try {
        lua.safe_script_file(INIT_FILE);
    } catch (const sol::error& err) {
        m_assert(false, "Error :%s", err.what());
    }


    // Load lua main script
    const char *LUA_SCRIPT = getenv("LUA_SCRIPT");
    if (LUA_SCRIPT == nullptr) {
        fprintf(stderr, "Error: LUA_SCRIPT environment variable is not set.\n");
        exit(EXIT_FAILURE);
    }
    printf("[liblua_vpi.cpp] LUA_SCRIPT is %s\n", LUA_SCRIPT);

    try {
        lua.safe_script_file(LUA_SCRIPT);
    } catch (const sol::error& err) {
        m_assert(false, "Error calling %s: %s", LUA_SCRIPT, err.what());
    }

    sol::protected_function verilua_init = lua["verilua_init"];
    verilua_init.set_error_handler(lua["debug"]["traceback"]);
    
    auto ret = verilua_init();
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
    }

    sim_event = lua["sim_event"];
    sim_event.set_error_handler(lua["debug"]["traceback"]); 
    main_step = lua["lua_main_step"];
    main_step.set_error_handler(lua["debug"]["traceback"]); 
}


void verilua_schedule_loop() {
    sol::state_view lua(L);
    sol::protected_function verilua_schedule_loop = lua["verilua_schedule_loop"];
    
    auto ret = verilua_schedule_loop();
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
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
void vlog_startup_routines_bootstrap() {
    // call each routine in turn like VPI would
    for (auto it = &vlog_startup_routines[0]; *it != nullptr; it++) {
        auto routine = *it;
        routine();
    }
}


vl_func_t verilator_next_sim_step_impl;
void alloc_verilator_next_sim_step(vl_func_t func) {
    verilator_next_sim_step_impl = func;
}

TO_LUA void verilator_next_sim_step(void) {
    verilator_next_sim_step_impl();
}
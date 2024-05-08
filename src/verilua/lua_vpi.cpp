#include "lua_vpi.h"
#include "fmt/core.h"
#include "vpi_access.h"
#include "vpi_callback.h"
#include "vpi_user.h"

lua_State *L;
bool verilua_is_init = false;
bool verilua_is_final = false;
sol::protected_function sim_event; 
sol::protected_function main_step; 

IDPool edge_cb_idpool(50);
std::unordered_map<int, vpiHandle> edge_cb_hdl_map;
std::unordered_map<std::string, vpiHandle> handle_cache;
std::unordered_map<vpiHandle, VpiPrivilege_t> handle_cache_rev;
bool enable_vpi_learn = false;

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
    if(!ret.valid()) [[unlikely]] {
        verilua_final();
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
    if(!ret.valid()) [[unlikely]] {
        verilua_final();
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
    if(!ret.valid()) [[unlikely]] {
        verilua_final();
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
    if(verilua_is_final) return;
    if(!verilua_is_init) {
        verilua_is_final = true;
        VL_FATAL(false, "FATAL! and verilua is NOT init yet.");
    }

    VL_INFO("verilua_final\n");
    execute_final_callback();
    verilua_is_final = true;

#ifdef ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    end_time_for_step = std::chrono::duration_cast<std::chrono::duration<double>>(end.time_since_epoch()).count();
    double time_taken = end_time_for_step - start_time_for_step;
    double percent = lua_time * 100 / time_taken;

    VL_INFO("time_taken: {:.2f} sec   lua_time_taken: {:.2f} sec   lua_overhead: {:.2f}%\n", time_taken, lua_time, percent);
#endif

    // Simulation end here...
    vpi_control(vpiFinish);
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
        VL_INFO("DUT_TOP is {}\n", env_val);
        return std::string(env_val);
    }
    else {
        VL_FATAL(false, "Error while getenv(DUT_TOP)");
    }
}

static void sigabrt_handler(int signal) {
    if (!verilua_is_final) {
        verilua_final();
    }
    VL_WARN(R"(
---------------------------------------------------------------------
----   Verilua get <SIGABRT>, the program will terminate...      ----
---------------------------------------------------------------------
)");
    exit(0); // we should successfully exit simulation no matter what lead to the simulation failed.
}

VERILUA_EXPORT void verilua_init(void) {
    signal(SIGABRT, sigabrt_handler);

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

    // Check is vpi learn is enable
    const char *_enable_vpi_learn = getenv("VPI_LEARN");
    if (_enable_vpi_learn != nullptr && (std::strcmp(_enable_vpi_learn, "1") == 0 || std::strcmp(_enable_vpi_learn, "enable") == 0) ) {
        enable_vpi_learn = true;
    }

    const char *DUT_TOP = getenv("DUT_TOP");
    if(DUT_TOP == nullptr) {
        auto dut_top = c_get_top_module();
        VL_WARN("DUT_TOP is not set, automatically set DUT_TOP as {}\n", dut_top);
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

    sol::protected_function test_func = lua["test_func"];
    auto start1 = std::chrono::high_resolution_clock::now();
    test_func();
    auto end1 = std::chrono::high_resolution_clock::now();
    double start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start1.time_since_epoch()).count();
    double end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end1.time_since_epoch()).count();
    VL_INFO("test_func time is {} us\n", (end_time - start_time) * 1000 * 1000);

#ifdef ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
    start_time_for_step = std::chrono::duration_cast<std::chrono::duration<double>>(start.time_since_epoch()).count();
#endif

    verilua_is_init = true;
}


TO_VERILATOR void verilua_schedule_loop() {
    sol::state_view lua(L);
    sol::protected_function verilua_schedule_loop = lua["verilua_schedule_loop"];
    
    auto ret = verilua_schedule_loop();
    if(!ret.valid()) [[unlikely]] {
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
// dpi releated functions
// ---------------------------------------
#include "svdpi.h"

TO_LUA void dpi_set_scope(char *str) {
    VL_INFO("set svScope name: {}\n", str);
    const svScope scope = svGetScopeFromName(str);
    VL_FATAL(scope, "scope is NULL");
    svSetScope(scope);
}


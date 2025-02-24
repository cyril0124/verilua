#pragma once

#include "lua.hpp"
#include "svdpi.h"
#include "vpi_user.h"
#include "sol/sol.hpp"

#include <cassert>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <csignal>
#include <memory>
#include <string>
#include <vector>
#include <queue>
#include <mutex>
#include <fstream>
#include <iostream>
#include <unordered_set>
#include <sys/types.h>
#include <chrono>

#ifdef VL_DEF_OPT_USE_BOOST_UNORDERED
#include "boost_unordered.hpp"
#define UNORDERED_SET boost::unordered_flat_set
#define UNORDERED_MAP boost::unordered_flat_map
#else
#include <unordered_map>
#define UNORDERED_SET std::unordered_set
#define UNORDERED_MAP std::unordered_map
#endif

#define ANSI_COLOR_RED     "\x1b[31m"
#define ANSI_COLOR_GREEN   "\x1b[32m"
#define ANSI_COLOR_YELLOW  "\x1b[33m"
#define ANSI_COLOR_BLUE    "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN    "\x1b[36m"
#define ANSI_COLOR_RESET   "\x1b[0m"

#define VL_DEBUG(...) \
    do { \
        static bool __enable_debug = [] { \
            const char* env_var = std::getenv("VL_DEBUG_C"); \
            return env_var != nullptr && std::string(env_var) == "1"; \
        }(); \
        if (__enable_debug) { \
            printf("[%s:%s:%d] [%sDEBUG%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_RED, ANSI_COLOR_RESET); \
            printf(__VA_ARGS__); \
            fflush(stdout); \
        } \
    } while(0)

#ifdef DEBUG
#define VL_STATIC_DEBUG(...) \
    do { \
        printf("[%s:%s:%d] [%sSTATIC_DEBUG%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_RED, ANSI_COLOR_RESET); \
        printf(__VA_ARGS__); \
    } while(0)
#else
#define VL_STATIC_DEBUG(...)
#endif

#define VL_INFO(...) \
    do { \
        printf("[%s:%s:%d] [%sINFO%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET); \
        printf(__VA_ARGS__); \
    } while(0)

#define VL_WARN(...) \
    do { \
        printf("[%s:%s:%d] [%sWARN%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_YELLOW, ANSI_COLOR_RESET); \
        printf(__VA_ARGS__); \
    } while(0)

#define VL_FATAL(cond, ...) \
    do { \
        if (!(cond)) { \
            printf("\n"); \
            printf("[%s:%s:%d] [%sFATAL%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_RED, ANSI_COLOR_RESET); \
            printf(__VA_ARGS__ __VA_OPT__(,) "A fatal error occurred without a message.\n"); \
            printf("\n"); \
            fflush(stdout); \
            fflush(stderr); \
            abort(); \
        } \
    } while(0)

#define ENV_IS_ENABLE(env_enable_str) env_enable_str != nullptr && (std::strcmp(env_enable_str, "1") == 0 || std::strcmp(env_enable_str, "enable") == 0)

// Mark the functions that will be used by Lua via ffi
#define TO_LUA extern "C"

// Mark the functions that will be used by verilator simulator
#define TO_VERILATOR

// Mark the functions that will be used by embeding verilua into other simulation enviroment
#define VERILUA_EXPORT extern "C"

// Mark the functions that will be privately used by the verilua library
#define VERILUA_PRIVATE

using TaskID = uint32_t;

enum class VpiPermission {
    READ,
    WRITE,
};

enum class EdgeType : int {
    POSEDGE = 0,
    NEGEDGE = 1,
    EDGE = 2
};

enum class EdgeValue : int {
    LOW = 0,
    HIGH = 1,
    DONTCARE = 2
};

struct EdgeCbData {
    TaskID      task_id;
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};

struct CallbackInfo {
    TaskID task_id;
    EdgeType edge_type;
};

class IDPool {
private:
    UNORDERED_SET<uint64_t> allocated_ids;  
    std::queue<uint64_t> available_ids;

public:
    IDPool(uint64_t size) {
        for (uint64_t i = 0; i < size; ++i) {
            available_ids.push(i);
        }
    }

    ~IDPool() {
        allocated_ids.clear();
        std::queue<uint64_t> empty;
        std::swap(available_ids, empty);
    }

    uint64_t alloc_id() {
        VL_FATAL(!available_ids.empty(), "No more IDs available");

        uint64_t id = available_ids.front();
        available_ids.pop();
        allocated_ids.insert(id);

        return id;
    }

    void release_id(uint64_t id) {
        VL_FATAL(allocated_ids.find(id) != allocated_ids.end(), "Invalid ID => %ld", id);

        allocated_ids.erase(id);
        available_ids.push(id);
    }
};

typedef union {
    uint64_t u64;
    uint32_t u32[2];
} SimpleVecValue;

// Singletone object of the entire Verilua environment
class VeriluaEnv {
public:
    VeriluaEnv(const VeriluaEnv&) = delete;
    VeriluaEnv& operator=(const VeriluaEnv&) = delete;

    static VeriluaEnv& get_instance() {
        static VeriluaEnv instance;
        return instance;
    }

    bool initialized = false;
    bool finalized = false;

    bool has_start_cb = false;
    bool has_final_cb = false;

    double lua_time = 0.0;
    double start_time = 0.0;
    double end_time = 0.0;

    lua_State* L;
    std::unique_ptr<sol::state_view> lua;
    sol::protected_function sim_event;
    sol::protected_function main_step;

    IDPool edge_cb_idpool; // Edge callback id pool for cbValueChange
    UNORDERED_MAP<uint64_t, vpiHandle> edge_cb_hdl_map;
    UNORDERED_MAP<std::string, vpiHandle> hdl_cache;
    UNORDERED_MAP<vpiHandle, VpiPermission> hdl_cache_rev;

#ifdef VL_DEF_OPT_MERGE_CALLBACK
    #include "gen_new_sim_event.h"

    UNORDERED_MAP<vpiHandle, std::vector<TaskID>> pending_posedge_cb_map;
    UNORDERED_MAP<vpiHandle, std::vector<TaskID>> pending_negedge_cb_map;
    UNORDERED_MAP<vpiHandle, std::vector<TaskID>> pending_edge_cb_map;
#else
    UNORDERED_MAP<vpiHandle, std::vector<CallbackInfo>> pending_edge_cb_map;
#endif

#ifdef VL_DEF_OPT_VEC_SIMPLE_ACCESS
    UNORDERED_MAP<vpiHandle, SimpleVecValue> vec_value_cache; // A cache that can be used to prevent repeated access of some signal during the same simulation step
#endif

#ifdef IVERILOG
    bool resolve_x_as_zero = true; // whether resolve x as zero
#endif

    void initialize();
    void finalize();

    std::string handle_to_name(vpiHandle handle) {
        for(auto &pair : hdl_cache) {
            if(pair.second == handle) {
                return pair.first;
            }
        }
        return std::string("Unknown");
    }
private:
    VeriluaEnv() : edge_cb_idpool(100000) {};
};

VERILUA_PRIVATE inline void execute_sim_event(TaskID id) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event(id);

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, %s", err.what());
    }
}

// Execute the main_step function in a way that is safe to be called.
// If the main_step function throws an error, the error will be caught 
// and the Verilua environment will be finalized.
VERILUA_PRIVATE inline void execute_main_step() {
    auto &env = VeriluaEnv::get_instance();
    VL_FATAL(env.initialized, "`execute_main_step` called before initialize!");

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.main_step();

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error err = ret;
        VL_FATAL(false, "Error calling main_step, %s", err.what());
    }
}

// Same as execute_main_step() while error will not cause the program to crash
VERILUA_PRIVATE inline void execute_main_step_safe() {
    static bool has_error = false;

    if (has_error) {
        VL_WARN("[execute_main_step_safe] `has_error` is `true`! Program should be terminated! Nothing will be done in `Verilua`...\n");
        return;
    }

    auto &env = VeriluaEnv::get_instance();
    if(!env.initialized) {
        VL_WARN("`execute_main_step_safe` called before initialize!\n");
        return;
    }

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.main_step();

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        has_error = true;
        sol::error err = ret;
        VL_WARN("Error calling main_step, %s", err.what());
    }
}

// ----------------------------------------------------------------------------------------------------------
//  Export functions for embeding Verilua inside other simulation environments
//  Make sure to use verilua_init() at the beginning of the simulation and use verilua_final() at the end of the simulation.
//  The verilua_main_step() should be invoked at the beginning of each simulation step.
// ----------------------------------------------------------------------------------------------------------
VERILUA_EXPORT void verilua_init();
VERILUA_EXPORT void verilua_final();
VERILUA_EXPORT void verilua_main_step();
VERILUA_EXPORT void verilua_main_step_safe();

// In some cases you may need to call this function manually since the simulation environment may not call it automatically(e.g. Verilator).
// While in most cases you don't need to call this function manually.
VERILUA_EXPORT void vlog_startup_routines_bootstrap();

typedef std::function<void(void*)> VerilatorFunc;

namespace Verilua {
    enum class VeriluaMode { 
        Normal = 1, 
        Step = 2, 
        Dominant = 3
    };

    void alloc_verilator_func(VerilatorFunc func, const std::string& name);
}

TO_VERILATOR void verilua_schedule_loop();
#pragma once

#include "lua.hpp"
#include "vpi_user.h"
#include "fmt/core.h"
#include "sol/sol.hpp"
#include "boost/unordered_map.hpp"
#include "boost/unordered_set.hpp"

#include <cassert>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <csignal>
#include <string>
#include <vector>
#include <queue>
#include <mutex>
#include <fstream>
#include <iostream>
#include <sys/types.h>


#define ANSI_COLOR_RED     "\x1b[31m"
#define ANSI_COLOR_GREEN   "\x1b[32m"
#define ANSI_COLOR_YELLOW  "\x1b[33m"
#define ANSI_COLOR_BLUE    "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN    "\x1b[36m"
#define ANSI_COLOR_RESET   "\x1b[0m"

#define VL_INFO(...) \
    do { \
        fmt::print("[{}:{}:{}] [{}INFO{}] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET); \
        fmt::print(__VA_ARGS__); \
    } while(0)

#define VL_WARN(...) \
    do { \
        fmt::print("[{}:{}:{}] [{}WARN{}] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_YELLOW, ANSI_COLOR_RESET); \
        fmt::print(__VA_ARGS__); \
    } while(0)

#define VL_FATAL(cond, ...) \
    do { \
        if (!(cond)) { \
            fmt::println("\n"); \
            fmt::print("[{}:{}:{}] [{}FATAL{}] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_RED, ANSI_COLOR_RESET); \
            fmt::println(__VA_ARGS__ __VA_OPT__(,) "A fatal error occurred without a message.\n"); \
            fflush(stdout); \
            fflush(stderr); \
            abort(); \
        } \
    } while(0)

#define ENV_IS_ENABLE(env_enable_str) env_enable_str != nullptr && (std::strcmp(env_enable_str, "1") == 0 || std::strcmp(env_enable_str, "enable") == 0)

#define TO_LUA extern "C"
#define TO_VERILATOR
#define VERILUA_EXPORT extern "C"
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

struct LuaStateDeleter {
    void operator()(lua_State* L) const {
        lua_close(L);
    }
};

struct EdgeCbData {
    TaskID      task_id;
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};


class IDPool {
private:
    boost::unordered_set<uint64_t> allocated_ids;  
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
        VL_FATAL(allocated_ids.find(id) != allocated_ids.end(), "Invalid ID => {}", id);

        allocated_ids.erase(id);
        available_ids.push(id);
    }
};


VERILUA_EXPORT void verilua_init();
VERILUA_EXPORT void verilua_main_step();
VERILUA_EXPORT void verilua_final();
VERILUA_EXPORT void vlog_startup_routines_bootstrap();


TO_VERILATOR void verilua_schedule_loop();

typedef void (*VerilatorFunc)(void *);
namespace Verilua {
    enum class VeriluaMode { 
        Normal = 1, 
        Step = 2, 
        Dominant = 3
    };

    void alloc_verilator_func(VerilatorFunc func, const std::string& name);
}


// used inside the verilua lib (cpp side)
VERILUA_PRIVATE void execute_final_callback();
VERILUA_PRIVATE void execute_sim_event(TaskID id);

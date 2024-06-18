#pragma once

#include "lua.hpp"
#include <LuaBridge.h>
#include <fmt/core.h>
#include <sol/sol.hpp>


#include "vpi_user.h"

#include "assert.h"
#include "stdio.h"

#include <cstdlib>
#include <csignal>
#include <unordered_map>
#include <unordered_set>
#include <queue>
#include <mutex>


#define ANSI_COLOR_RED     "\x1b[31m"
#define ANSI_COLOR_GREEN   "\x1b[32m"
#define ANSI_COLOR_YELLOW  "\x1b[33m"
#define ANSI_COLOR_BLUE    "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN    "\x1b[36m"
#define ANSI_COLOR_RESET   "\x1b[0m"

#define VL_INFO(...) \
    do { \
        fmt::print("[{}:{}:{}] [{}INFO{}] ", __FILE__, __func__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET); \
        fmt::print(__VA_ARGS__); \
    } while(0)

#define VL_WARN(...) \
    do { \
        fmt::print("[{}:{}:{}] [{}WARN{}] ", __FILE__, __func__, __LINE__, ANSI_COLOR_YELLOW, ANSI_COLOR_RESET); \
        fmt::print(__VA_ARGS__); \
    } while(0)

#define VL_FATAL(cond, ...) \
    do { \
        if (!(cond)) { \
            fmt::println("\n"); \
            fmt::print("[{}:{}:{}] [{}FATAL{}] ", __FILE__, __func__, __LINE__, ANSI_COLOR_RED, ANSI_COLOR_RESET); \
            fmt::println(__VA_ARGS__ __VA_OPT__(,) "A fatal error occurred without a message.\n"); \
            fflush(stdout); \
            fflush(stderr); \
            abort(); \
        } \
    } while(0)

#define TO_LUA extern "C"
#define TO_VERILATOR
#define VERILUA_EXPORT extern "C"
#define VERILUA_PRIVATE

struct EdgeCbData {
    int       task_id;
    int       expected_value;
    long long cb_hdl_id;
};


enum class VpiPermission {
    READ,
    WRITE,
};


class IDPool {
private:
    std::unordered_set<uint64_t> allocated_ids;  
    std::queue<uint64_t> available_ids;

public:
    IDPool(uint64_t size) {
        for (uint64_t i = 0; i < size; ++i) {
            available_ids.push(i);
        }
    }

    uint64_t alloc_id() {
        if (available_ids.empty()) {
            throw std::runtime_error("No more IDs available");
        }

        uint64_t id = available_ids.front();
        available_ids.pop();
        allocated_ids.insert(id);
        // printf("alloc:%d\n", id);

        return id;
    }

    void release_id(uint64_t id) {
        if (allocated_ids.find(id) == allocated_ids.end()) {
            throw std::runtime_error("Invalid ID");
        }
        // printf("release:%d\n",id);

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

    void alloc_verilator_func(VerilatorFunc func, std::string name);
}


// used inside the verilua lib (cpp side)
VERILUA_PRIVATE void execute_final_callback();
VERILUA_PRIVATE void execute_sim_event(int *id);
VERILUA_PRIVATE void execute_sim_event(int id);

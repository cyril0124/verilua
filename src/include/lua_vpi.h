#ifndef __LUA_VPI_H__
#define __LUA_VPI_H__

#include "lua.hpp"
#include <LuaBridge.h>
#include <sol.hpp>
#include <fmt/core.h>

#include "vpi_user.h"

#include "assert.h"
#include "stdio.h"

#include <cstdlib>
#include <unordered_map>
#include <unordered_set>
#include <queue>

#define ANSI_COLOR_RED     "\x1b[31m"
#define ANSI_COLOR_GREEN   "\x1b[32m"
#define ANSI_COLOR_YELLOW  "\x1b[33m"
#define ANSI_COLOR_BLUE    "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN    "\x1b[36m"
#define ANSI_COLOR_RESET   "\x1b[0m"

#define m_assert(cond, ...) \
    do { \
        if (!(cond)) { \
            printf(ANSI_COLOR_BLUE); \
            printf(__VA_ARGS__); \
            printf("\n[%s:%s:%d] ", __FILE__, __FUNCTION__, __LINE__); \
            printf(ANSI_COLOR_MAGENTA);\
            execute_final_callback(); \
            printf(ANSI_COLOR_RESET);\
            fflush(stdout); \
            fflush(stderr); \
            assert(cond); \
        } \
    } while (0)

#define TO_LUA extern "C"


typedef struct {
    int       task_id;
    int       expected_value;
    int       cb_hdl_id;
} edge_cb_data_t;



class IdPool {
private:
    std::unordered_set<int> allocated_ids;  
    std::queue<int> available_ids;

public:
    IdPool(int size) {
        for (int i = 0; i < size; ++i) {
            available_ids.push(i);
        }
    }

    int alloc_id() {
        if (available_ids.empty()) {
            throw std::runtime_error("No more IDs available");
        }

        int id = available_ids.front();
        available_ids.pop();
        allocated_ids.insert(id);
        // printf("alloc:%d\n", id);

        return id;
    }

    void release_id(int id) {
        if (allocated_ids.find(id) == allocated_ids.end()) {
            throw std::runtime_error("Invalid ID");
        }
        // printf("release:%d\n",id);

        allocated_ids.erase(id);
        available_ids.push(id);
    }
};

// TODO: add prefix: verilua
void verilua_init();
void verilua_main_step();
void verilua_final();
void vlog_startup_routines_bootstrap();


// used inside the verilua lib
void execute_final_callback();
void execute_sim_event(int *id);
void execute_sim_event(int id);

#endif // __LUA_VPI_H__
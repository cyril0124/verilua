#pragma once

#include "boost_unordered.hpp"
#include "fmt/core.h"
#include "vpi_user.h"
#include <condition_variable>
#include <csignal>
#include <cstdint>
#include <memory>
#include <queue>
#include <string>
#include <thread>
#include <vector>

#ifndef FALSE
#define FALSE 0
#endif

#ifndef TRUE
#define TRUE 1
#endif

#define ANSI_COLOR_RED "\x1b[31m"
#define ANSI_COLOR_GREEN "\x1b[32m"
#define ANSI_COLOR_YELLOW "\x1b[33m"
#define ANSI_COLOR_BLUE "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN "\x1b[36m"
#define ANSI_COLOR_RESET "\x1b[0m"

#define VL_INFO(...)                                                                                                                                                                                                                                                                                                                                                                                           \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        fmt::print("[{}:{}:{}] [{}INFO{}] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                          \
        fmt::print(__VA_ARGS__);                                                                                                                                                                                                                                                                                                                                                                               \
    } while (0)

#define VL_WARN(...)                                                                                                                                                                                                                                                                                                                                                                                           \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        fmt::print("[{}:{}:{}] [{}WARN{}] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_YELLOW, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                           \
        fmt::print(__VA_ARGS__);                                                                                                                                                                                                                                                                                                                                                                               \
    } while (0)

#define VL_FATAL(cond, ...)                                                                                                                                                                                                                                                                                                                                                                                    \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        if (!(cond)) {                                                                                                                                                                                                                                                                                                                                                                                         \
            fmt::println("\n");                                                                                                                                                                                                                                                                                                                                                                                \
            fmt::print("[{}:{}:{}] [{}FATAL{}] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_RED, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                         \
            fmt::println(__VA_ARGS__ __VA_OPT__(, ) "A fatal error occurred without a message.\n");                                                                                                                                                                                                                                                                                                            \
            fflush(stdout);                                                                                                                                                                                                                                                                                                                                                                                    \
            fflush(stderr);                                                                                                                                                                                                                                                                                                                                                                                    \
            abort();                                                                                                                                                                                                                                                                                                                                                                                           \
        }                                                                                                                                                                                                                                                                                                                                                                                                      \
    } while (0)

// Exported from rust side
extern "C" {
void wellen_initialize(const char *filename);
void wellen_finalize();

uint64_t wellen_get_max_index();
uint64_t wellen_get_time_from_index(uint64_t index);
uint64_t wellen_get_index_from_time(uint64_t time);

char *wellen_get_value_str(void *handle, uint64_t time_table_idx);
uint32_t wellen_get_int_value(void *handle, uint64_t time_table_index);

void wellen_vpi_get_value(void *handle, uint64_t time, p_vpi_value value_p);
void wellen_vpi_get_value_from_index(void *handle, uint64_t time_table_idx, p_vpi_value value_p);

void *wellen_vpi_handle_by_name(const char *name);
PLI_INT32 wellen_vpi_get(PLI_INT32 property, void *handle);
PLI_BYTE8 *wellen_vpi_get_str(PLI_INT32 property, void *object);
void *wellen_vpi_iterate(PLI_INT32 type, void *refHandle);
}

using CursorTime_t = uint64_t;
using TaskId_t     = uint64_t;
using vpiHandleRaw = PLI_UINT32;
using vpiCbFunc    = PLI_INT32 (*)(struct t_cb_data *);

struct ValueCbInfo {
    std::shared_ptr<s_cb_data> cbData;
#ifdef USE_FSDB
    vpiHandle handle;
    size_t bitSize;
    uint32_t bitValue;
#else
    vpiHandle handle;
#endif
    std::string valueStr;
};

struct WaveCursor {
    CursorTime_t time;
    CursorTime_t maxTime;

    uint64_t index;
    uint64_t maxIndex;

#ifndef USE_FSDB
    void updateTime(uint64_t time) {
        this->time  = time;
        this->index = wellen_get_index_from_time(time);
    }

    void updateIndex(uint64_t index) {
        this->index = index;
        this->time  = wellen_get_time_from_index(index);
    }
#endif
};

typedef struct {
    std::string name;
    vpiHandle vpiHdl;
    size_t bitSize;

    // Used by JIT-like feature
    uint64_t readCnt = 0;
    std::thread optThread;
    bool doOpt       = false;
    bool optFinish   = false;
    bool continueOpt = false;
    std::vector<uint32_t> optValueVec;
    uint64_t optFinishIdx = 0;
    std::condition_variable cv;
    std::mutex mtx;
} SignalHandle, *SignalHandlePtr;

void wave_vpi_init(const char *filename);
void wave_vpi_loop();

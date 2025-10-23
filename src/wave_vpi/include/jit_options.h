#pragma once

#include <fmt/core.h>
#include <thread>

#define JTT_DEFAULT_HOT_ACCESS_THRESHOLD 30
#define JIT_DEFAULT_COMPILE_WINDOW_SIZE 200000
#define JIT_DEFAULT_RECOMPILE_WINDOW_SIZE 200000

// Maximum threads(default) that are allowed to be run for JIT optimization.
#ifdef USE_FSDB
#define JIT_DEFAULT_MAX_OPT_THREADS 20
#else
#define JIT_DEFAULT_MAX_OPT_THREADS 900 // Maximum threads(default) that are allowed to be run for JIT optimization.
#endif

namespace jit_options {
extern bool enableJIT;
extern bool verboseJIT;
extern std::atomic<uint32_t> optThreadCnt;
extern uint32_t maxOptThreads;
extern uint64_t hotAccessThreshold;
extern uint64_t compileWindowSize;
extern uint64_t recompileWindowSize;

struct Statistic_t {
    double totalReadTime;
    uint64_t readFromOpt;
    uint64_t readFromNormal;
    uint64_t unOptimizableRead;
    double readFromOptTime;
    double readFromNormalTime;
    uint64_t optThreadNotEnough;
    std::atomic<uint32_t> jitOptTaskCnt;
    std::atomic<uint32_t> jitOptTaskFirstFinishCnt;
};

using Statistic = Statistic_t;

extern Statistic statistic;

void initialize();
void reportStatistic();
}; // namespace jit_options

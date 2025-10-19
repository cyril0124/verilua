#pragma once

#include <fmt/core.h>
#include <thread>

#define JTT_DEFAULT_HOT_ACCESS_THRESHOLD 10
#define JIT_DEFAULT_COMPILE_WINDOW_SIZE 200000
#define JIT_DEFAULT_RECOMPILE_WINDOW_SIZE 200000
#define JIT_DEFAULT_MAX_OPT_THREADS 20 // Maximum threads(default) that are allowed to be run for JIT optimization.

namespace jit_options {
extern bool enableJIT;
extern std::atomic<uint32_t> optThreadCnt;
extern uint32_t maxOptThreads;
extern uint64_t hotAccessThreshold;
extern uint64_t compileThreshold;
extern uint64_t compileWindowSize;
extern uint64_t recompileWindowSize;

typedef struct {
    double totalReadTime;
    uint64_t readFromOpt;
    uint64_t readFromNormal;
    double readFromOptTime;
    double readFromNormalTime;
    uint64_t optThreadNotEnough;
} Statistic;

extern Statistic statistic;

void initialize();
void reportStatistic();
}; // namespace jit_options

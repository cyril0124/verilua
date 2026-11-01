#pragma once

#include "boost_unordered.hpp"
#include "jit_options.h"
#include <cinttypes>
#include <cstdio>
#include <wave_vpi.h>

#if __cplusplus >= 201703L
#include <charconv>
#endif

// Fast integer-to-string conversion for JIT hot path.
// Uses std::to_chars (C++17) when available, falls back to snprintf.
inline char *uint32_to_hex_str(char *buf, size_t buf_size, uint32_t value) {
#if __cplusplus >= 201703L
    auto [ptr, ec] = std::to_chars(buf, buf + buf_size, value, 16);
    *ptr           = '\0';
#else
    snprintf(buf, buf_size, "%x", value);
#endif
    return buf;
}

inline char *uint32_to_dec_str(char *buf, size_t buf_size, uint32_t value) {
#if __cplusplus >= 201703L
    auto [ptr, ec] = std::to_chars(buf, buf + buf_size, value);
    *ptr           = '\0';
#else
    snprintf(buf, buf_size, "%u", value);
#endif
    return buf;
}

namespace vpi_compat {

// Set by the CLI before waveform initialization.
inline bool ignoreWrites = false;

// During cbValueChange, the triggering handle reads "current"; other handles
// read "before". Outside callbacks or after a cursor jump, all reads are current.
// Reading either view leaves the cursor and simulation time unchanged.
//
// Example: count changes 5 -> 6 at tick 100; no changes occur between 90 and 100.
// clang-format off
// tick     90                  100                 110
//           |                   |                   |
// clock                         +-------------------+
//           --------------------+                   +-----
// count     ========= 5 ========|========== 6 ============
// sample    A                 B C D
//
//         before                     current (JIT buffer)
// FSDB    B: 99 (t - 1 tick)          D: 101 (t + 1 tick)
// Wellen  A: 90 (index i - 1)         C: 100 (index i)
// clang-format on
//
// optValueVec caches current snapshots, not before values. Before reads bypass
// that cache; FSDB bounds current reader sampling at the waveform end.
inline vpiHandle samplingEventObject = nullptr;

extern bool vpiControlTerminate;
extern std::string terminateReason;

extern std::unique_ptr<s_cb_data> startOfSimulationCb;
extern std::unique_ptr<s_cb_data> endOfSimulationCb;

extern boost::unordered_flat_map<uint64_t, std::vector<std::shared_ptr<t_cb_data>>> timeCbMap;
extern std::vector<std::pair<uint64_t, std::shared_ptr<t_cb_data>>> willAppendTimeCbQueue;

// The nextSimTimeQueue is a queue of callbacks that will be called at the next simulation time.
extern std::vector<std::shared_ptr<t_cb_data>> nextSimTimeQueue;
extern std::vector<std::shared_ptr<t_cb_data>> willAppendNextSimTimeQueue;

extern boost::unordered_flat_map<vpiHandleRaw, ValueCbInfo> valueCbMap;
extern std::vector<std::pair<vpiHandleRaw, ValueCbInfo>> willAppendValueCb;
extern std::vector<vpiHandleRaw> willRemoveValueCb;

// The vpiHandleAllocator is a counter that counts the number of vpiHandles allocated which make it easy to provide unique vpiHandle values.
extern vpiHandleRaw vpiHandleAllcator;

void startOfSimulation();

void endOfSimulation();

inline void appendTimeCb() {
    for (auto &cbPair : willAppendTimeCbQueue) {
        auto targetIdx = cbPair.first;
        auto cb        = cbPair.second;
        if (timeCbMap.find(targetIdx) != timeCbMap.end()) {
            timeCbMap[targetIdx].emplace_back(cb);
        } else {
            timeCbMap[targetIdx] = {cb};
        }
    }
    willAppendTimeCbQueue.clear();
}

inline void appendValueCb() {
    if (!willAppendValueCb.empty()) {
        for (auto &cb : willAppendValueCb) {
            valueCbMap[cb.first] = cb.second;
            // fmt::println("append {}", cb.first);
        }
        willAppendValueCb.clear();
    }
}

inline void removeValueCb() {
    if (!willRemoveValueCb.empty()) {
        for (auto &cb : willRemoveValueCb) {
            valueCbMap.erase(cb);
            // fmt::println("remove {}", cb);
        }
        willRemoveValueCb.clear();
    }
}

inline void appendNextSimTimeCb() {
    for (auto &cb : willAppendNextSimTimeQueue) {
        nextSimTimeQueue.emplace_back(cb);
        // fmt::println("append nextSimTimeCb");
    }
    willAppendNextSimTimeQueue.clear();
}

#ifdef USE_FSDB
std::string fsdbGetBinStr(vpiHandle object);
uint32_t fsdbGetSingleBitValue(vpiHandle object);
#else
std::string _wellen_get_value_str(vpiHandle sigHdl);
#endif
}; // namespace vpi_compat

#pragma once

#include "boost_unordered.hpp"
#include "jit_options.h"
#include <wave_vpi.h>

namespace vpi_compat {

extern bool vpiControlTerminate;
extern std::string terminateReason;

extern std::unique_ptr<s_cb_data> startOfSimulationCb;
extern std::unique_ptr<s_cb_data> endOfSimulationCb;

extern std::queue<std::pair<uint64_t, std::shared_ptr<t_cb_data>>> timeCbQueue;
extern std::vector<std::pair<uint64_t, std::shared_ptr<t_cb_data>>> willAppendTimeCbQueue;

// The nextSimTimeQueue is a queue of callbacks that will be called at the next simulation time.
extern std::vector<std::shared_ptr<t_cb_data>> nextSimTimeQueue;
extern std::vector<std::shared_ptr<t_cb_data>> willAppendNextSimTimeQueue;

extern boost::unordered_flat_map<vpiHandleRaw, ValueCbInfo> valueCbMap;
extern std::vector<std::pair<vpiHandleRaw, ValueCbInfo>> willAppendValueCb;
extern std::vector<vpiHandleRaw> willRemoveValueCb;

// The vpiHandleAllocator is a counter that counts the number of vpiHandles allocated which make it easy to provide unique vpiHandle values.
extern vpiHandleRaw vpiHandleAllcator;

inline void endOfSimulation() {
    static bool called = false;

    if (endOfSimulationCb && !called) {
        called = true;
#ifndef USE_FSDB
        wellen_finalize();
#endif
        endOfSimulationCb->cb_rtn(endOfSimulationCb.get());
#ifdef PROFILE_JIT
        jit_options::reportStatistic();
#endif
    }
}

inline void appendTimeCb() {
    for (auto &cb : willAppendTimeCbQueue) {
        timeCbQueue.push(cb);
        // fmt::println("append appendTimeCb");
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

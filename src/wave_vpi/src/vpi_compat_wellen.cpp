#include "jit_options.h"
#include "vpi_compat.h"
#include "wave_vpi.h"
#include <unordered_map>
#include <unordered_set>

// Unsupported:
//      vpi_put_value(handle, &v, NULL, vpiNoDelay); // wave_vpi is considered a read-only waveform simulate backend in verilua
//
// Supported:
//      OK => vpi_get_value(handle, &v);
//      OK => vpi_get_str(vpiType, actual_handle);
//      OK => vpi_get(vpiSize, actual_handle);
//      OK => vpi_iterate(vpiModule, ...)
//      OK => vpi_scan(iterator)
//      OK => vpi_handle_by_name(name)
//      OK => vpi_release_handle()
//      OK => vpi_free_object()
//      vpi_register_cb()
//          -> cbStartOfSimulation OK
//          -> cbEndOfSimulation   OK
//          -> cbValueChange       OK
//          -> cbAfterDelay        OK
//      vpi_remove_cb()            OK
//
// TODO:
//      vpi_handle_by_index

extern WaveCursor cursor;

namespace vpi_compat {

bool vpiControlTerminate    = false;
std::string terminateReason = "Unknown";

std::unique_ptr<s_cb_data> startOfSimulationCb = nullptr;
std::unique_ptr<s_cb_data> endOfSimulationCb   = nullptr;

boost::unordered_flat_map<uint64_t, std::vector<std::shared_ptr<t_cb_data>>> timeCbMap;
std::vector<std::pair<uint64_t, std::shared_ptr<t_cb_data>>> willAppendTimeCbQueue;

// The nextSimTimeQueue is a queue of callbacks that will be called at the next simulation time.
std::vector<std::shared_ptr<t_cb_data>> nextSimTimeQueue;
std::vector<std::shared_ptr<t_cb_data>> willAppendNextSimTimeQueue;

boost::unordered_flat_map<vpiHandleRaw, ValueCbInfo> valueCbMap;
std::vector<std::pair<vpiHandleRaw, ValueCbInfo>> willAppendValueCb;
std::vector<vpiHandleRaw> willRemoveValueCb;

// The vpiHandleAllocator is a counter that counts the number of vpiHandles allocated which make it easy to provide unique vpiHandle values.
vpiHandleRaw vpiHandleAllcator = 0;

// Handle sets used as a lightweight RTTI layer for opaque `vpiHandle`.
// This prevents us from decoding a module/iterator handle as a signal handle.
std::unordered_set<void *> signalHandleSet;
std::unordered_set<void *> moduleHandleSet;
std::unordered_set<void *> iteratorHandleSet;
std::unordered_map<void *, PLI_INT32> iteratorTypeMap;

struct ModuleHandle_t {
    void *wellenModuleHandle;
};
using ModuleHandle    = ModuleHandle_t;
using ModuleHandlePtr = ModuleHandle_t *;

// boost::unordered_flat_map<vpiHandle, std::string> hdlToNameMap; // For debug purpose

void startOfSimulation() {
    if (startOfSimulationCb != nullptr) {
        startOfSimulationCb->cb_rtn(startOfSimulationCb.get());
    }
}

void endOfSimulation() {
    static bool called = false;

    if (endOfSimulationCb && !called) {
        called = true;
        wellen_finalize();
        endOfSimulationCb->cb_rtn(endOfSimulationCb.get());
#ifdef PROFILE_JIT
        jit_options::reportStatistic();
#endif
    }
}

std::string _wellen_get_value_str(vpiHandle sigHdl) {
    VL_FATAL(sigHdl != nullptr, "sigHdl is nullptr");
    auto vpiHdl = reinterpret_cast<SignalHandlePtr>(sigHdl)->vpiHdl;
    return std::string(wellen_get_value_str(reinterpret_cast<void *>(vpiHdl), cursor.index));
}

}; // namespace vpi_compat

using namespace vpi_compat;

vpiHandle vpi_register_cb(p_cb_data cb_data_p) {
    switch (cb_data_p->reason) {
    case cbStartOfSimulation:
        VL_FATAL(startOfSimulationCb == nullptr, "startOfSimulationCb is not nullptr");
        startOfSimulationCb = std::make_unique<s_cb_data>(*cb_data_p);
        break;
    case cbEndOfSimulation:
        VL_FATAL(endOfSimulationCb == nullptr, "endOfSimulationCb is not nullptr");
        endOfSimulationCb = std::make_unique<s_cb_data>(*cb_data_p);
        break;
    case cbValueChange: {
        VL_FATAL(cb_data_p->obj != nullptr, "cb_data_p->obj is nullptr");
        VL_FATAL(cb_data_p->cb_rtn != nullptr, "cb_data_p->cb_rtn is nullptr");
        VL_FATAL(cb_data_p->time != nullptr && cb_data_p->time->type == vpiSuppressTime, "cb_data_p->time is nullptr or cb_data_p->time->type is not vpiSuppressTime");
        VL_FATAL(cb_data_p->value != nullptr && cb_data_p->value->format == vpiIntVal, "cb_data_p->value is nullptr or cb_data_p->value->format is not vpiIntVal");

        auto t = *cb_data_p;
        willAppendValueCb.emplace_back(std::make_pair(vpiHandleAllcator, ValueCbInfo{
                                                                             .cbData   = std::make_shared<t_cb_data>(*cb_data_p),
                                                                             .handle   = cb_data_p->obj,
                                                                             .valueStr = _wellen_get_value_str(cb_data_p->obj),
                                                                         }));
        break;
    }
    case cbAfterDelay: {
        VL_FATAL(cb_data_p->time != nullptr && cb_data_p->time->type == vpiSimTime, "cb_data_p->time is nullptr or cb_data_p->time->type is not vpiSimTime");

        uint64_t time       = (((uint64_t)cb_data_p->time->high << 32) | (cb_data_p->time->low));
        uint64_t targetTime = wellen_get_time_from_index(cursor.index) + time;
        if (targetTime > cursor.maxTime) {
            break;
        }

        uint64_t targetIndex = wellen_get_index_from_time(targetTime);
        // VL_FATAL(targetTime <= cursor.maxTime, "targetTime: {}, cursor.maxTime: {}", targetTime, cursor.maxTime);

        willAppendTimeCbQueue.emplace_back(std::make_pair(targetIndex, std::make_shared<t_cb_data>(*cb_data_p)));
        break;
    }
    case cbNextSimTime: {
        VL_FATAL(cb_data_p->cb_rtn != nullptr, "cb_data_p->cb_rtn is nullptr");
        VL_FATAL(cb_data_p->obj == nullptr, "cb_data_p->obj is not nullptr"); // cbNextSimTime callbacks do not have an object handle.
        VL_FATAL(cb_data_p->value == nullptr, "cb_data_p->value is not nullptr");

        willAppendNextSimTimeQueue.emplace_back(std::make_shared<t_cb_data>(*cb_data_p));
        break;
    }
    default:
        VL_FATAL(false, "TODO: cb reason: {}", cb_data_p->reason);
        break;
    }

    if (cb_data_p->reason == cbValueChange) {
        vpiHandleRaw handle = vpiHandleAllcator;
        vpiHandleAllcator++;
        return new vpiHandleRaw(handle);
    }

    return nullptr;
}

PLI_INT32 vpi_remove_cb(vpiHandle cb_obj) {
    VL_FATAL(cb_obj != nullptr, "cb_obj is nullptr");
    if (valueCbMap.contains(*cb_obj)) {
        willRemoveValueCb.emplace_back(*cb_obj);
    }
    delete cb_obj;
    return 0;
}

PLI_INT32 vpi_free_object(vpiHandle object) {
    if (object != nullptr) {
        VL_FATAL(false, "TODO: vpi_free_object is not supported for now");
        if (valueCbMap.contains(*object)) {
            valueCbMap.erase(*object);
        }
        delete object;
    }
    return 0;
}

PLI_INT32 vpi_release_handle(vpiHandle object) { return vpi_free_object(object); }

vpiHandle vpi_put_value(vpiHandle object, p_vpi_value value_p, p_vpi_time time_p, PLI_INT32 flags) {
    VL_FATAL(false, "Unsupported in wave_vpi, all signals are read-only!");
    return nullptr;
}

vpiHandle vpi_handle_by_name(PLI_BYTE8 *name, vpiHandle scope) {
    // TODO: scope?
    VL_FATAL(scope == nullptr, "TODO: scope is not supported for now");

    auto _vpiHdl = reinterpret_cast<vpiHandle>(wellen_vpi_handle_by_name(name));
    if (_vpiHdl == nullptr) {
        return nullptr;
    }

    auto bitSize = wellen_vpi_get(vpiSize, reinterpret_cast<void *>(_vpiHdl));
    auto sigHdl  = new SignalHandle{.name = std::string(name), .vpiHdl = _vpiHdl, .bitSize = (size_t)bitSize};

    // Only for signals with bitSize <= 32. TODO: Support signals with bitSize > 32.
    sigHdl->canOpt = bitSize <= 32;

    auto vpiHdl = reinterpret_cast<vpiHandle>(sigHdl);

    signalHandleSet.insert(reinterpret_cast<void *>(vpiHdl));
    // hdlToNameMap[vpiHdl] = std::string(name); // For debug purpose
    return vpiHdl;
}

PLI_INT32 vpi_control(PLI_INT32 operation, ...) {
    switch (operation) {
    case vpiStop:
    case vpiFinish:
        if (operation == vpiStop) {
            VL_INFO("get vpiStop\n");
            terminateReason = "vpiStop";
        } else {
            VL_INFO("get vpiFinish\n");
            terminateReason = "vpiFinish";
        }

        vpiControlTerminate = true;
        endOfSimulation();
        return 1;
    default:
        VL_FATAL(false, "Unsupported operation: {}", operation);
        break;
    }
    return 0;
}

vpiHandle vpi_handle_by_index(vpiHandle object, PLI_INT32 indx) {
    VL_FATAL(false, "TODO: vpi_handle_by_index is not supported for now");
    return nullptr;
}

vpiHandle vpi_iterate(PLI_INT32 type, vpiHandle refHandle) {
    if (type != vpiModule && type != vpiNet && type != vpiReg && type != vpiMemory) {
        return nullptr;
    }

    // In wellen mode, Rust returns a backend iterator pointer directly.
    auto iter = reinterpret_cast<vpiHandle>(wellen_vpi_iterate(type, reinterpret_cast<void *>(refHandle)));
    if (iter != nullptr) {
        iteratorHandleSet.insert(reinterpret_cast<void *>(iter));
        iteratorTypeMap.insert_or_assign(reinterpret_cast<void *>(iter), type);
    }
    return iter;
}

vpiHandle vpi_scan(vpiHandle iterator) {
    if (iterator == nullptr) {
        return nullptr;
    }

    auto iteratorRaw = reinterpret_cast<void *>(iterator);
    if (!iteratorHandleSet.contains(iteratorRaw)) {
        return nullptr;
    }

    auto iterType = vpiModule;
    if (auto iterTypeIt = iteratorTypeMap.find(iteratorRaw); iterTypeIt != iteratorTypeMap.end()) {
        iterType = iterTypeIt->second;
    }

    while (true) {
        auto next = reinterpret_cast<vpiHandle>(wellen_vpi_scan(reinterpret_cast<void *>(iterator)));
        if (next == nullptr) {
            // Rust side already freed iterator storage when scan reaches the end.
            iteratorHandleSet.erase(iteratorRaw);
            iteratorTypeMap.erase(iteratorRaw);
            return nullptr;
        }

        if (iterType == vpiModule) {
            moduleHandleSet.insert(reinterpret_cast<void *>(next));
            return next;
        }

        auto signalNamePtr = reinterpret_cast<PLI_BYTE8 *>(wellen_vpi_get_str(vpiName, reinterpret_cast<void *>(next)));
        if (signalNamePtr == nullptr) {
            continue;
        }
        auto bitSize = wellen_vpi_get(vpiSize, reinterpret_cast<void *>(next));
        auto sigHdl  = new SignalHandle{
             .name    = std::string(reinterpret_cast<char *>(signalNamePtr)),
             .vpiHdl  = next,
             .bitSize = static_cast<size_t>(bitSize),
        };
        sigHdl->canOpt = bitSize <= 32;
        auto ret       = reinterpret_cast<vpiHandle>(sigHdl);
        signalHandleSet.insert(reinterpret_cast<void *>(ret));
        return ret;
    }
}

/// Convert FSDB scale unit string to VPI time precision exponent
/// e.g., "1ps" -> -12, "10ns" -> -8, "100us" -> -4
static int32_t fsdbScaleUnitToVpiPrecision(const char *scaleUnit) {
    if (scaleUnit == nullptr) {
        VL_WARN("FSDB scale unit is null, defaulting to ns (-9)\n");
        return -9;
    }

    // Parse digit and unit from scale unit string (e.g., "1ps", "10ns", "100us")
    int digit     = 0;
    const char *p = scaleUnit;
    while (*p >= '0' && *p <= '9') {
        digit = digit * 10 + (*p - '0');
        p++;
    }
    if (digit == 0)
        digit = 1;

    // Calculate factor adjustment: 1 -> 0, 10 -> 1, 100 -> 2
    int factorAdj = 0;
    if (digit >= 100)
        factorAdj = 2;
    else if (digit >= 10)
        factorAdj = 1;

    // Map unit to base exponent
    int baseExp = -9; // default ns
    if (strncmp(p, "fs", 2) == 0)
        baseExp = -15;
    else if (strncmp(p, "ps", 2) == 0)
        baseExp = -12;
    else if (strncmp(p, "ns", 2) == 0)
        baseExp = -9;
    else if (strncmp(p, "us", 2) == 0)
        baseExp = -6;
    else if (strncmp(p, "ms", 2) == 0)
        baseExp = -3;
    else if (strncmp(p, "s", 1) == 0)
        baseExp = 0;
    else {
        VL_WARN("Unknown FSDB time unit: {}, defaulting to ns (-9)\n", p);
    }

    return baseExp + factorAdj;
}

PLI_INT32 vpi_get(PLI_INT32 property, vpiHandle sigHdl) {
    switch (property) {
    case vpiSize:
        if (moduleHandleSet.contains(reinterpret_cast<void *>(sigHdl))) {
            // Module handles are container nodes, not packed value objects.
            return 0;
        }
        return reinterpret_cast<SignalHandlePtr>(sigHdl)->bitSize;
    case vpiTimePrecision:
        return wellen_get_time_precision();
    default:
        VL_FATAL(false, "Unimplemented property: {}", property);
    }
}

void vpi_get_time(vpiHandle object, p_vpi_time time_p) {
    if (time_p == nullptr) {
        return;
    }

    uint64_t simTime = 0;
    simTime          = wellen_get_time_from_index(cursor.index);

    switch (time_p->type) {
    case vpiSimTime:
        time_p->high = (PLI_UINT32)(simTime >> 32);
        time_p->low  = (PLI_UINT32)(simTime & 0xFFFFFFFF);
        break;
    case vpiScaledRealTime:
        time_p->real = (double)simTime;
        break;
    default:
        VL_FATAL(false, "Unsupported time type: {}", time_p->type);
    }
}

PLI_BYTE8 *vpi_get_str(PLI_INT32 property, vpiHandle sigHdl) {
    auto sigHdlRaw = reinterpret_cast<void *>(sigHdl);
    switch (property) {
    case vpiName: {
        // Resolve by handle kind first because module/signal handles are both opaque pointers.
        if (moduleHandleSet.contains(sigHdlRaw)) {
            return reinterpret_cast<PLI_BYTE8 *>(wellen_vpi_get_str(property, sigHdlRaw));
        }

        if (signalHandleSet.contains(sigHdlRaw)) {
            return const_cast<PLI_BYTE8 *>(reinterpret_cast<SignalHandlePtr>(sigHdl)->name.c_str());
        }
        return nullptr;
    }
    case vpiType: {
        if (moduleHandleSet.contains(sigHdlRaw)) {
            return reinterpret_cast<PLI_BYTE8 *>(wellen_vpi_get_str(property, sigHdlRaw));
        }
        auto vpiHdl = reinterpret_cast<SignalHandlePtr>(sigHdl)->vpiHdl;
        return wellen_vpi_get_str(property, reinterpret_cast<void *>(vpiHdl));
    }
    case vpiDefName: {
        if (!moduleHandleSet.contains(sigHdlRaw)) {
            return nullptr;
        }
        // Non-FSDB path delegates to wellen_impl; def-name is intentionally null under FSDB-only policy.
        return reinterpret_cast<PLI_BYTE8 *>(wellen_vpi_get_str(property, sigHdlRaw));
    }
    default:
        VL_FATAL(false, "Unimplemented property: {}", property);
    }
};

static void wellenOptThreadTask(SignalHandlePtr sigHdl) {
    if (vpiControlTerminate) {
        return;
    }

    // static std::mutex optMutex;

    // std::unique_lock<std::mutex> lock(optMutex);

#ifdef PROFILE_JIT
    jit_options::statistic.jitOptTaskCnt.store(jit_options::statistic.jitOptTaskCnt.load() + 1);
#endif

    auto optFunc = [sigHdl](uint64_t startIdx, uint64_t finishIdx) {
        constexpr uint64_t PROGRESS_BATCH = 1024;
        auto &optValueVec                 = sigHdl->optValueVec;
        auto baseIdx                      = sigHdl->optBaseIdx.load(std::memory_order_relaxed);
        for (auto idx = startIdx; idx < finishIdx; idx++) {
            optValueVec[idx - baseIdx] = wellen_get_int_value(sigHdl->vpiHdl, idx);
            // Progressive read: update optFinishIdx periodically so vpi_get_value
            // can start using fast path before the entire window is compiled.
            if ((idx - startIdx + 1) % PROGRESS_BATCH == 0) {
                sigHdl->optFinishIdx.store(idx + 1, std::memory_order_release);
            }
        }
        sigHdl->optFinishIdx.store(finishIdx, std::memory_order_release);
    };

    auto verboseJIT = jit_options::verboseJIT;

    auto currentCursorIdx = cursor.index;
    auto optFinishIdx     = currentCursorIdx + jit_options::compileWindowSize;
    optFinishIdx          = std::min(optFinishIdx, cursor.maxIndex);

    if (verboseJIT && !is_quiet_mode()) {
        fmt::println("[wellenOptThreadTask] First optimization start! {} currentCursorIdx:{} optFinishIdx:{} windowSize:{}", sigHdl->name, currentCursorIdx, optFinishIdx, jit_options::compileWindowSize);
        fflush(stdout);
    }

    // Sliding window: allocate only what's needed instead of the full waveform.
    // Use min(windowCapacity, maxIndex) to avoid over-allocating for small waveforms.
    auto windowCapacity = std::min(jit_options::compileWindowSize * 2, cursor.maxIndex);
    sigHdl->optBaseIdx.store(currentCursorIdx, std::memory_order_relaxed);
    sigHdl->optValueVec.resize(windowCapacity);

    optFunc(currentCursorIdx, optFinishIdx);

    // No longer need optFinish flag — optFinishIdx is progressively updated by optFunc

    // lock.unlock();

#ifdef PROFILE_JIT
    jit_options::statistic.jitOptTaskFirstFinishCnt.store(jit_options::statistic.jitOptTaskFirstFinishCnt.load() + 1);
#endif

    if (verboseJIT && !is_quiet_mode()) {
        fmt::println("[wellenOptThreadTask] First optimization finish! {} currentCursorIdx:{} optFinishIdx:{} windowSize:{}", sigHdl->name, currentCursorIdx, optFinishIdx, jit_options::compileWindowSize);
        fflush(stdout);
    }

    int optCnt = 0;
    std::unique_lock<std::mutex> continueOptLock(sigHdl->mtx);
    while (true) {
        sigHdl->cv.wait(continueOptLock, [sigHdl]() { return sigHdl->continueOpt; });

        // Continue optimization
        auto optFinish    = false;
        auto optStartIdx  = std::max(cursor.index, sigHdl->optFinishIdx.load(std::memory_order_relaxed));
        auto optFinishIdx = optStartIdx + jit_options::compileWindowSize;
        if (optFinishIdx >= cursor.maxIndex) {
            optFinishIdx = cursor.maxIndex;
            optFinish    = true;
        }

        // Sliding window: check if the next window fits in the current allocation.
        // If not, slide the window forward by resetting baseIdx and resizing.
        auto neededEnd = optFinishIdx - sigHdl->optBaseIdx.load(std::memory_order_relaxed);
        if (neededEnd > sigHdl->optValueVec.size()) {
            // Reset optFinishIdx first to force main thread onto slow path during the slide.
            sigHdl->optFinishIdx.store(0, std::memory_order_release);
            sigHdl->optBaseIdx.store(optStartIdx, std::memory_order_release);
            auto newCapacity = std::min(jit_options::compileWindowSize * 2, cursor.maxIndex - optStartIdx);
            sigHdl->optValueVec.resize(newCapacity);
        }

        optFunc(optStartIdx, optFinishIdx);

        // optFinishIdx is already updated progressively by optFunc
        sigHdl->continueOpt = false;
        optCnt++;

        if (verboseJIT && !is_quiet_mode()) {
            fmt::println("[wellenOptThreadTask] [{}] Continue optimization... {} optStartIdx:{} optFinishIdx:{}", optCnt, sigHdl->name, optStartIdx, optFinishIdx);
            fflush(stdout);
        }

        if (optFinish) {
            break;
        }
    }

    jit_options::optThreadCnt.fetch_sub(1, std::memory_order_relaxed);

    if (verboseJIT && !is_quiet_mode()) {
        fmt::println("[wellenOptThreadTask] Optimization finish! total compile times:{} signalName:{}", optCnt, sigHdl->name);
        fflush(stdout);
    }
}

void vpi_get_value(vpiHandle sigHdl, p_vpi_value value_p) {
#ifdef PROFILE_JIT
    auto _totalReadStart = std::chrono::high_resolution_clock::now();
#endif

    static char _buffer[1024 * 1024];
    static s_vpi_vecval _vpiValueVecs[100];

    auto _sigHdl = reinterpret_cast<SignalHandlePtr>(sigHdl);
    auto vpiHdl  = _sigHdl->vpiHdl;

    if (!_sigHdl->canOpt || !jit_options::enableJIT)
        goto ReadFromWellen;

    {
        // Progressive read: check optFinishIdx (atomic) to determine if fast path is available.
        // No need to wait for the entire compilation window to finish.
        auto _optFinishIdx = _sigHdl->optFinishIdx.load(std::memory_order_acquire);
        if (_sigHdl->doOpt && _optFinishIdx > 0) {
            auto _optBaseIdx = _sigHdl->optBaseIdx.load(std::memory_order_acquire);
            if (cursor.index < _optBaseIdx || cursor.index >= _optFinishIdx) {
                // fmt::println("[WARN] JIT need recompile! cursor.index:{} optFinishIdx:{} signalName:{}", cursor.index, _optFinishIdx, _sigHdl->name);
                goto ReadFromWellen;
            }

            if (!_sigHdl->continueOpt && cursor.index >= (_optFinishIdx - jit_options::recompileWindowSize)) {
                // fmt::println("[WARN] continue optimization... {} cursor.index:{} optFinishIdx:{}", _sigHdl->name, cursor.index, _optFinishIdx);
                _sigHdl->continueOpt = true;
                _sigHdl->cv.notify_one();
            }

#ifdef PROFILE_JIT
            jit_options::statistic.readFromOpt++;
#endif

            // Hot-Prefetch JIT path: reads from pre-computed optValueVec (uint32_t, 2-state only).
            // X/Z states are NOT preserved here. To get X/Z information, disable Hot-Prefetch JIT
            // via WAVE_VPI_ENABLE_JIT=0 or WaveVpiCtrl.jit_options:set("enableJIT", false).
            // Sliding window: use offset indexing (cursor.index - optBaseIdx).
            auto _optLocalIdx = cursor.index - _optBaseIdx;
            switch (value_p->format) {
            case vpiIntVal: {
                value_p->value.integer = _sigHdl->optValueVec[_optLocalIdx];
                break;
            }
            case vpiVectorVal: {
                _vpiValueVecs[0].aval = _sigHdl->optValueVec[_optLocalIdx];
                _vpiValueVecs[0].bval = 0;
                value_p->value.vector = _vpiValueVecs;
                break;
            }
            case vpiHexStrVal: {
                const int bufferSize = 8; // TODO: 4 * 8 = 32, if support 64 bit signal, this value should be set to 16.
                uint32_to_hex_str(reinterpret_cast<char *>(_buffer), bufferSize, _sigHdl->optValueVec[_optLocalIdx]);
                value_p->value.str = (char *)_buffer;
                break;
            }
            case vpiBinStrVal: {
                auto &bitSize = _sigHdl->bitSize;
                auto value    = _sigHdl->optValueVec[_optLocalIdx];
                for (int i = 0; i < bitSize; i++) {
                    _buffer[bitSize - 1 - i] = (value & (1 << i)) ? '1' : '0';
                }
                _buffer[bitSize]   = '\0';
                value_p->value.str = (char *)_buffer;
                break;
            }
            case vpiDecStrVal: {
                // Hot-Prefetch JIT path: 2-state only, no X/Z possible
                // Notice: buffer size 16 is sufficient for uint32_t max (4294967295 = 10 chars + '\0').
                // Update this if optValueVec type changes to a wider integer type.
                uint32_to_dec_str(reinterpret_cast<char *>(_buffer), 16, _sigHdl->optValueVec[_optLocalIdx]);
                value_p->value.str = (char *)_buffer;
                break;
            }
            default:
                VL_FATAL(false, "Unsupported format: {}", value_p->format);
            }

#ifdef PROFILE_JIT
            auto _optEnd         = std::chrono::high_resolution_clock::now();
            auto _optElapsedTime = std::chrono::duration_cast<std::chrono::nanoseconds>(_optEnd - _totalReadStart).count();
            jit_options::statistic.readFromOptTime += _optElapsedTime;
            jit_options::statistic.totalReadTime += _optElapsedTime;
#endif
            return;
        }
    }

    if (!_sigHdl->doOpt) {
        _sigHdl->readCnt++;
        // fmt::println("[WARN] readCnt: {} signalName: {} doOpt: {} bitSize: {}", _sigHdl->readCnt, _sigHdl->name, _sigHdl->doOpt, _sigHdl->bitSize);

        // Hot-Prefetch JIT: trigger prefetch when read count exceeds threshold
        if (_sigHdl->readCnt >= jit_options::hotAccessThreshold) {
            auto _jitOptThreadCnt = jit_options::optThreadCnt.load(std::memory_order_relaxed);
            while (_jitOptThreadCnt <= jit_options::maxOptThreads) {
                if (jit_options::optThreadCnt.compare_exchange_weak(_jitOptThreadCnt, _jitOptThreadCnt + 1, std::memory_order_relaxed)) {
                    _sigHdl->doOpt       = true;
                    _sigHdl->continueOpt = false;
                    _sigHdl->optThread   = std::thread([_sigHdl] { wellenOptThreadTask(_sigHdl); });
                    break;
                }
                // compare_exchange_weak updates _jitOptThreadCnt on failure, loop re-checks
            }
#ifdef PROFILE_JIT
            if (_jitOptThreadCnt > jit_options::maxOptThreads) {
                jit_options::statistic.optThreadNotEnough++;
            }
#endif
        }
    }

ReadFromWellen:

#ifdef PROFILE_JIT
    jit_options::statistic.readFromNormal++;
    if (!_sigHdl->canOpt) {
        jit_options::statistic.unOptimizableRead++;
    }
#endif

    wellen_vpi_get_value_from_index(reinterpret_cast<void *>(vpiHdl), cursor.index, value_p);

#ifdef PROFILE_JIT
    auto _normalEnd         = std::chrono::high_resolution_clock::now();
    auto _normalElapsedTime = std::chrono::duration_cast<std::chrono::nanoseconds>(_normalEnd - _totalReadStart).count();
    jit_options::statistic.readFromNormalTime += _normalElapsedTime;
    jit_options::statistic.totalReadTime += _normalElapsedTime;
#endif
}

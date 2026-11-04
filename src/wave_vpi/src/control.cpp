#include "jit_options.h"
#include "vpi_compat.h"
#include "wave_vpi.h"
#include <cstdint>

#ifdef USE_FSDB
#include "fsdb_wave_vpi.h"
#endif

extern WaveCursor cursor;

namespace vpi_compat {
void resyncValueCallbacks() {
    // Cursor jumps skip normal value-change callbacks. Sample the destination
    // so skipped transitions do not appear as new edges on the next step.
    auto resync = [](ValueCbInfo &callback) {
#ifdef USE_FSDB
        if (callback.bitSize == 1) {
            callback.bitValue = fsdbGetSingleBitValue(callback.handle);
        } else {
            callback.valueStr = fsdbGetBinStr(callback.handle);
        }
#else
        callback.valueStr = _wellen_get_value_str(callback.handle);
#endif
    };

    for (auto &entry : valueCbMap) {
        resync(entry.second);
    }
    for (auto &entry : willAppendValueCb) {
        resync(entry.second);
    }
}
} // namespace vpi_compat

// Below are interfaces used by WaveVpiCtrl.lua to control the wave_vpi.

extern "C" uint64_t wave_vpi_ctrl_get_cursor_index() { return cursor.index; }

extern "C" uint64_t wave_vpi_ctrl_get_max_cursor_index() { return cursor.maxIndex; }

extern "C" uint64_t wave_vpi_ctrl_get_max_cursor_time() { return cursor.maxTime; }

extern "C" void wave_vpi_ctrl_set_cursor_index(uint64_t index) {
    vpi_compat::samplingEventObject = nullptr;
    cursor.index                    = index;
    vpi_compat::resyncValueCallbacks();
}

extern "C" void wave_vpi_ctrl_set_cursor_index_percent(double percent) {
    const uint64_t previousIndex    = cursor.index;
    vpi_compat::samplingEventObject = nullptr;
    if (percent >= 100) {
        cursor.index = cursor.maxIndex > 0 ? cursor.maxIndex - 1 : 0;
    } else {
        uint64_t targetIndex = cursor.maxIndex * (percent / 100.0);
        cursor.index         = targetIndex;
    }
    if (cursor.index != previousIndex) {
        vpi_compat::resyncValueCallbacks();
    }
}

extern "C" void wave_vpi_ctrl_set_jit_options(const char *opt_name, uint64_t v) {
    auto n = std::string(opt_name);
    if (n == "enable") {
        jit_options::enableJIT = v >= 1;
    } else if (n == "verbose") {
        jit_options::verboseJIT = v >= 1;
    } else if (n == "max_opt_threads") {
        jit_options::maxOptThreads = v;
    } else if (n == "hot_access_threshold") {
        jit_options::hotAccessThreshold = v;
    } else if (n == "compile_window_size") {
        jit_options::compileWindowSize = v;
    } else if (n == "recompile_window_size") {
        jit_options::recompileWindowSize = v;
    } else {
        VL_FATAL(false, "Unknown JIT option: {}", n);
    }
}

extern "C" uint64_t wave_vpi_ctrl_get_jit_options(const char *opt_name) {
    auto n = std::string(opt_name);
    if (n == "enable") {
        return jit_options::enableJIT;
    } else if (n == "verbose") {
        return jit_options::verboseJIT;
    } else if (n == "max_opt_threads") {
        return jit_options::maxOptThreads;
    } else if (n == "hot_access_threshold") {
        return jit_options::hotAccessThreshold;
    } else if (n == "compile_window_size") {
        return jit_options::compileWindowSize;
    } else if (n == "recompile_window_size") {
        return jit_options::recompileWindowSize;
    } else {
        VL_FATAL(false, "Unknown JIT option: {}", n);
    }
}

extern "C" void wave_vpi_ctrl_set_cursor_time(uint64_t time) {
    vpi_compat::samplingEventObject = nullptr;
    uint64_t targetIndex;
#ifdef USE_FSDB
    targetIndex = fsdb_wave_vpi::fsdbWaveVpi->findNearestTimeIndex(time);
#else
    targetIndex = wellen_get_index_from_time(time);
#endif
    const uint64_t lastIndex = cursor.maxIndex > 0 ? cursor.maxIndex - 1 : 0;
    cursor.index             = targetIndex >= cursor.maxIndex ? lastIndex : targetIndex;
    vpi_compat::resyncValueCallbacks();
}

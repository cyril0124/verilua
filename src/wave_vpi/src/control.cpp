#include "jit_options.h"
#include "wave_vpi.h"

extern WaveCursor cursor;

// Below are interfaces used by WaveVpiCtrl.lua to control the wave_vpi.

extern "C" uint64_t wave_vpi_ctrl_get_cursor_index() { return cursor.index; }

extern "C" uint64_t wave_vpi_ctrl_get_max_cursor_index() { return cursor.maxIndex; }

extern "C" void wave_vpi_ctrl_set_cursor_index(uint64_t index) { cursor.index = index; }

extern "C" void wave_vpi_ctrl_set_cursor_index_percent(double percent) {
    if (percent >= 100) {
        cursor.index = cursor.maxIndex - 1;
    } else {
        uint64_t targetIndex = cursor.maxIndex * (percent / 100.0);
        cursor.index         = targetIndex;
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

#include "jit_options.h"
#include "wave_vpi.h"

namespace jit_options {
bool enableJIT                     = true;
std::atomic<uint32_t> optThreadCnt = 0;
uint32_t maxOptThreads             = JIT_DEFAULT_MAX_OPT_THREADS;
uint64_t hotAccessThreshold        = JTT_DEFAULT_HOT_ACCESS_THRESHOLD;
uint64_t compileWindowSize         = JIT_DEFAULT_COMPILE_WINDOW_SIZE;
uint64_t recompileWindowSize       = JIT_DEFAULT_RECOMPILE_WINDOW_SIZE;

void initialize() {
    auto _enableJIT = std::getenv("WAVE_VPI_ENABLE_JIT");
    if (_enableJIT != nullptr) {
        enableJIT = std::string(_enableJIT) == "1";
    }
    fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_ENABLE_JIT: {}", enableJIT);

    if (enableJIT) {
        auto _maxOptThreads = std::getenv("WAVE_VPI_JIT_MAX_OPT_THREADS");
        if (_maxOptThreads != nullptr) {
            maxOptThreads = std::stoul(_maxOptThreads);
        }
        fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_MAX_OPT_THREADS: {}", maxOptThreads);

        auto _hotAccessThreshold = std::getenv("WAVE_VPI_JIT_HOT_ACCESS_THRESHOLD");
        if (_hotAccessThreshold != nullptr) {
            hotAccessThreshold = std::stoull(_hotAccessThreshold);
        }
        fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_HOT_ACCESS_THRESHOLD: {}", hotAccessThreshold);

        auto _compileWindowSize = std::getenv("WAVE_VPI_JIT_COMPILE_WINDOW_SIZE");
        if (_compileWindowSize != nullptr) {
            compileWindowSize = std::stoull(_compileWindowSize);
        }
        fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_COMPILE_WINDOW_SIZE: {}", compileWindowSize);

        auto _recompileWindowSize = std::getenv("WAVE_VPI_JIT_RECOMPILE_WINDOW_SIZE");
        if (_recompileWindowSize != nullptr) {
            if (std::string(_recompileWindowSize) == "-1") {
                recompileWindowSize = compileWindowSize;
                fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_RECOMPILE_WINDOW_SIZE = WAVE_VPI_JIT_COMPILE_WINDOW_SIZE = {}", recompileWindowSize);
            } else {
                recompileWindowSize = std::stoull(_recompileWindowSize);
            }
        }
        fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_RECOMPILE_WINDOW_SIZE: {}", recompileWindowSize);

        VL_FATAL(recompileWindowSize <= compileWindowSize, "`recompileWindowSize`({}) should less than or equal to `compileWindowSize`({})", recompileWindowSize, compileWindowSize);
    }
}

} // namespace jit_options

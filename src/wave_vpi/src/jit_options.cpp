#include "jit_options.h"
#include "wave_vpi.h"

namespace jit_options {
bool enableJIT                     = true;
bool verboseJIT                    = false;
std::atomic<uint32_t> optThreadCnt = 0;
uint32_t maxOptThreads             = JIT_DEFAULT_MAX_OPT_THREADS;
uint64_t hotAccessThreshold        = JTT_DEFAULT_HOT_ACCESS_THRESHOLD;
uint64_t compileWindowSize         = JIT_DEFAULT_COMPILE_WINDOW_SIZE;
uint64_t recompileWindowSize       = JIT_DEFAULT_RECOMPILE_WINDOW_SIZE;

Statistic statistic;

void initialize() {
    auto _enableJIT = std::getenv("WAVE_VPI_ENABLE_JIT");
    if (_enableJIT != nullptr) {
        enableJIT = std::string(_enableJIT) == "1";
    }
    if (!is_quiet_mode()) {
        fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_ENABLE_JIT: {}", enableJIT);
    }

    if (enableJIT) {
        auto _verboseJIT = std::getenv("WAVE_VPI_VERBOSE_JIT");
        if (_verboseJIT != nullptr) {
            verboseJIT = std::string(_verboseJIT) == "1";
        }
        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_VERBOSE_JIT: {}", verboseJIT);
        }

        auto _maxOptThreads = std::getenv("WAVE_VPI_JIT_MAX_OPT_THREADS");
        if (_maxOptThreads != nullptr) {
            maxOptThreads = std::stoul(_maxOptThreads);
        }
        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_MAX_OPT_THREADS: {}", maxOptThreads);
        }

        auto _hotAccessThreshold = std::getenv("WAVE_VPI_JIT_HOT_ACCESS_THRESHOLD");
        if (_hotAccessThreshold != nullptr) {
            hotAccessThreshold = std::stoull(_hotAccessThreshold);
        }
        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_HOT_ACCESS_THRESHOLD: {}", hotAccessThreshold);
        }

        auto _compileWindowSize = std::getenv("WAVE_VPI_JIT_COMPILE_WINDOW_SIZE");
        if (_compileWindowSize != nullptr) {
            compileWindowSize = std::stoull(_compileWindowSize);
        }
        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_COMPILE_WINDOW_SIZE: {}", compileWindowSize);
        }

        auto _recompileWindowSize = std::getenv("WAVE_VPI_JIT_RECOMPILE_WINDOW_SIZE");
        if (_recompileWindowSize != nullptr) {
            if (std::string(_recompileWindowSize) == "-1") {
                recompileWindowSize = compileWindowSize;
                if (!is_quiet_mode()) {
                    fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_RECOMPILE_WINDOW_SIZE = WAVE_VPI_JIT_COMPILE_WINDOW_SIZE = {}", recompileWindowSize);
                }
            } else {
                recompileWindowSize = std::stoull(_recompileWindowSize);
            }
        }
        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::jit_options::initialize] WAVE_VPI_JIT_RECOMPILE_WINDOW_SIZE: {}", recompileWindowSize);
        }

        VL_FATAL(recompileWindowSize <= compileWindowSize, "`recompileWindowSize`({}) should less than or equal to `compileWindowSize`({})", recompileWindowSize, compileWindowSize);
    }
}

void reportStatistic() {
    auto totalRead           = statistic.readFromOpt + statistic.readFromNormal;
    auto optPerReadTimeNs    = statistic.readFromOptTime / statistic.readFromOpt;
    auto normalPerReadTimeNs = statistic.readFromNormalTime / statistic.readFromNormal;

    auto noJitReadTimeNs = totalRead * normalPerReadTimeNs;
    auto jitEfficiency   = (noJitReadTimeNs - statistic.totalReadTime) * 100 / noJitReadTimeNs;

    if (!is_quiet_mode()) {
        fmt::println("[wave_vpi::jit_options::reportStatistic]");
        fmt::println("\ttotalRead:\t{}", totalRead);
        fmt::println("\ttotalReadTime:\t{:.2f} ms", statistic.totalReadTime / 1000000);
        fmt::println("\tnoJitReadTime:\t{:.2f} ms(suppose)", noJitReadTimeNs / 1000000);
        fmt::println("\tunOptimizableRead:\t{}({:.2f}%)", statistic.unOptimizableRead, static_cast<double>(statistic.unOptimizableRead) / totalRead * 100);
        fmt::println("\treadFromOpt:\t{}({:.2f}%)", statistic.readFromOpt, static_cast<double>(statistic.readFromOpt) / totalRead * 100);
        fmt::println("\treadFromNormal:\t{}({:.2f}%)", statistic.readFromNormal, static_cast<double>(statistic.readFromNormal) / totalRead * 100);
        fmt::println("\treadFromOptTime:\t{:.2f} ns/read, {:.2f} ms(total)", optPerReadTimeNs, statistic.readFromOptTime / 1000000);
        fmt::println("\treadFromNormalTime:\t{:.2f} ns/read, {:.2f} ms(total)", normalPerReadTimeNs, statistic.readFromNormalTime / 1000000);
        fmt::println("\toptThreadNotEnough:\t{}({:.2f}%)", statistic.optThreadNotEnough, static_cast<double>(statistic.optThreadNotEnough) / statistic.readFromNormal * 100);
        fmt::println("\tjitOptTaskCnt:\t{}", statistic.jitOptTaskCnt.load());
        fmt::println("\tjitOptTaskFirstFinishCnt:\t{}", statistic.jitOptTaskFirstFinishCnt.load());
        fmt::println("\tjitEfficiency:\t{:.2f}%", jitEfficiency);
    }
}

} // namespace jit_options

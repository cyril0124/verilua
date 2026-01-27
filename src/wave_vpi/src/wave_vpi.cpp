#include "wave_vpi.h"
#include "jit_options.h"
#include "vpi_compat.h"

#ifdef USE_FSDB
#include "fsdb_wave_vpi.h"
#endif

WaveCursor cursor{0, 0, 0, 0};

// VPI bootstrap function implemented by the user.
extern "C" void vlog_startup_routines_bootstrap();

void sigint_handler(int unused) {
    VL_WARN(R"(
---------------------------------------------------------------------
----   wave_vpi_loop get <SIGINT>, the program will terminate...
---------------------------------------------------------------------
)");

    vpi_compat::endOfSimulation();

    exit(0);
}

void sigabrt_handler(int unused) {
    VL_WARN(R"(
---------------------------------------------------------------------
----   wave_vpi_loop get <SIGABRT>, the program will terminate...
---------------------------------------------------------------------
)");

    vpi_compat::endOfSimulation();

    exit(1);
}

void wave_vpi_init(const char *filename) {
#ifdef USE_FSDB
    fsdb_wave_vpi::fsdbWaveVpi = std::make_shared<fsdb_wave_vpi::FsdbWaveVpi>(ffrObject::ffrOpenNonSharedObj((char *)filename), std::string(filename));

    cursor.maxIndex = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec.size() - 1;
    cursor.maxTime  = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec.at(fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec.size() - 1);
#else
    wellen_initialize(filename);

    cursor.maxIndex = wellen_get_max_index();
    cursor.maxTime  = wellen_get_time_from_index(cursor.maxIndex);
#endif
}

void wave_vpi_loop() {
    // Setup SIG handler so that we can exit gracefully
    std::signal(SIGINT, sigint_handler);   // Deal with Ctrl-C
    std::signal(SIGABRT, sigabrt_handler); // Deal with assert

    jit_options::initialize();

#ifndef NO_VLOG_STARTUP
    // Manually call vlog_startup_routines_bootstrap(), which is called at the beginning of the simulation according to VPI standard specification.
    vlog_startup_routines_bootstrap();
#endif

    vpi_compat::startOfSimulation();

    // Append callbacks which is registered from vpi_compat::startOfSimulationCb
    vpi_compat::appendTimeCb();
    vpi_compat::appendNextSimTimeCb();
    vpi_compat::appendValueCb();

    // Start wave_vpi evaluation loop
    VL_FATAL(cursor.maxIndex != 0, "cursor.maxIndex should not be 0");
    if (!is_quiet_mode()) {
        fmt::println("[wave_vpi::loop] START! cursor.maxIndex => {} cursor.maxTime => {}", cursor.maxIndex, cursor.maxTime);
    }

    while (cursor.index < cursor.maxIndex && !vpi_compat::vpiControlTerminate) {
        // Deal with cbAfterDelay(time) callbacks
        if (!vpi_compat::timeCbMap.empty()) {
            for (auto it = vpi_compat::timeCbMap.begin(); it != vpi_compat::timeCbMap.end();) {
                if (cursor.index >= it->first) {
                    auto cbVec = it->second;
                    for (auto &cb : cbVec) {
                        cb->cb_rtn(cb.get());
                    }
                    it = vpi_compat::timeCbMap.erase(it);
                } else {
                    ++it;
                }
            }
        }
        vpi_compat::appendTimeCb();

        // Deal with cbValueChange callbacks
        for (auto &cb : vpi_compat::valueCbMap) {
            if (cb.second.cbData->cb_rtn != nullptr) [[likely]] {
                VL_FATAL(cb.second.cbData->obj != nullptr, "cbData->obj should not be nullptr");
                VL_FATAL(cb.second.cbData->cb_rtn != nullptr, "cbData->cb_rtn should not be nullptr");

                auto misMatch = false;
#ifdef USE_FSDB
                uint32_t newBitValue = 0;
                std::string newValueStr;
                if (cb.second.bitSize == 1) [[likely]] {
                    newBitValue = vpi_compat::fsdbGetSingleBitValue(cb.second.handle);
                    if (newBitValue != cb.second.bitValue) {
                        misMatch           = true;
                        cb.second.bitValue = newBitValue;
                    }
                } else [[unlikely]] {
                    newValueStr = vpi_compat::fsdbGetBinStr(cb.second.handle);
                    if (newValueStr != cb.second.valueStr) {
                        misMatch           = true;
                        cb.second.valueStr = newValueStr;
                    }
                }
#else
                auto newValueStr = vpi_compat::_wellen_get_value_str(cb.second.handle);
                if (newValueStr != cb.second.valueStr) {
                    misMatch           = true;
                    cb.second.valueStr = newValueStr;
                }
#endif
                // All the value change comparision is done by comparing the string of the value, which provides a more robust way to compare the value.
                if (misMatch) {
                    // For now, the value change callback is only supported in vpiIntVal format.
                    switch (cb.second.cbData->value->format) {
                    [[likely]] case vpiIntVal: {
#ifdef USE_FSDB
                        if (cb.second.bitSize == 1) [[likely]] {
                            cb.second.cbData->value->value.integer = newBitValue;
                        } else [[unlikely]] {
                            // TODO: it seems incorrect?
                            cb.second.cbData->value->value.integer = std::stoi(newValueStr);
                        }
#else
                        // TODO: it seems incorrect?
                        cb.second.cbData->value->value.integer = std::stoi(newValueStr);
#endif
                        break;
                    }
                    default:
                        VL_FATAL(false, "cb.second.cbData->value->format should be vpiIntVal");
                        break;
                    }
                    cb.second.cbData->cb_rtn(cb.second.cbData.get());
                }
            }
        }

        // Deal with cbNextSimTime callbacks
        for (auto &cb : vpi_compat::nextSimTimeQueue) {
            cb->cb_rtn(cb.get());
        }

        // Clean the current cbNextSimTime callbacks
        vpi_compat::nextSimTimeQueue.clear();
        // Append callbacks which is registered from cbNextSimTime callbacks
        vpi_compat::appendNextSimTimeCb();

        // Remove finished cbValueChange callbacks
        vpi_compat::removeValueCb();
        // Register newly registered cbValueChange callbacks from the previous cbNextSimTime callback
        vpi_compat::appendValueCb();

        // Next simulation step
        cursor.index++;
    }

    if (!is_quiet_mode()) {
#ifdef USE_FSDB
        fmt::println("[wave_vpi::loop] FINISH! cursor.index => {} cursor.time => {}", cursor.index, fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index]);
#else
        fmt::println("[wave_vpi::loop] FINISH! cursor.index => {} cursor.time => {}", cursor.index, wellen_get_time_from_index(cursor.index));
#endif

        if (vpi_compat::vpiControlTerminate) {
            fmt::println("[wave_vpi::loop] Terminated by vpiControlTerminate, reason: {}", vpi_compat::terminateReason);
        }
    }

    vpi_compat::endOfSimulation();
    exit(0);
}

#include "wave_vpi.h"
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
    fsdbWaveVpi = std::make_shared<FsdbWaveVpi>(ffrObject::ffrOpenNonSharedObj((char *)filename), std::string(filename));

    cursor.maxIndex = fsdbWaveVpi->xtagU64Vec.size() - 1;
    cursor.maxTime  = fsdbWaveVpi->xtagU64Vec.at(fsdbWaveVpi->xtagU64Vec.size() - 1);
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

#ifndef NO_VLOG_STARTUP
    // Manually call vlog_startup_routines_bootstrap(), which is called at the beginning of the simulation according to VPI standard specification.
    vlog_startup_routines_bootstrap();
#endif

    // Call vpi_compat::startOfSimulationCb if it exists
    if (vpi_compat::startOfSimulationCb) {
        vpi_compat::startOfSimulationCb->cb_rtn(vpi_compat::startOfSimulationCb.get());
    }

    // Append callbacks which is registered from vpi_compat::startOfSimulationCb
    vpi_compat::appendTimeCb();
    vpi_compat::appendNextSimTimeCb();
    vpi_compat::appendValueCb();

    // Start wave_vpi evaluation loop
    VL_FATAL(cursor.maxIndex != 0, "cursor.maxIndex should not be 0");
    fmt::println("[wave_vpi::loop] START! cursor.maxIndex => {} cursor.maxTime => {}", cursor.maxIndex, cursor.maxTime);

    while (cursor.index < cursor.maxIndex) {
        // Deal with cbAfterDelay(time) callbacks
        if (!vpi_compat::timeCbQueue.empty()) {
            bool again = cursor.index >= vpi_compat::timeCbQueue.front().first;
            while (again) {
                auto cb = vpi_compat::timeCbQueue.front().second;
                cb->cb_rtn(cb.get());
                vpi_compat::timeCbQueue.pop();
                again = !vpi_compat::timeCbQueue.empty() && cursor.index >= vpi_compat::timeCbQueue.front().first;
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
                auto newValueStr = vpi_compat::_wellen_get_value_str(&cb.second.handle);
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

#ifdef USE_FSDB
    fmt::println("[wave_vpi::loop] FINISH! cursor.index => {} cursor.time => {}", cursor.index, fsdbWaveVpi->xtagU64Vec[cursor.index]);
#else
    fmt::println("[wave_vpi::loop] FINISH! cursor.index => {} cursor.time => {}", cursor.index, wellen_get_time_from_index(cursor.index));
#endif

    vpi_compat::endOfSimulation();
    exit(0);
}

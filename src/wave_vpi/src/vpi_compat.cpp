#include "vpi_compat.h"

#ifdef USE_FSDB
#include "fsdb_wave_vpi.h"
#endif

// Unsupported:
//      vpi_put_value(handle, &v, NULL, vpiNoDelay); // wave_vpi is considered a read-only waveform simulate backend in verilua
//
// Supported:
//      OK => vpi_get_value(handle, &v);
//      OK => vpi_get_str(vpiType, actual_handle);
//      OK => vpi_get(vpiSize, actual_handle);
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
//      vpi_iterate
//      vpi_scan
//      vpi_handle_by_index

extern WaveCursor cursor;

namespace vpi_compat {

bool vpiControlTerminate    = false;
std::string terminateReason = "Unknown";

std::unique_ptr<s_cb_data> startOfSimulationCb = NULL;
std::unique_ptr<s_cb_data> endOfSimulationCb   = NULL;

std::queue<std::pair<uint64_t, std::shared_ptr<t_cb_data>>> timeCbQueue;
std::vector<std::pair<uint64_t, std::shared_ptr<t_cb_data>>> willAppendTimeCbQueue;

// The nextSimTimeQueue is a queue of callbacks that will be called at the next simulation time.
std::vector<std::shared_ptr<t_cb_data>> nextSimTimeQueue;
std::vector<std::shared_ptr<t_cb_data>> willAppendNextSimTimeQueue;

boost::unordered_flat_map<vpiHandleRaw, ValueCbInfo> valueCbMap;
std::vector<std::pair<vpiHandleRaw, ValueCbInfo>> willAppendValueCb;
std::vector<vpiHandleRaw> willRemoveValueCb;

// The vpiHandleAllocator is a counter that counts the number of vpiHandles allocated which make it easy to provide unique vpiHandle values.
vpiHandleRaw vpiHandleAllcator = 0;

// boost::unordered_flat_map<vpiHandle, std::string> hdlToNameMap; // For debug purpose

#ifdef USE_FSDB
std::string fsdbGetBinStr(vpiHandle object) {
    s_vpi_value v;
    v.format = vpiBinStrVal;
    vpi_get_value(object, &v);
    return std::string(v.value.str);
}

uint32_t fsdbGetSingleBitValue(vpiHandle object) {
    s_vpi_value v;
    v.format = vpiIntVal;
    vpi_get_value(object, &v); // Use `vpi_get_value` since we have JIT-like feature in `vpi_get_value`
    return v.value.integer;

    // auto fsdbSigHdl = reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandlePtr>(object);
    // auto vcTrvsHdl = fsdbSigHdl->vcTrvsHdl;
    // byte_T *retVC;
    // fsdbBytesPerBit bpb;

    // auto time = fsdb_wave_vpi::fsdbWaveVpi->xtagVec[cursor.index];
    // time.hltag.L = time.hltag.L + 1; // Move a little bit further to ensure we are not in the sensitive clock edge which may lead to signal value confusion.
    // if(FSDB_RC_SUCCESS != vcTrvsHdl->ffrGotoXTag(&time)) [[unlikely]] {
    //     auto currIndexTime = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index];
    //     auto maxIndexTime = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.maxIndex];
    //     VL_FATAL(false, "vcTrvsHdl->ffrGotoXTag() failed! time.hltag.L: {}, time.hltag.H: {}, maxIndexTime: {}, currIndexTime: {}, cursor.maxIndex: {}, cursor.index: {}", time.hltag.L, time.hltag.H, maxIndexTime, currIndexTime, cursor.maxIndex, cursor.index);
    // }
    // if(FSDB_RC_SUCCESS != vcTrvsHdl->ffrGetVC(&retVC)) [[unlikely]] {
    //     VL_FATAL(false, "vcTrvsHdl->ffrGetVC() failed!");
    // }

    // bpb = vcTrvsHdl->ffrGetBytesPerBit();

    // switch (bpb) {
    // [[likely]] case FSDB_BYTES_PER_BIT_1B: {
    //     switch (retVC[0]) {
    //         case FSDB_BT_VCD_X: // treat `X` as `0`
    //         case FSDB_BT_VCD_Z: // treat `Z` as `0`
    //         case FSDB_BT_VCD_0:
    //             return 0;
    //         case FSDB_BT_VCD_1:
    //             return 1;
    //         default:
    //             VL_FATAL(false, "unknown verilog bit type found.");
    //     }
    //     break;
    // }
    // case FSDB_BYTES_PER_BIT_4B:
    // case FSDB_BYTES_PER_BIT_8B:
    //     VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_4B/8B, bpb: {}", static_cast<int>(bpb));
    //     break;
    // default:
    //     VL_FATAL(false, "Should not reach here!");
    // }

    // VL_FATAL(false, "Should not come here...");
}
#else
std::string _wellen_get_value_str(vpiHandle object) {
    VL_FATAL(object != nullptr, "object is nullptr");
    return std::string(wellen_get_value_str(reinterpret_cast<void *>(object), cursor.index));
}
#endif

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
#ifdef USE_FSDB
        size_t bitSize = reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandlePtr>(cb_data_p->obj)->bitSize;
        if (bitSize == 1) [[likely]] {
            willAppendValueCb.emplace_back(std::make_pair(vpiHandleAllcator, ValueCbInfo{
                                                                                 .cbData   = std::make_shared<t_cb_data>(*cb_data_p),
                                                                                 .handle   = cb_data_p->obj,
                                                                                 .bitSize  = 1,
                                                                                 .bitValue = fsdbGetSingleBitValue(cb_data_p->obj),
                                                                                 .valueStr = "",
                                                                             }));
        } else [[unlikely]] {
            willAppendValueCb.emplace_back(std::make_pair(vpiHandleAllcator, ValueCbInfo{
                                                                                 .cbData   = std::make_shared<t_cb_data>(*cb_data_p),
                                                                                 .handle   = cb_data_p->obj,
                                                                                 .bitSize  = bitSize,
                                                                                 .bitValue = 0,
                                                                                 .valueStr = fsdbGetBinStr(cb_data_p->obj),
                                                                             }));
        }
#else
        willAppendValueCb.emplace_back(std::make_pair(vpiHandleAllcator, ValueCbInfo{
                                                                             .cbData   = std::make_shared<t_cb_data>(*cb_data_p),
                                                                             .handle   = *cb_data_p->obj,
                                                                             .valueStr = _wellen_get_value_str(cb_data_p->obj),
                                                                         }));
#endif
        break;
    }
    case cbAfterDelay: {
        VL_FATAL(cb_data_p->time != nullptr && cb_data_p->time->type == vpiSimTime, "cb_data_p->time is nullptr or cb_data_p->time->type is not vpiSimTime");

        uint64_t time = (((uint64_t)cb_data_p->time->high << 32) | (cb_data_p->time->low));
#ifdef USE_FSDB
        uint64_t targetTime  = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index] + time;
        uint64_t targetIndex = fsdb_wave_vpi::fsdbWaveVpi->findNearestTimeIndex(targetTime);
#else
        uint64_t targetTime  = wellen_get_time_from_index(cursor.index) + time;
        uint64_t targetIndex = wellen_get_index_from_time(targetTime);
#endif
        VL_FATAL(targetTime <= cursor.maxTime, "targetTime: {}, cursor.maxTime: {}", targetTime, cursor.maxTime);

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
    } else {
        return nullptr;
    }
}

PLI_INT32 vpi_remove_cb(vpiHandle cb_obj) {
    VL_FATAL(cb_obj != nullptr, "cb_obj is nullptr");
    if (valueCbMap.find(*cb_obj) != valueCbMap.end()) {
        willRemoveValueCb.emplace_back(*cb_obj);
    }
    delete cb_obj;
    return 0;
}

PLI_INT32 vpi_free_object(vpiHandle object) {
    if (object != nullptr) {
        VL_FATAL(false, "TODO: vpi_free_object is not supported for now");
        if (valueCbMap.find(*object) != valueCbMap.end()) {
            valueCbMap.erase(*object);
        }
        delete object;
    }
    return 0;
}

PLI_INT32 vpi_release_handle(vpiHandle object) { return vpi_free_object(object); }

vpiHandle vpi_put_value(vpiHandle object, p_vpi_value value_p, p_vpi_time time_p, PLI_INT32 flags) {
    VL_FATAL(false, "Unsupported in wave_vpi, all signals are read-only!");
    return 0;
}

vpiHandle vpi_handle_by_name(PLI_BYTE8 *name, vpiHandle scope) {
    // TODO: scope?
    VL_FATAL(scope == nullptr, "TODO: scope is not supported for now");

#ifdef USE_FSDB
    auto varIdCode = fsdb_wave_vpi::fsdbWaveVpi->getVarIdCodeByName(name);
    if (varIdCode == -1) {
        return nullptr;
    }

    auto hdl = fsdb_wave_vpi::fsdbWaveVpi->fsdbObj->ffrCreateVCTrvsHdl(varIdCode);
    if (!hdl) {
        VL_FATAL(false, "Failed to create value change traverse handle, name: {}", std::string(name));
    }

    auto fsdbSigHdl = new fsdb_wave_vpi::FsdbSignalHandle{.name = std::string(name), .vcTrvsHdl = hdl, .varIdCode = varIdCode, .bitSize = hdl->ffrGetBitSize()};

    auto vpiHdl = reinterpret_cast<vpiHandle>(fsdbSigHdl);
#else
    auto vpiHdl = reinterpret_cast<vpiHandle>(wellen_vpi_handle_by_name(name));
#endif

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
    // TODO: consider slang
    // return reinterpret_cast<vpiHandle>(wellen_vpi_iterate(type, reinterpret_cast<void *>(refHandle)));
    return nullptr;
}

vpiHandle vpi_scan(vpiHandle iterator) {
    // TODO: consider slang
    return nullptr;
}

PLI_INT32 vpi_get(PLI_INT32 property, vpiHandle object) {
#ifdef USE_FSDB
    switch (property) {
    case vpiSize:
        return reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandlePtr>(object)->bitSize;
    default:
        VL_FATAL(false, "Unimplemented property: {}", property);
    }
#else
    return wellen_vpi_get(property, reinterpret_cast<void *>(object));
#endif
}

PLI_BYTE8 *vpi_get_str(PLI_INT32 property, vpiHandle object) {
#ifdef USE_FSDB
    switch (property) {
    case vpiType: {
        auto varType = reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandle *>(object)->vcTrvsHdl->ffrGetVarType();
        switch (varType) {
        case FSDB_VT_VCD_REG:
            return const_cast<PLI_BYTE8 *>("vpiReg");
        case FSDB_VT_VCD_WIRE:
            return const_cast<PLI_BYTE8 *>("vpiNet");
        default:
            VL_FATAL(false, "Unknown fsdbVarType: {}", static_cast<int>(varType));
        }
    }
    default:
        VL_FATAL(false, "Unimplemented property: {}", property);
    }
#else
    return reinterpret_cast<PLI_BYTE8 *>(wellen_vpi_get_str(property, reinterpret_cast<void *>(object)));
#endif
};

#ifdef USE_FSDB
static void fsdbOptThreadTask(std::string fsdbFileName, std::vector<fsdbXTag> xtagVec, fsdb_wave_vpi::FsdbSignalHandlePtr fsdbSigHdl) {
    static std::mutex optMutex;

    // Ensure only one `fsdbObj` can be processed for all the optimization threads. (It seems like a bug that FsdbReader did not allow multiple ffrObjects to be processed at multiple threads. )
    std::unique_lock<std::mutex> lock(optMutex);

    ffrObject *fsdbObj = ffrObject::ffrOpenNonSharedObj(const_cast<char *>(fsdbFileName.c_str()));
    VL_FATAL(fsdbObj != nullptr, "Failed to open fsdbObj, fsdbFileName: {}", fsdbFileName);
    fsdbObj->ffrReadScopeVarTree();

    auto hdl     = fsdbObj->ffrCreateVCTrvsHdl(fsdbSigHdl->varIdCode);
    auto bitSize = hdl->ffrGetBitSize();
    VL_FATAL(hdl != nullptr, "Failed to create hdl, fsdbFileName: {}, fsdbSigHdl->name: {}, fsdbSigHdl->varIdCode: {}", fsdbFileName, fsdbSigHdl->name, fsdbSigHdl->varIdCode);
    VL_FATAL(bitSize <= 32, "For now we only optimize signals with bitSize <= 32, bitSize: {}", bitSize);

    auto &optValueVec = fsdbSigHdl->optValueVec;
    optValueVec.reserve(xtagVec.size());

    auto currentCursorIdx = cursor.index;
    auto optFinishIdx     = currentCursorIdx + fsdb_wave_vpi::jitCompileWindowSize;

    if (optFinishIdx >= xtagVec.size()) {
        optFinishIdx = xtagVec.size() - 1;
    }

    auto optFunc = [&hdl, &xtagVec, &bitSize, &fsdbFileName, fsdbSigHdl](size_t startIdx, size_t finishIdx) {
        byte_T *retVC;
        fsdbBytesPerBit bpb;

        auto &optValueVec = fsdbSigHdl->optValueVec;

        for (auto idx = startIdx; idx < finishIdx; idx++) {
            uint32_t tmpVal = 0;
            auto time       = xtagVec[idx];
            time.hltag.L    = time.hltag.L + 1;

            if (FSDB_RC_SUCCESS != hdl->ffrGotoXTag(&time)) [[unlikely]] {
                VL_FATAL(false, "Failed to call hdl->ffrGotoXtag(), time.hltag.L: {}, time.hltag.H: {}, idx: {}, fsdbSigHdl->name: {}, fsdbFileName: {}", time.hltag.L, time.hltag.H, idx, fsdbSigHdl->name, fsdbFileName);
            }

            if (FSDB_RC_SUCCESS != hdl->ffrGetVC(&retVC)) [[unlikely]] {
                VL_FATAL(false, "hdl->ffrGetVC() failed!");
            }

            bpb = hdl->ffrGetBytesPerBit();

            if (bitSize == 1) {
                switch (bpb) {
                [[likely]] case FSDB_BYTES_PER_BIT_1B: {
                    switch (retVC[0]) {
                    case FSDB_BT_VCD_X: // treat `X` as `0`
                    case FSDB_BT_VCD_Z: // treat `Z` as `0`
                    case FSDB_BT_VCD_0:
                        optValueVec[idx] = 0;
                        break;
                    case FSDB_BT_VCD_1:
                        optValueVec[idx] = 1;
                        break;
                    default:
                        VL_FATAL(false, "unknown verilog bit type found.");
                    }
                    break;
                }
                case FSDB_BYTES_PER_BIT_4B:
                case FSDB_BYTES_PER_BIT_8B:
                    VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_4B/8B, bpb: {}", static_cast<int>(bpb));
                    break;
                default:
                    VL_FATAL(false, "Should not reach here!");
                }
            } else {
                switch (bpb) {
                [[likely]] case FSDB_BYTES_PER_BIT_1B: {
                    for (int i = 0; i < bitSize; i++) {
                        switch (retVC[i]) {
                        case FSDB_BT_VCD_X: // treat `X` as `0`
                        case FSDB_BT_VCD_Z: // treat `Z` as `0`
                        case FSDB_BT_VCD_0:
                            break;
                        case FSDB_BT_VCD_1:
                            tmpVal += 1 << (bitSize - i - 1);
                            break;
                        default:
                            VL_FATAL(false, "unknown verilog bit type found.");
                        }
                    }
                    break;
                }
                case FSDB_BYTES_PER_BIT_4B:
                case FSDB_BYTES_PER_BIT_8B:
                    VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_4B/8B, bpb: {}", static_cast<int>(bpb));
                    break;
                default:
                    VL_FATAL(false, "Should not reach here!");
                }
                optValueVec[idx] = tmpVal;
            }
        }
    };

    optFunc(currentCursorIdx, optFinishIdx);

    fsdbSigHdl->optFinish    = true;
    fsdbSigHdl->optFinishIdx = optFinishIdx;

    lock.unlock();

    auto _verbose_jit = std::getenv("WAVE_VPI_VERBOSE_JIT");
    auto verbose_jit  = false;
    if (_verbose_jit != nullptr) {
        verbose_jit = std::string(_verbose_jit) == "1";
    }

    if (verbose_jit) {
        fmt::println("[fsdbOptThreadTask] First optimization finish! {} currentCursorIdx:{} optFinishIdx:{}", fsdbSigHdl->name, currentCursorIdx, optFinishIdx);
    }

    int optCnt = 0;
    std::unique_lock<std::mutex> continueOptLock(fsdbSigHdl->mtx);
    while (true) {
        fsdbSigHdl->cv.wait(continueOptLock, [fsdbSigHdl]() { return fsdbSigHdl->continueOpt; });

        // Continue optimization
        auto optFinish    = false;
        auto optStartIdx  = fsdbSigHdl->optFinishIdx;
        auto optFinishIdx = fsdbSigHdl->optFinishIdx + fsdb_wave_vpi::jitCompileWindowSize;
        if (optFinishIdx >= xtagVec.size()) {
            optFinishIdx = xtagVec.size() - 1;
            optFinish    = true;
        }
        optFunc(optStartIdx, optFinishIdx);

        fsdbSigHdl->optFinishIdx = optFinishIdx;
        fsdbSigHdl->continueOpt  = false;

        optCnt++;

        if (verbose_jit) {
            fmt::println("[fsdbOptThreadTask] [{}] Continue optimization... {} optStartIdx:{} optFinishIdx:{}", optCnt, fsdbSigHdl->name, optStartIdx, optFinishIdx);
        }

        if (optFinish) {
            break;
        }
    }

    fsdb_wave_vpi::jitOptThreadCnt.store(fsdb_wave_vpi::jitOptThreadCnt.load() - 1);

    // fsdbObj->ffrClose();
    if (verbose_jit) {
        fmt::println("[fsdbOptThreadTask] Optimization finish! total compile times:{} signalName:{}", optCnt, fsdbSigHdl->name);
        optCnt++;
    }
}
#endif

void vpi_get_value(vpiHandle object, p_vpi_value value_p) {
#ifdef USE_FSDB
    static byte_T buffer[FSDB_MAX_BIT_SIZE + 1];
    static s_vpi_vecval vpiValueVecs[100];
    auto fsdbSigHdl = reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandlePtr>(object);

    if (!fsdb_wave_vpi::enableJIT)
        goto ReadFromFSDB;

    if (fsdbSigHdl->optFinish) {
        if (cursor.index >= fsdbSigHdl->optFinishIdx) {
            // fmt::println("[WARN] JIT need recompile! cursor.index:{} optFinishIdx:{} signalName:{}", cursor.index, fsdbSigHdl->optFinishIdx, fsdbSigHdl->name);
            goto ReadFromFSDB;
        } else if (cursor.index >= (fsdbSigHdl->optFinishIdx - fsdb_wave_vpi::jitRecompileWindowSize)) {
            // fmt::println("[WARN] continue optimization... {} cursot.index:{} optFinishIdx:{}", fsdbSigHdl->name, cursor.index, fsdbSigHdl->optFinishIdx);
            fsdbSigHdl->continueOpt = true;
            fsdbSigHdl->cv.notify_all();
        }

        switch (value_p->format) {
        case vpiIntVal: {
            value_p->value.integer = fsdbSigHdl->optValueVec[cursor.index];
            return;
        }
        case vpiVectorVal: {
            vpiValueVecs[0].aval  = fsdbSigHdl->optValueVec[cursor.index];
            vpiValueVecs[0].bval  = 0;
            value_p->value.vector = vpiValueVecs;
            return;
        }
        case vpiHexStrVal: {
            const int bufferSize = 8; // TODO: 4 * 8 = 32, if support 64 bit signal, this value should be set to 16.
            snprintf(reinterpret_cast<char *>(buffer), bufferSize, "%x", fsdbSigHdl->optValueVec[cursor.index]);
            value_p->value.str = (char *)buffer;
            return;
        }
        case vpiBinStrVal: {
            auto &bitSize = fsdbSigHdl->bitSize;
            auto value    = fsdbSigHdl->optValueVec[cursor.index];
            for (int i = 0; i < bitSize; i++) {
                buffer[bitSize - 1 - i] = (value & (1 << i)) ? '1' : '0';
            }
            buffer[bitSize]    = '\0';
            value_p->value.str = (char *)buffer;
            return;
        }
        default:
            VL_FATAL(false, "Unsupported format: {}", value_p->format);
        }
    } else {
        fsdbSigHdl->readCnt++;

        // Doing somthing like JIT(Just-In-Time)...
        // Only for signals with bitSize <= 32. TODO: Support signals with bitSize > 32.
        if (!fsdbSigHdl->doOpt && fsdbSigHdl->bitSize <= 32 && fsdbSigHdl->readCnt > fsdb_wave_vpi::jitHotAccessThreshold) {
            auto _jitOptThreadCnt = fsdb_wave_vpi::jitOptThreadCnt.load();
            if (_jitOptThreadCnt <= fsdb_wave_vpi::jitMaxOptThreads) {
                fsdb_wave_vpi::jitOptThreadCnt.store(_jitOptThreadCnt + 1);
                fsdbSigHdl->doOpt       = true;
                fsdbSigHdl->continueOpt = false;
                fsdbSigHdl->optThread   = std::thread(std::bind(fsdbOptThreadTask, fsdb_wave_vpi::fsdbWaveVpi->waveFileName, fsdb_wave_vpi::fsdbWaveVpi->xtagVec, fsdbSigHdl));
            }
        }
    }

ReadFromFSDB:

    auto vcTrvsHdl = fsdbSigHdl->vcTrvsHdl;
    byte_T *retVC;
    fsdbBytesPerBit bpb;
    size_t bitSize = fsdbSigHdl->bitSize;

    auto time    = fsdb_wave_vpi::fsdbWaveVpi->xtagVec[cursor.index];
    time.hltag.L = time.hltag.L + 1; // Move a little bit further to ensure we are not in the sensitive clock edge which may lead to signal value confusion.

    if (FSDB_RC_SUCCESS != vcTrvsHdl->ffrGotoXTag(&time)) [[unlikely]] {
        auto currIndexTime = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index];
        auto maxIndexTime  = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.maxIndex];
        VL_FATAL(false, "vcTrvsHdl->ffrGotoXTag() failed! time.hltag.L: {}, time.hltag.H: {}, maxIndexTime: {}, currIndexTime: {}, cursor.maxIndex: {}, cursor.index: {}", time.hltag.L, time.hltag.H, maxIndexTime, currIndexTime, cursor.maxIndex, cursor.index);
    }
    if (FSDB_RC_SUCCESS != vcTrvsHdl->ffrGetVC(&retVC)) [[unlikely]] {
        VL_FATAL(false, "vcTrvsHdl->ffrGetVC() failed!");
    }

    bpb = vcTrvsHdl->ffrGetBytesPerBit();

    switch (value_p->format) {
    case vpiIntVal: {
        value_p->value.integer = 0;
        switch (bpb) {
        [[likely]] case FSDB_BYTES_PER_BIT_1B: {
            for (int i = 0; i < bitSize; i++) {
                switch (retVC[i]) {
                case FSDB_BT_VCD_0:
                    break;
                case FSDB_BT_VCD_1:
                    value_p->value.integer += 1 << (bitSize - i - 1);
                    break;
                case FSDB_BT_VCD_X:
                    // treat `X` as `0`
                    break;
                case FSDB_BT_VCD_Z:
                    // treat `Z` as `0`
                    break;
                default:
                    VL_FATAL(false, "unknown verilog bit type found.");
                }
            }
            break;
        }
        case FSDB_BYTES_PER_BIT_4B:
            VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_4B");
            break;
        case FSDB_BYTES_PER_BIT_8B:
            VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_8B");
            break;
        default:
            VL_FATAL(false, "Should not reach here!");
        }
        break;
    }
    case vpiVectorVal: {
        switch (bpb) {
        [[likely]] case FSDB_BYTES_PER_BIT_1B: {
            uint32_t chunkSize = 0;
            if ((bitSize % 32) == 0) {
                chunkSize = bitSize / 32;
            } else {
                chunkSize = bitSize / 32 + 1;
            }

            uint32_t tmpVal    = 0;
            uint32_t bufferIdx = 0;
            uint32_t tmpIdx    = 0;
            for (int i = bitSize - 1; i >= 0; i--) {
                switch (retVC[i]) {
                case FSDB_BT_VCD_0:
                    break;
                case FSDB_BT_VCD_1:
                    tmpVal += 1 << tmpIdx;
                    break;
                case FSDB_BT_VCD_X:
                    // treat `X` as `0`
                    break;
                case FSDB_BT_VCD_Z:
                    // treat `Z` as `0`
                    break;
                default:
                    VL_FATAL(false, "unknown verilog bit type found. i: {}", i);
                }
                tmpIdx++;
                if (tmpIdx == 32) {
                    vpiValueVecs[bufferIdx].aval = tmpVal;
                    vpiValueVecs[bufferIdx].bval = 0;
                    tmpVal                       = 0;
                    tmpIdx                       = 0;
                    bufferIdx++;
                }
            }

            if (tmpIdx != 0) {
                vpiValueVecs[bufferIdx].aval = tmpVal;
                vpiValueVecs[bufferIdx].bval = 0;
            }
            break;
        }
        case FSDB_BYTES_PER_BIT_4B:
            VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_4B");
            break;
        case FSDB_BYTES_PER_BIT_8B:
            VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_8B");
            break;
        default:
            VL_FATAL(false, "Should not reach here!");
        }
        value_p->value.vector = vpiValueVecs;
        break;
    }
    case vpiHexStrVal: {
        static const char hexLookUpTable[] = {'0', '1', '2', '3', '4', '4', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
        switch (bpb) {
        [[likely]] case FSDB_BYTES_PER_BIT_1B: {
            int bufferIdx = 0;
            int tmpVal    = 0;
            int tmpIdx    = 0;
            int chunkSize = 0;
            if ((bitSize % 4) == 0) {
                chunkSize = bitSize / 4;
            } else {
                chunkSize = bitSize / 4 + 1;
            }

            for (int i = bitSize - 1; i >= 0; i--) {
                switch (retVC[i]) {
                case FSDB_BT_VCD_0:
                    break;
                case FSDB_BT_VCD_1:
                    tmpVal += 1 << tmpIdx;
                    break;
                case FSDB_BT_VCD_X:
                    // treat `X` as `0`
                    break;
                case FSDB_BT_VCD_Z:
                    // treat `Z` as `0`
                    break;
                default:
                    VL_FATAL(false, "unknown verilog bit type found. i: {}", i);
                }
                tmpIdx++;
                if (tmpIdx == 4) {
                    buffer[chunkSize - 1 - bufferIdx] = hexLookUpTable[tmpVal];
                    tmpVal                            = 0;
                    tmpIdx                            = 0;
                    bufferIdx++;
                }
            }
            if (tmpIdx != 0) {
                buffer[chunkSize - 1 - bufferIdx] = hexLookUpTable[tmpVal];
                bufferIdx++;
            }
            buffer[bufferIdx] = '\0';
            break;
        }
        case FSDB_BYTES_PER_BIT_4B:
            VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_4B");
            break;
        case FSDB_BYTES_PER_BIT_8B:
            VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_8B");
            break;
        default:
            VL_FATAL(false, "Should not reach here!");
        }
        value_p->value.str = (char *)buffer;
        break;
    }
    [[unlikely]] case vpiBinStrVal: {
        switch (bpb) {
        [[likely]] case FSDB_BYTES_PER_BIT_1B: {
            int i = 0;
            for (i = 0; i < bitSize; i++) {
                switch (retVC[i]) {
                case FSDB_BT_VCD_0:
                    buffer[i] = '0';
                    break;
                case FSDB_BT_VCD_1:
                    buffer[i] = '1';
                    break;
                case FSDB_BT_VCD_X:
                    // treat `X` as `0`
                    buffer[i] = '0';
                    break;
                case FSDB_BT_VCD_Z:
                    // treat `Z` as `0`
                    buffer[i] = '0';
                    break;
                default:
                    VL_FATAL(false, "unknown verilog bit type found.");
                }
            }
            buffer[i] = '\0';
            break;
        }
        case FSDB_BYTES_PER_BIT_4B:
            VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_4B");
            break;
        case FSDB_BYTES_PER_BIT_8B:
            VL_FATAL(false, "TODO: FSDB_BYTES_PER_BIT_8B");
            break;
        default:
            VL_FATAL(false, "Should not reach here!");
        }
        value_p->value.str = (char *)buffer;
        break;
    }
    default: {
        VL_FATAL(false, "Unknown value format: {}", value_p->format);
    }
    }

    // auto format = std::string("");
    // fmt::println("\n[{}] retVC:{}", hdlToNameMap[object], retVC[0]);
    // if(value_p->format == vpiIntVal) {
    //     format = "vpiIntVal";
    //     fmt::println("[{}]@{} format:{} value: {}", hdlToNameMap[object], fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index], format, value_p->value.integer);
    // } else if(value_p->format == vpiVectorVal) {
    //     format = "vpiVectorVal";
    //     fmt::println("[{}]@{} format:{} value: {}", hdlToNameMap[object], fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index], format, value_p->value.vector[0].aval);
    // } else if (value_p->format == vpiHexStrVal) {
    //     format = "vpiHexStrVal";
    //     fmt::println("[{}]@{} format:{} value: {}", hdlToNameMap[object], fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index], format, value_p->value.str);
    // }
#else
    wellen_vpi_get_value_from_index(reinterpret_cast<void *>(object), cursor.index, value_p);
#endif
}

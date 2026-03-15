#include "jit_options.h"
#include "vpi_compat.h"
#include "wave_vpi.h"
#include <unordered_map>
#include <unordered_set>

#include "fsdb_wave_vpi.h"

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
    int32_t fsdbNodeIdx;
};
using ModuleHandle    = ModuleHandle_t;
using ModuleHandlePtr = ModuleHandle_t *;

enum class IteratorItemType {
    Module,
    Signal,
};

struct FsdbSignalEntry {
    std::string name;
    fsdbVarIdcode varIdCode;
};

struct IteratorHandle_t {
    IteratorItemType itemType = IteratorItemType::Module;
    std::vector<int32_t> moduleNodeIdxVec;
    std::vector<FsdbSignalEntry> signalEntryVec;
    size_t index = 0;
};
using IteratorHandle    = IteratorHandle_t;
using IteratorHandlePtr = IteratorHandle_t *;

struct FsdbModuleNode {
    std::string name;
    // Module definition name from FSDB scope metadata (e.g. "MidMod").
    // Empty means reader did not provide this field.
    std::string moduleName;
    int32_t parent = -1;
    std::vector<int32_t> children;
    std::vector<FsdbSignalEntry> signals;
};

std::vector<FsdbModuleNode> fsdbModuleTree;
bool fsdbModuleTreeBuilt = false;

struct FsdbModuleTreeContext {
    std::vector<int32_t> scopeStack;
};

static std::string normalizeFsdbSignalName(std::string_view rawName) {
    std::string normalized(rawName);
    std::size_t start = 0;
    while ((start = normalized.find('[', start)) != std::string::npos) {
        auto end = normalized.find(']', start);
        if (end == std::string::npos) {
            break;
        }
        normalized.erase(start, end - start + 1);
    }
    return normalized;
}

static bool isIgnoredFsdbModuleName(std::string_view name) {
    // FSDB may expose internal/generated scopes that are not user-facing RTL modules.
    // We skip those pseudo scopes but keep traversing their children.
    if (!name.empty() && name.front() == '$') {
        return true;
    }
    if (name.size() >= 4 && name.substr(name.size() - 4) == "_pkg") {
        return true;
    }
    if (name.find("unnamed$$_") != std::string_view::npos) {
        return true;
    }
    return false;
}

static void collectVisibleFsdbModuleNodeIdxVec(int32_t nodeIdx, std::vector<int32_t> &outputNodeIdxVec) {
    if (nodeIdx < 0 || nodeIdx >= static_cast<int32_t>(fsdbModuleTree.size())) {
        return;
    }

    const auto &node = fsdbModuleTree[nodeIdx];
    if (isIgnoredFsdbModuleName(node.name)) {
        // Flatten ignored wrappers to keep visible RTL hierarchy contiguous.
        for (auto childNodeIdx : node.children) {
            collectVisibleFsdbModuleNodeIdxVec(childNodeIdx, outputNodeIdxVec);
        }
    } else {
        outputNodeIdxVec.emplace_back(nodeIdx);
    }
}

static void collectFsdbSignalsFromIgnoredScopes(int32_t nodeIdx, std::vector<FsdbSignalEntry> &outputSignalVec) {
    if (nodeIdx < 0 || nodeIdx >= static_cast<int32_t>(fsdbModuleTree.size())) {
        return;
    }

    const auto &node = fsdbModuleTree[nodeIdx];
    if (!isIgnoredFsdbModuleName(node.name)) {
        return;
    }

    outputSignalVec.insert(outputSignalVec.end(), node.signals.begin(), node.signals.end());
    for (auto childNodeIdx : node.children) {
        collectFsdbSignalsFromIgnoredScopes(childNodeIdx, outputSignalVec);
    }
}

static bool_T fsdbModuleTreeCb(fsdbTreeCBType cbType, void *cbClientData, void *cbData) {
    auto *ctx = reinterpret_cast<FsdbModuleTreeContext *>(cbClientData);
    switch (cbType) {
    case FSDB_TREE_CBT_SCOPE: {
        auto *scopeData = reinterpret_cast<fsdbTreeCBDataScope *>(cbData);
        int32_t parent  = ctx->scopeStack.empty() ? -1 : ctx->scopeStack.back();
        int32_t nodeIdx = static_cast<int32_t>(fsdbModuleTree.size());
        // `scopeData->module` is the def-name source used by vpi_get_str(vpiDefName, ...).
        auto moduleName = scopeData->module ? std::string(scopeData->module) : std::string();
        fsdbModuleTree.emplace_back(FsdbModuleNode{
            .name       = std::string(scopeData->name),
            .moduleName = std::move(moduleName),
            .parent     = parent,
        });
        if (parent >= 0) {
            fsdbModuleTree[parent].children.emplace_back(nodeIdx);
        }
        ctx->scopeStack.emplace_back(nodeIdx);
        break;
    }
    case FSDB_TREE_CBT_VAR: {
        if (!ctx->scopeStack.empty()) {
            auto *varData      = reinterpret_cast<fsdbTreeCBDataVar *>(cbData);
            auto parentNodeIdx = ctx->scopeStack.back();
            auto signalName    = normalizeFsdbSignalName(varData->name);
            if (!signalName.empty()) {
                fsdbModuleTree[parentNodeIdx].signals.emplace_back(FsdbSignalEntry{
                    .name      = std::move(signalName),
                    .varIdCode = varData->u.idcode,
                });
            }
        }
        break;
    }
    case FSDB_TREE_CBT_UPSCOPE:
        if (!ctx->scopeStack.empty()) {
            ctx->scopeStack.pop_back();
        }
        break;
    default:
        break;
    }
    return TRUE;
}

static void ensureFsdbModuleTreeBuilt() {
    if (fsdbModuleTreeBuilt) {
        return;
    }

    fsdbModuleTree.clear();
    FsdbModuleTreeContext ctx;
    fsdb_wave_vpi::fsdbWaveVpi->fsdbObj->ffrReadScopeVarTree2(fsdbModuleTreeCb, reinterpret_cast<void *>(&ctx));
    fsdbModuleTreeBuilt = true;
}

static std::vector<int32_t> getFsdbTopModuleNodeIdxVec() {
    ensureFsdbModuleTreeBuilt();
    std::vector<int32_t> topModuleNodeIdxVec;
    for (int32_t i = 0; i < static_cast<int32_t>(fsdbModuleTree.size()); i++) {
        if (fsdbModuleTree[i].parent == -1) {
            collectVisibleFsdbModuleNodeIdxVec(i, topModuleNodeIdxVec);
        }
    }

    if (topModuleNodeIdxVec.empty()) {
        for (int32_t i = 0; i < static_cast<int32_t>(fsdbModuleTree.size()); i++) {
            if (fsdbModuleTree[i].parent == -1) {
                topModuleNodeIdxVec.emplace_back(i);
            }
        }
    }

    return topModuleNodeIdxVec;
}

static std::vector<int32_t> getFsdbVisibleChildModuleNodeIdxVec(int32_t parentNodeIdx) {
    ensureFsdbModuleTreeBuilt();
    std::vector<int32_t> childModuleNodeIdxVec;
    if (parentNodeIdx < 0 || parentNodeIdx >= static_cast<int32_t>(fsdbModuleTree.size())) {
        return childModuleNodeIdxVec;
    }

    for (auto childNodeIdx : fsdbModuleTree[parentNodeIdx].children) {
        collectVisibleFsdbModuleNodeIdxVec(childNodeIdx, childModuleNodeIdxVec);
    }

    return childModuleNodeIdxVec;
}

static std::vector<FsdbSignalEntry> getFsdbVisibleSignalEntryVec(int32_t parentNodeIdx) {
    ensureFsdbModuleTreeBuilt();
    std::vector<FsdbSignalEntry> signalEntryVec;
    if (parentNodeIdx < 0 || parentNodeIdx >= static_cast<int32_t>(fsdbModuleTree.size())) {
        return signalEntryVec;
    }

    const auto &parentNode = fsdbModuleTree[parentNodeIdx];
    signalEntryVec.insert(signalEntryVec.end(), parentNode.signals.begin(), parentNode.signals.end());
    for (auto childNodeIdx : parentNode.children) {
        collectFsdbSignalsFromIgnoredScopes(childNodeIdx, signalEntryVec);
    }

    std::unordered_set<std::string> seenSignalNames;
    std::vector<FsdbSignalEntry> dedupSignalEntryVec;
    dedupSignalEntryVec.reserve(signalEntryVec.size());
    for (auto &entry : signalEntryVec) {
        if (seenSignalNames.insert(entry.name).second) {
            dedupSignalEntryVec.emplace_back(std::move(entry));
        }
    }
    return dedupSignalEntryVec;
}

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
        endOfSimulationCb->cb_rtn(endOfSimulationCb.get());
#ifdef PROFILE_JIT
        jit_options::reportStatistic();
#endif
    }
}

std::string fsdbGetBinStr(vpiHandle object) {
    s_vpi_value v;
    v.format = vpiBinStrVal;
    vpi_get_value(object, &v);
    return std::string(v.value.str);
}

uint32_t fsdbGetSingleBitValue(vpiHandle object) {
    s_vpi_value v;
    v.format = vpiIntVal;
    vpi_get_value(object, &v); // Use `vpi_get_value` since we have Hot-Prefetch JIT in `vpi_get_value`
    return v.value.integer;
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

        auto t         = *cb_data_p;
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
        break;
    }
    case cbAfterDelay: {
        VL_FATAL(cb_data_p->time != nullptr && cb_data_p->time->type == vpiSimTime, "cb_data_p->time is nullptr or cb_data_p->time->type is not vpiSimTime");

        uint64_t time       = (((uint64_t)cb_data_p->time->high << 32) | (cb_data_p->time->low));
        uint64_t targetTime = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index] + time;
        if (targetTime > cursor.maxTime) {
            break;
        }

        uint64_t targetIndex = fsdb_wave_vpi::fsdbWaveVpi->findNearestTimeIndex(targetTime);
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

    auto varIdCode = fsdb_wave_vpi::fsdbWaveVpi->getVarIdCodeByName(name);
    if (varIdCode == -1) {
        return nullptr;
    }

    auto hdl = fsdb_wave_vpi::fsdbWaveVpi->fsdbObj->ffrCreateVCTrvsHdl(varIdCode);
    if (!hdl) {
        VL_FATAL(false, "Failed to create value change traverse handle, name: {}", std::string(name));
    }

    auto bitSize    = hdl->ffrGetBitSize();
    auto fsdbSigHdl = new fsdb_wave_vpi::FsdbSignalHandle{.name = std::string(name), .vcTrvsHdl = hdl, .varIdCode = varIdCode, .bitSize = bitSize};

    // Only for signals with bitSize <= 32. TODO: Support signals with bitSize > 32.
    fsdbSigHdl->canOpt = bitSize <= 32;

    auto vpiHdl = reinterpret_cast<vpiHandle>(fsdbSigHdl);

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

    auto iter = new IteratorHandle{};
    if (type == vpiModule) {
        std::vector<int32_t> moduleNodeIdxVec;
        if (refHandle == nullptr) {
            moduleNodeIdxVec = getFsdbTopModuleNodeIdxVec();
        } else {
            auto refHandleRaw = reinterpret_cast<void *>(refHandle);
            if (!moduleHandleSet.contains(refHandleRaw)) {
                delete iter;
                return nullptr;
            }

            auto moduleHdl = reinterpret_cast<ModuleHandlePtr>(refHandle);
            auto nodeIdx   = moduleHdl->fsdbNodeIdx;
            if (nodeIdx < 0 || nodeIdx >= static_cast<int32_t>(fsdbModuleTree.size())) {
                delete iter;
                return nullptr;
            }
            // `refHandle` is already a module handle: iterate direct visible children.
            moduleNodeIdxVec = getFsdbVisibleChildModuleNodeIdxVec(nodeIdx);
        }

        if (moduleNodeIdxVec.empty()) {
            delete iter;
            return nullptr;
        }

        iter->itemType         = IteratorItemType::Module;
        iter->moduleNodeIdxVec = std::move(moduleNodeIdxVec);
    } else {
        if (refHandle == nullptr) {
            delete iter;
            return nullptr;
        }
        auto refHandleRaw = reinterpret_cast<void *>(refHandle);
        if (!moduleHandleSet.contains(refHandleRaw)) {
            delete iter;
            return nullptr;
        }

        auto moduleHdl = reinterpret_cast<ModuleHandlePtr>(refHandle);
        auto nodeIdx   = moduleHdl->fsdbNodeIdx;
        if (nodeIdx < 0 || nodeIdx >= static_cast<int32_t>(fsdbModuleTree.size())) {
            delete iter;
            return nullptr;
        }

        auto signalEntryVec = getFsdbVisibleSignalEntryVec(nodeIdx);
        if (signalEntryVec.empty()) {
            delete iter;
            return nullptr;
        }

        iter->itemType       = IteratorItemType::Signal;
        iter->signalEntryVec = std::move(signalEntryVec);
    }

    auto ret = reinterpret_cast<vpiHandle>(iter);
    iteratorHandleSet.insert(reinterpret_cast<void *>(ret));
    iteratorTypeMap.insert_or_assign(reinterpret_cast<void *>(ret), type);
    return ret;
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

    auto iter = reinterpret_cast<IteratorHandlePtr>(iterator);
    if (iter->itemType == IteratorItemType::Module) {
        if (iter->index >= iter->moduleNodeIdxVec.size()) {
            // End of iteration: free iterator immediately to match VPI scan semantics.
            iteratorHandleSet.erase(iteratorRaw);
            iteratorTypeMap.erase(iteratorRaw);
            delete iter;
            return nullptr;
        }

        auto nodeIdx = iter->moduleNodeIdxVec[iter->index];
        iter->index++;
        auto moduleHdl = new ModuleHandle{.fsdbNodeIdx = nodeIdx};
        auto ret       = reinterpret_cast<vpiHandle>(moduleHdl);
        moduleHandleSet.insert(reinterpret_cast<void *>(ret));
        return ret;
    }

    while (iter->index < iter->signalEntryVec.size()) {
        auto signalEntry = iter->signalEntryVec[iter->index];
        iter->index++;

        auto hdl = fsdb_wave_vpi::fsdbWaveVpi->fsdbObj->ffrCreateVCTrvsHdl(signalEntry.varIdCode);
        if (hdl == nullptr) {
            continue;
        }

        auto varType = hdl->ffrGetVarType();
        if (iterType == vpiNet && varType != FSDB_VT_VCD_WIRE) {
            hdl->ffrFree();
            continue;
        }
        if (iterType == vpiReg && varType == FSDB_VT_VCD_WIRE) {
            hdl->ffrFree();
            continue;
        }
        if (iterType == vpiMemory) {
            hdl->ffrFree();
            continue;
        }

        auto bitSize    = static_cast<size_t>(hdl->ffrGetBitSize());
        auto fsdbSigHdl = new fsdb_wave_vpi::FsdbSignalHandle{
            .name      = signalEntry.name,
            .vcTrvsHdl = hdl,
            .varIdCode = signalEntry.varIdCode,
            .bitSize   = bitSize,
        };
        fsdbSigHdl->canOpt = bitSize <= 32;
        auto ret           = reinterpret_cast<vpiHandle>(fsdbSigHdl);
        signalHandleSet.insert(reinterpret_cast<void *>(ret));
        return ret;
    }

    iteratorHandleSet.erase(iteratorRaw);
    iteratorTypeMap.erase(iteratorRaw);
    delete iter;
    return nullptr;
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
        return reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandlePtr>(sigHdl)->bitSize;
    case vpiTimePrecision: {
        auto scaleUnit = fsdb_wave_vpi::fsdbWaveVpi->fsdbObj->ffrGetScaleUnit();
        return fsdbScaleUnitToVpiPrecision(scaleUnit);
    }
    default:
        VL_FATAL(false, "Unimplemented property: {}", property);
    }
}

void vpi_get_time(vpiHandle object, p_vpi_time time_p) {
    if (time_p == nullptr) {
        return;
    }

    uint64_t simTime = 0;
    simTime          = fsdb_wave_vpi::fsdbWaveVpi->xtagU64Vec[cursor.index];

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
            auto moduleHdl = reinterpret_cast<ModuleHandlePtr>(sigHdl);
            auto nodeIdx   = moduleHdl->fsdbNodeIdx;
            if (nodeIdx < 0 || nodeIdx >= static_cast<int32_t>(fsdbModuleTree.size())) {
                return nullptr;
            }
            return const_cast<PLI_BYTE8 *>(fsdbModuleTree[nodeIdx].name.c_str());
        }

        if (signalHandleSet.contains(sigHdlRaw)) {
            return const_cast<PLI_BYTE8 *>(reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandlePtr>(sigHdl)->name.c_str());
        }
        return nullptr;
    }
    case vpiType: {
        if (moduleHandleSet.contains(sigHdlRaw)) {
            return const_cast<PLI_BYTE8 *>("vpiModule");
        }
        auto varType = reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandle *>(sigHdl)->vcTrvsHdl->ffrGetVarType();
        switch (varType) {
        case FSDB_VT_VCD_REG:
            return const_cast<PLI_BYTE8 *>("vpiReg");
        case FSDB_VT_VCD_WIRE:
            return const_cast<PLI_BYTE8 *>("vpiNet");
        default:
            return const_cast<PLI_BYTE8 *>("vpiReg");
        }
    }
    case vpiDefName: {
        if (!moduleHandleSet.contains(sigHdlRaw)) {
            return nullptr;
        }
        // FSDB backend provides module definition names from scope tree metadata.
        auto moduleHdl = reinterpret_cast<ModuleHandlePtr>(sigHdl);
        auto nodeIdx   = moduleHdl->fsdbNodeIdx;
        if (nodeIdx < 0 || nodeIdx >= static_cast<int32_t>(fsdbModuleTree.size())) {
            return nullptr;
        }
        const auto &moduleName = fsdbModuleTree[nodeIdx].moduleName;
        return moduleName.empty() ? nullptr : const_cast<PLI_BYTE8 *>(moduleName.c_str());
    }
    default:
        VL_FATAL(false, "Unimplemented property: {}", property);
    }
};

static void fsdbOptThreadTask(const std::string &fsdbFileName, const std::vector<fsdbXTag> &xtagVec, fsdb_wave_vpi::FsdbSignalHandlePtr fsdbSigHdl) {
    if (vpiControlTerminate) {
        return;
    }

    static std::mutex optMutex;
    // Shared ffrObject: all JIT threads share one FSDB file handle (under optMutex)
    // to avoid per-thread memory overhead from separate decompression buffers.
    // Intentionally never freed — lives until process exit.
    static ffrObject *sharedFsdbObj = nullptr;

#ifdef PROFILE_JIT
    jit_options::statistic.jitOptTaskCnt.store(jit_options::statistic.jitOptTaskCnt.load() + 1);
#endif

    auto verboseJIT = jit_options::verboseJIT;

    // VCTrvsHdl — updated before each optFunc call, captured by reference in lambda.
    // ffrVCTrvsHdl is already a pointer type (ffrVCIterOne*).
    ffrVCTrvsHdl hdlPtr = nullptr;
    uint_T bitSize      = 0;

    auto optFunc = [&hdlPtr, &bitSize, &xtagVec, &fsdbFileName, fsdbSigHdl](uint64_t startIdx, uint64_t finishIdx) {
        constexpr uint64_t PROGRESS_BATCH = 1024;
        byte_T *retVC;
        fsdbBytesPerBit bpb;

        auto &optValueVec = fsdbSigHdl->optValueVec;
        auto baseIdx      = fsdbSigHdl->optBaseIdx.load(std::memory_order_relaxed);

        for (auto idx = startIdx; idx < finishIdx; idx++) {
            uint32_t tmpVal = 0;
            auto time       = xtagVec[idx];
            time.hltag.L    = time.hltag.L + 1;

            if (FSDB_RC_SUCCESS != hdlPtr->ffrGotoXTag(&time)) [[unlikely]] {
                VL_FATAL(false, "Failed to call hdl->ffrGotoXtag(), time.hltag.L: {}, time.hltag.H: {}, idx: {}, fsdbSigHdl->name: {}, fsdbFileName: {}", time.hltag.L, time.hltag.H, idx, fsdbSigHdl->name, fsdbFileName);
            }

            if (FSDB_RC_SUCCESS != hdlPtr->ffrGetVC(&retVC)) [[unlikely]] {
                VL_FATAL(false, "hdl->ffrGetVC() failed!");
            }

            bpb = hdlPtr->ffrGetBytesPerBit();

            if (bitSize == 1) {
                switch (bpb) {
                [[likely]] case FSDB_BYTES_PER_BIT_1B: {
                    switch (retVC[0]) {
                    case FSDB_BT_VCD_X: // treat `X` as `0`
                    case FSDB_BT_VCD_Z: // treat `Z` as `0`
                    case FSDB_BT_VCD_0:
                        optValueVec[idx - baseIdx] = 0;
                        break;
                    case FSDB_BT_VCD_1:
                        optValueVec[idx - baseIdx] = 1;
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
                    for (uint_T i = 0; i < bitSize; i++) {
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
                optValueVec[idx - baseIdx] = tmpVal;
            }

            // Progressive read: update optFinishIdx periodically so vpi_get_value
            // can start using fast path before the entire window is compiled.
            if ((idx - startIdx + 1) % PROGRESS_BATCH == 0) {
                fsdbSigHdl->optFinishIdx.store(idx + 1, std::memory_order_release);
            }
        }
        fsdbSigHdl->optFinishIdx.store(finishIdx, std::memory_order_release);
    };

    // Helper: create VCTrvsHdl on the shared ffrObject for this signal.
    auto createHdl = [&hdlPtr, &bitSize, &fsdbSigHdl, &fsdbFileName]() {
        hdlPtr = sharedFsdbObj->ffrCreateVCTrvsHdl(fsdbSigHdl->varIdCode);
        VL_FATAL(hdlPtr != nullptr, "Failed to create hdl, fsdbFileName: {}, fsdbSigHdl->name: {}, fsdbSigHdl->varIdCode: {}", fsdbFileName, fsdbSigHdl->name, fsdbSigHdl->varIdCode);
        bitSize = hdlPtr->ffrGetBitSize();
        VL_FATAL(bitSize <= 32, "For now we only optimize signals with bitSize <= 32, bitSize: {}", bitSize);
    };

    // Helper: free the VCTrvsHdl after compilation.
    auto freeHdl = [&hdlPtr]() {
        if (hdlPtr) {
            hdlPtr->ffrFree();
            hdlPtr = nullptr;
        }
    };

    // === Initial compilation (under optMutex) ===
    {
        std::lock_guard<std::mutex> lock(optMutex);

        // Lazy init shared ffrObject
        if (!sharedFsdbObj) {
            sharedFsdbObj = ffrObject::ffrOpenNonSharedObj(const_cast<char *>(fsdbFileName.c_str()));
            VL_FATAL(sharedFsdbObj != nullptr, "Failed to open fsdbObj, fsdbFileName: {}", fsdbFileName);
            sharedFsdbObj->ffrReadScopeVarTree();
        }

        if (verboseJIT && !is_quiet_mode()) {
            fmt::println("[fsdbOptThreadTask] First optimization start! {} currentCursorIdx:{}, windowSize:{}", fsdbSigHdl->name, cursor.index, jit_options::compileWindowSize);
            fflush(stdout);
        }

        createHdl();

        auto &optValueVec     = fsdbSigHdl->optValueVec;
        auto currentCursorIdx = cursor.index;
        auto optFinishIdx     = currentCursorIdx + jit_options::compileWindowSize;

        if (optFinishIdx >= xtagVec.size()) {
            optFinishIdx = xtagVec.size() - 1;
        }

        // Sliding window: allocate only what's needed instead of the full waveform.
        auto windowCapacity = std::min(jit_options::compileWindowSize * 2, xtagVec.size());
        fsdbSigHdl->optBaseIdx.store(currentCursorIdx, std::memory_order_relaxed);
        optValueVec.resize(windowCapacity);

        optFunc(currentCursorIdx, optFinishIdx);
        freeHdl();
    }
    // optMutex released

#ifdef PROFILE_JIT
    jit_options::statistic.jitOptTaskFirstFinishCnt.store(jit_options::statistic.jitOptTaskFirstFinishCnt.load() + 1);
#endif

    if (verboseJIT && !is_quiet_mode()) {
        fmt::println("[fsdbOptThreadTask] First optimization finish! {} windowSize:{}", fsdbSigHdl->name, jit_options::compileWindowSize);
        fflush(stdout);
    }

    // === Recompilation loop ===
    // Recompilation also acquires optMutex because FsdbReader is not thread-safe.
    int optCnt = 0;
    std::unique_lock<std::mutex> continueOptLock(fsdbSigHdl->mtx);
    while (true) {
        fsdbSigHdl->cv.wait(continueOptLock, [fsdbSigHdl]() { return fsdbSigHdl->continueOpt; });

        {
            std::lock_guard<std::mutex> lock(optMutex);

            createHdl();

            auto optFinish    = false;
            auto optStartIdx  = std::max(cursor.index, fsdbSigHdl->optFinishIdx.load(std::memory_order_relaxed));
            auto optFinishIdx = optStartIdx + jit_options::compileWindowSize;
            if (optFinishIdx >= xtagVec.size()) {
                optFinishIdx = xtagVec.size() - 1;
                optFinish    = true;
            }

            // Sliding window: check if the next window fits in the current allocation.
            auto neededEnd = optFinishIdx - fsdbSigHdl->optBaseIdx.load(std::memory_order_relaxed);
            if (neededEnd > fsdbSigHdl->optValueVec.size()) {
                // Reset optFinishIdx first to force main thread onto slow path during the slide.
                fsdbSigHdl->optFinishIdx.store(0, std::memory_order_release);
                fsdbSigHdl->optBaseIdx.store(optStartIdx, std::memory_order_release);
                auto newCapacity = std::min(jit_options::compileWindowSize * 2, xtagVec.size() - optStartIdx);
                fsdbSigHdl->optValueVec.resize(newCapacity);
            }

            optFunc(optStartIdx, optFinishIdx);
            freeHdl();

            // optFinishIdx is already updated progressively by optFunc
            fsdbSigHdl->continueOpt = false;
            optCnt++;

            if (optFinish) {
                break;
            }
        }
        // optMutex released

        if (verboseJIT && !is_quiet_mode()) {
            fmt::println("[fsdbOptThreadTask] [{}] Continue optimization... {}", optCnt, fsdbSigHdl->name);
            fflush(stdout);
        }
    }

    jit_options::optThreadCnt.fetch_sub(1, std::memory_order_relaxed);

    if (verboseJIT && !is_quiet_mode()) {
        fmt::println("[fsdbOptThreadTask] Optimization finish! total compile times:{} signalName:{}", optCnt, fsdbSigHdl->name);
        fflush(stdout);
    }
}

void vpi_get_value(vpiHandle sigHdl, p_vpi_value value_p) {
#ifdef PROFILE_JIT
    auto _totalReadStart = std::chrono::high_resolution_clock::now();
#endif

    static byte_T buffer[FSDB_MAX_BIT_SIZE + 1];
    static s_vpi_vecval vpiValueVecs[100];
    auto fsdbSigHdl = reinterpret_cast<fsdb_wave_vpi::FsdbSignalHandlePtr>(sigHdl);

    if (!fsdbSigHdl->canOpt || !jit_options::enableJIT)
        goto ReadFromFSDB;

    {
        // Progressive read: check optFinishIdx (atomic) to determine if fast path is available.
        // No need to wait for the entire compilation window to finish.
        auto _optFinishIdx = fsdbSigHdl->optFinishIdx.load(std::memory_order_acquire);
        if (fsdbSigHdl->doOpt && _optFinishIdx > 0) {
            auto _optBaseIdx = fsdbSigHdl->optBaseIdx.load(std::memory_order_acquire);
            if (cursor.index < _optBaseIdx || cursor.index >= _optFinishIdx) {
                // fmt::println("[WARN] JIT need recompile! cursor.index:{} optFinishIdx:{} signalName:{}", cursor.index, _optFinishIdx, fsdbSigHdl->name);
                goto ReadFromFSDB;
            }

            if (!fsdbSigHdl->continueOpt && cursor.index >= (_optFinishIdx - jit_options::recompileWindowSize)) {
                // fmt::println("[WARN] continue optimization... {} cursor.index:{} optFinishIdx:{}", fsdbSigHdl->name, cursor.index, _optFinishIdx);
                fsdbSigHdl->continueOpt = true;
                fsdbSigHdl->cv.notify_one();
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
                value_p->value.integer = fsdbSigHdl->optValueVec[_optLocalIdx];
                break;
            }
            case vpiVectorVal: {
                vpiValueVecs[0].aval  = fsdbSigHdl->optValueVec[_optLocalIdx];
                vpiValueVecs[0].bval  = 0;
                value_p->value.vector = vpiValueVecs;
                break;
            }
            case vpiHexStrVal: {
                const int bufferSize = 8; // TODO: 4 * 8 = 32, if support 64 bit signal, this value should be set to 16.
                uint32_to_hex_str(reinterpret_cast<char *>(buffer), bufferSize, fsdbSigHdl->optValueVec[_optLocalIdx]);
                value_p->value.str = (char *)buffer;
                break;
            }
            case vpiBinStrVal: {
                auto &bitSize = fsdbSigHdl->bitSize;
                auto value    = fsdbSigHdl->optValueVec[_optLocalIdx];
                for (int i = 0; i < bitSize; i++) {
                    buffer[bitSize - 1 - i] = (value & (1 << i)) ? '1' : '0';
                }
                buffer[bitSize]    = '\0';
                value_p->value.str = (char *)buffer;
                break;
            }
            case vpiDecStrVal: {
                // Hot-Prefetch JIT path: 2-state only, no X/Z possible
                // Notice: buffer size 16 is sufficient for uint32_t max (4294967295 = 10 chars + '\0').
                // Update this if optValueVec type changes to a wider integer type.
                uint32_to_dec_str(reinterpret_cast<char *>(buffer), 16, fsdbSigHdl->optValueVec[_optLocalIdx]);
                value_p->value.str = (char *)buffer;
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

    if (!fsdbSigHdl->doOpt) {
        fsdbSigHdl->readCnt++;
        // fmt::println("[WARN] readCnt: {} signalName: {} doOpt: {} bitSize: {}", fsdbSigHdl->readCnt, fsdbSigHdl->name, fsdbSigHdl->doOpt, fsdbSigHdl->bitSize);

        // Hot-Prefetch JIT: trigger prefetch when read count exceeds threshold
        // Only for signals with bitSize <= 32. TODO: Support signals with bitSize > 32.
        if (fsdbSigHdl->readCnt >= jit_options::hotAccessThreshold) {
            auto _jitOptThreadCnt = jit_options::optThreadCnt.load(std::memory_order_relaxed);
            while (_jitOptThreadCnt <= jit_options::maxOptThreads) {
                if (jit_options::optThreadCnt.compare_exchange_weak(_jitOptThreadCnt, _jitOptThreadCnt + 1, std::memory_order_relaxed)) {
                    fsdbSigHdl->doOpt       = true;
                    fsdbSigHdl->continueOpt = false;
                    fsdbSigHdl->optThread   = std::thread([fsdbSigHdl] { fsdbOptThreadTask(fsdb_wave_vpi::fsdbWaveVpi->waveFileName, fsdb_wave_vpi::fsdbWaveVpi->xtagVec, fsdbSigHdl); });
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

ReadFromFSDB:

#ifdef PROFILE_JIT
    jit_options::statistic.readFromNormal++;
    if (!fsdbSigHdl->canOpt) {
        jit_options::statistic.unOptimizableRead++;
    }
#endif

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
        static const char hexLookUpTable[] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
        switch (bpb) {
        [[likely]] case FSDB_BYTES_PER_BIT_1B: {
            int bufferIdx = 0;
            int tmpVal    = 0;
            int tmpIdx    = 0;
            bool hasX     = false;
            bool hasZ     = false;
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
                    hasX = true;
                    break;
                case FSDB_BT_VCD_Z:
                    hasZ = true;
                    break;
                default:
                    VL_FATAL(false, "unknown verilog bit type found. i: {}", i);
                }
                tmpIdx++;
                if (tmpIdx == 4) {
                    if (hasX)
                        buffer[chunkSize - 1 - bufferIdx] = 'x';
                    else if (hasZ)
                        buffer[chunkSize - 1 - bufferIdx] = 'z';
                    else
                        buffer[chunkSize - 1 - bufferIdx] = hexLookUpTable[tmpVal];
                    tmpVal = tmpIdx = 0;
                    hasX = hasZ = false;
                    bufferIdx++;
                }
            }
            if (tmpIdx != 0) {
                if (hasX)
                    buffer[chunkSize - 1 - bufferIdx] = 'x';
                else if (hasZ)
                    buffer[chunkSize - 1 - bufferIdx] = 'z';
                else
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
                    buffer[i] = 'x';
                    break;
                case FSDB_BT_VCD_Z:
                    buffer[i] = 'z';
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
    case vpiDecStrVal: {
        // Get the value as integer first, then convert to decimal string.
        // For X/Z values, iterate bits to check for X/Z presence.
        switch (bpb) {
        [[likely]] case FSDB_BYTES_PER_BIT_1B: {
            uint64_t intVal = 0;
            bool hasXZ      = false;
            for (int i = 0; i < bitSize; i++) {
                switch (retVC[i]) {
                case FSDB_BT_VCD_0:
                    break;
                case FSDB_BT_VCD_1:
                    intVal += static_cast<uint64_t>(1) << (bitSize - i - 1);
                    break;
                case FSDB_BT_VCD_X:
                case FSDB_BT_VCD_Z:
                    hasXZ = true;
                    break;
                default:
                    VL_FATAL(false, "unknown verilog bit type found.");
                }
            }
            if (hasXZ) {
                buffer[0] = 'x';
                buffer[1] = '\0';
            } else {
                snprintf(reinterpret_cast<char *>(buffer), sizeof(buffer), "%" PRIu64, intVal);
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
        value_p->value.str = (char *)buffer;
        break;
    }
    default: {
        VL_FATAL(false, "Unknown value format: {}", value_p->format);
    }
    }

#ifdef PROFILE_JIT
    auto _normalEnd         = std::chrono::high_resolution_clock::now();
    auto _normalElapsedTime = std::chrono::duration_cast<std::chrono::nanoseconds>(_normalEnd - _totalReadStart).count();
    jit_options::statistic.readFromNormalTime += _normalElapsedTime;
    jit_options::statistic.totalReadTime += _normalElapsedTime;
#endif
}

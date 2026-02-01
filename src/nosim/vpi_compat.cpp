#include "vpi_compat.h"
#include "vpi_user.h"

namespace vpi_compat {
std::unique_ptr<s_cb_data> startOfSimulationCb = nullptr;
std::unique_ptr<s_cb_data> endOfSimulationCb   = nullptr;

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
    }
}

} // namespace vpi_compat

using namespace vpi_compat;

PLI_INT32 vpi_free_object(vpiHandle object) {
    // PANIC("vpi_free_object not implemented");
    return 0;
}

vpiHandle vpi_register_cb(p_cb_data cb_data_p) {
    switch (cb_data_p->reason) {
    case cbStartOfSimulation:
        ASSERT(startOfSimulationCb == nullptr, "startOfSimulationCb is not nullptr");
        startOfSimulationCb = std::make_unique<s_cb_data>(*cb_data_p);
        break;
    case cbEndOfSimulation:
        ASSERT(endOfSimulationCb == nullptr, "endOfSimulationCb is not nullptr");
        endOfSimulationCb = std::make_unique<s_cb_data>(*cb_data_p);
        break;
    case cbNextSimTime:
        break;
    default:
        PANIC("vpi_register_cb not implemented", cb_data_p->reason);
        break;
    }
    return nullptr;
}

PLI_INT32 vpi_remove_cb(vpiHandle cb_obj) {
    PANIC("vpi_remove_cb not implemented");
    return 0;
};

vpiHandle vpi_iterate(PLI_INT32 type, vpiHandle refHandle) {
    PANIC("vpi_iterate not implemented");
    return nullptr;
}

vpiHandle vpi_scan(vpiHandle iterator) {
    PANIC("vpi_scan not implemented");
    return nullptr;
}

PLI_BYTE8 *vpi_get_str(PLI_INT32 property, vpiHandle object) {
    PANIC("vpi_get_str not implemented");
    return nullptr;
}

PLI_INT32 vpi_get(PLI_INT32 property, vpiHandle object) {
    PANIC("vpi_get not implemented");
    return 0;
}

vpiHandle vpi_handle_by_name(PLI_BYTE8 *name, vpiHandle scope) {
    PANIC("vpi_handle_by_name not implemented");
    return nullptr;
}

void vpi_get_value(vpiHandle expr, p_vpi_value value_p) { PANIC("vpi_get_value not implemented"); }

void vpi_get_time(vpiHandle object, p_vpi_time time_p) { PANIC("vpi_get_time not implemented"); }

PLI_INT32 vpi_control(PLI_INT32 operation, ...) {
    switch (operation) {
    case vpiStop:
    case vpiFinish:
        endOfSimulation();
        exit(0);
    default:
        PANIC("Unsupported operation: {}", operation);
        break;
    }
    return 0;
}

vpiHandle vpi_handle_by_index(vpiHandle object, PLI_INT32 indx) {
    PANIC("vpi_handle_by_index not implemented");
    return nullptr;
}

vpiHandle vpi_put_value(vpiHandle object, p_vpi_value value_p, p_vpi_time time_p, PLI_INT32 flags) {
    PANIC("vpi_put_value not implemented");
    return nullptr;
}

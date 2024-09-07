#include "lua_vpi.h"
#include "vpi_callback.h"
#include "mimalloc-new-delete.h"

TO_LUA void verilua_time_callback(uint64_t time, TaskID id) {   
    s_cb_data cb_data;
    cb_data.reason = cbAfterDelay,
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto task_id = *reinterpret_cast<TaskID *>(cb_data->user_data);
        execute_sim_event(task_id);
        
        delete reinterpret_cast<TaskID *>(cb_data->user_data);
        return 0;
    };
    cb_data.obj = nullptr;
    cb_data.value = nullptr;
    cb_data.time = new s_vpi_time;
    cb_data.time->type = vpiSimTime;
    cb_data.time->low = time & 0xFFFFFFFF;
    cb_data.time->high = (time >> 32) & 0xFFFFFFFF;

    auto id_p = new TaskID(id);
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(id_p);
    vpi_register_cb(&cb_data);
}

VERILUA_PRIVATE static inline void register_edge_callback_basic(vpiHandle handle, int edge_type, TaskID id) {
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto &env = VeriluaEnv::get_instance();

        // vpi_get_value(cb_data->obj, cb_data->value);
        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;

        EdgeCbData *user_data = reinterpret_cast<EdgeCbData *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event(user_data->task_id);
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData *>(cb_data->user_data);
        }

        return 0;
    };

    EdgeValue expected_value;
    switch ((EdgeType)edge_type) {
        case EdgeType::POSEDGE:
            expected_value = EdgeValue::HIGH;
            break;
        case EdgeType::NEGEDGE:
            expected_value = EdgeValue::LOW;
            break;
        case EdgeType::EDGE:
            expected_value = EdgeValue::DONTCARE;
            break;
        default:
            VL_FATAL(false, "Invalid edge type: {}", edge_type);
    }

    EdgeCbData *user_data = new EdgeCbData;
    user_data->task_id = id;
    user_data->expected_value = expected_value;
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}

TO_LUA void verilua_posedge_callback(const char *path, TaskID id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: {}", path);
    register_edge_callback_basic(signal_handle, 0, id);
}

TO_LUA void verilua_posedge_callback_hdl(long long handle, TaskID id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, 0, id);
}

TO_LUA void verilua_negedge_callback(const char *path, TaskID id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: {}", path);
    register_edge_callback_basic(signal_handle, 1, id);
}

TO_LUA void verilua_negedge_callback_hdl(long long handle, TaskID id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, 1, id);
}

TO_LUA void verilua_edge_callback(const char *path, int id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: {}", path);
    register_edge_callback_basic(signal_handle, 2, id);
}

TO_LUA void verilua_edge_callback_hdl(long long handle, TaskID id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, 2, id);
}


TO_LUA void c_register_edge_callback(const char *path, int edge_type, TaskID id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: {}", path);
    register_edge_callback_basic(signal_handle, edge_type, id);
}

TO_LUA void c_register_edge_callback_hdl(long long handle, int edge_type, TaskID id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, edge_type, id);
}

TO_LUA void c_register_edge_callback_hdl_always(long long handle, int edge_type, TaskID id) {
    auto &env = VeriluaEnv::get_instance();
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        // vpi_get_value(cb_data->obj, cb_data->value);
        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;

        EdgeCbData *user_data = reinterpret_cast<EdgeCbData *>(cb_data->user_data); 
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event(user_data->task_id);
        }

        return 0;
    };

    EdgeValue expected_value;
    switch ((EdgeType)edge_type) {
        case EdgeType::POSEDGE:
            expected_value = EdgeValue::HIGH;
            break;
        case EdgeType::NEGEDGE:
            expected_value = EdgeValue::LOW;
            break;
        case EdgeType::EDGE:
            expected_value = EdgeValue::DONTCARE;
            break;
        default:
            VL_FATAL(false, "Invalid edge type: {}", edge_type);
    }

    EdgeCbData *user_data = new EdgeCbData;
    user_data->task_id = id;
    user_data->expected_value = expected_value;
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = actual_handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = (PLI_BYTE8 *)user_data;
    
    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}

TO_LUA void verilua_posedge_callback_hdl_always(long long handle, TaskID id) {
    auto &env = VeriluaEnv::get_instance();
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        // vpi_get_value(cb_data->obj, cb_data->value);
        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;

        EdgeCbData *user_data = reinterpret_cast<EdgeCbData *>(cb_data->user_data); 
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event(user_data->task_id);
        }

        return 0;
    };

    EdgeCbData *user_data = new EdgeCbData;
    user_data->task_id = id;
    user_data->expected_value = EdgeValue::HIGH; // Posedge
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = actual_handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = (PLI_BYTE8 *)user_data;

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}

TO_LUA void verilua_negedge_callback_hdl_always(long long handle, TaskID id) {
    auto &env = VeriluaEnv::get_instance();
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        // vpi_get_value(cb_data->obj, cb_data->value);
        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;

        EdgeCbData *user_data = reinterpret_cast<EdgeCbData *>(cb_data->user_data); 
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event(user_data->task_id);
        }

        return 0;
    };

    EdgeCbData *user_data = new EdgeCbData;
    user_data->task_id = id;
    user_data->expected_value = EdgeValue::LOW; // Negedge
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();

    cb_data.obj = actual_handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = (PLI_BYTE8 *)user_data;
    
    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}

TO_LUA void c_register_read_write_synch_callback(TaskID id) {
    s_cb_data cb_data;

    VL_INFO("Register cbReadWriteSynch {}\n", id);

    cb_data.reason = cbReadWriteSynch;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto task_id = *reinterpret_cast<TaskID *>(cb_data->user_data);
        execute_sim_event(task_id);

        delete reinterpret_cast<TaskID *>(cb_data->user_data);
        return 0;
    };
    cb_data.time = nullptr;
    cb_data.value = nullptr;

    auto id_p = new TaskID(id);
    cb_data.user_data = (PLI_BYTE8 *)id_p;

    VL_FATAL(vpi_register_cb(&cb_data) != nullptr);
}

VERILUA_PRIVATE static PLI_INT32 start_callback(p_cb_data cb_data) {
    VL_INFO("[cbStartOfSimulation] enter start_callback()\n");

    VeriluaEnv::get_instance().initialize();
    
    VL_INFO("[cbStartOfSimulation] leave start_callback()\n");
    return 0;
}

VERILUA_PRIVATE static PLI_INT32 final_callback(p_cb_data cb_data) {
    VL_INFO("[cbEndOfSimulation] enter final_callback()\n");

    VeriluaEnv::get_instance().finalize();

    VL_INFO("[cbEndOfSimulation] leave final_callback()\n");
    return 0;
}

VERILUA_PRIVATE void register_start_calllback(void) {
    static bool registered = false;
    if(registered) return;

    vpiHandle callback_handle;
    s_cb_data cb_data_s;

    cb_data_s.reason = cbStartOfSimulation;
    cb_data_s.cb_rtn = start_callback;
    cb_data_s.obj = nullptr;
    cb_data_s.time = nullptr;
    cb_data_s.value = nullptr;
    cb_data_s.user_data = nullptr;

    callback_handle = vpi_register_cb(&cb_data_s);
    vpi_free_object(callback_handle);

    VL_INFO("register_start_calllback()\n");
    registered = true;
}

VERILUA_PRIVATE void register_final_calllback(void) {
    static bool registered = false;
    if (registered) return;

    vpiHandle callback_handle;
    s_cb_data cb_data_s;

    cb_data_s.reason = cbEndOfSimulation;
    cb_data_s.cb_rtn = final_callback;
    cb_data_s.obj = nullptr;
    cb_data_s.time = nullptr;
    cb_data_s.value = nullptr;
    cb_data_s.user_data = nullptr;

    callback_handle = vpi_register_cb(&cb_data_s);
    vpi_free_object(callback_handle); // Free the callback handle

    VL_INFO("register_final_calllback()\n");
    registered = true;
}

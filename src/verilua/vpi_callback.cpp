#include "lua_vpi.h"
#include "vpi_callback.h"

#ifdef USE_MIMALLOC
#include "mimalloc-new-delete.h"
#endif

#define CASE_STR(_X) \
    case _X:         \
        return #_X

VERILUA_PRIVATE const char *reason_to_string(int reason) {
    switch (reason) {
        CASE_STR(cbValueChange);
        CASE_STR(cbAtStartOfSimTime);
        CASE_STR(cbReadWriteSynch);
        CASE_STR(cbReadOnlySynch);
        CASE_STR(cbNextSimTime);
        CASE_STR(cbAfterDelay);
        CASE_STR(cbStartOfSimulation);
        CASE_STR(cbEndOfSimulation);

        default:
            return "unknown";
    }
}

VERILUA_PRIVATE inline static EdgeValue edge_type_to_value(EdgeType &edge_type) {
    EdgeValue expected_value;
    switch (edge_type) {
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
            VL_FATAL(false, "Invalid edge type: %d", (int)edge_type);
    }
    return expected_value;
}

#ifdef VL_DEF_OPT_MERGE_CALLBACK
#include "gen_register_edge_callback.h"
#endif

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

VERILUA_PRIVATE static inline void register_edge_callback_basic(vpiHandle handle, EdgeType edge_type, TaskID id) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_OPT_MERGE_CALLBACK
    switch (edge_type) {
        case EdgeType::POSEDGE:
            env.pending_posedge_cb_map[handle].emplace_back(id);
            break;
        case EdgeType::NEGEDGE:
            env.pending_negedge_cb_map[handle].emplace_back(id);
            break;
        case EdgeType::EDGE:
            env.pending_edge_cb_map[handle].emplace_back(id);
            break;
        default:
            VL_FATAL(false, "Unkonwn edge type => %d", (int)edge_type);
    }
#else
    env.pending_edge_cb_map[handle].emplace_back(CallbackInfo{(TaskID)id, edge_type});
#endif
}

TO_LUA void verilua_posedge_callback(const char *path, TaskID id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: %s", path);
    register_edge_callback_basic(signal_handle, EdgeType::POSEDGE, id);
}

TO_LUA void verilua_posedge_callback_hdl(long long handle, TaskID id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, EdgeType::POSEDGE, id);
}

TO_LUA void verilua_negedge_callback(const char *path, TaskID id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: %s", path);
    register_edge_callback_basic(signal_handle, EdgeType::NEGEDGE, id);
}

TO_LUA void verilua_negedge_callback_hdl(long long handle, TaskID id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, EdgeType::NEGEDGE, id);
}

TO_LUA void verilua_edge_callback(const char *path, int id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: %s", path);
    register_edge_callback_basic(signal_handle, EdgeType::EDGE, id);
}

TO_LUA void verilua_edge_callback_hdl(long long handle, TaskID id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, EdgeType::EDGE, id);
}


TO_LUA void c_register_edge_callback(const char *path, int edge_type, TaskID id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: %s", path);
    register_edge_callback_basic(signal_handle, (EdgeType)edge_type, id);
}

TO_LUA void c_register_edge_callback_hdl(long long handle, int edge_type, TaskID id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, (EdgeType)edge_type, id);
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
            VL_FATAL(false, "Invalid edge type: %d", edge_type);
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

    VL_STATIC_DEBUG("Register cbReadWriteSynch %d\n", id);

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

VERILUA_PRIVATE static PLI_INT32 next_sim_time_callback(p_cb_data cb_data) {
    // VL_INFO("[cbNextSimTime] enter next_sim_time_callback()\n");

    auto &env = VeriluaEnv::get_instance();

    static auto register_edge_callback = [](vpiHandle &handle, TaskID id, EdgeType edge_type) {
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

        EdgeCbData *user_data = new EdgeCbData;
        user_data->task_id = id;
        user_data->expected_value = edge_type_to_value(edge_type);
        user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
        user_data->vpi_value.format = vpiIntVal;
        user_data->vpi_time.type = vpiSuppressTime;

        cb_data.obj = handle;
        cb_data.time = &user_data->vpi_time;
        cb_data.value = &user_data->vpi_value;
        cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

        env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
    };

#ifdef VL_DEF_OPT_MERGE_CALLBACK
    #include "gen_callback_policy.h"
    env.pending_posedge_cb_map.clear();
    env.pending_negedge_cb_map.clear();
    env.pending_edge_cb_map.clear();
#else
    for (const auto& pair : env.pending_edge_cb_map) {
        vpiHandle handle = pair.first;
        const std::vector<CallbackInfo>& infos = pair.second;
        for (auto& info : infos) {
            register_edge_callback(handle, info.task_id, info.edge_type);
        }
    }
    env.pending_edge_cb_map.clear();
#endif

    auto callback_handle = vpi_register_cb(cb_data);
    vpi_free_object(callback_handle);

#ifdef VL_DEF_OPT_VEC_SIMPLE_ACCESS
    // VL_STATIC_DEBUG("before clean => %d\n", env.vec_value_cache.size());
    env.vec_value_cache.clear();
#endif

    // VL_STATIC_DEBUG("[cbNextSimTime] leave next_sim_time_callback()\n");
    return 0;
}

VERILUA_PRIVATE static PLI_INT32 readwrite_synch_callback(p_cb_data cb_data) {
    VL_STATIC_DEBUG("[cbReadWriteSynch] enter readwrite_synch_callback()\n");

    VL_FATAL(false, "TODO:");

    VL_STATIC_DEBUG("[cbReadWriteSynch] leave readwrite_synch_callback()\n");
    return 0;
}

VERILUA_PRIVATE static PLI_INT32 start_callback(p_cb_data cb_data) {
    VL_STATIC_DEBUG("[cbStartOfSimulation] enter start_callback()\n");

    VeriluaEnv::get_instance().initialize();
    
    VL_STATIC_DEBUG("[cbStartOfSimulation] leave start_callback()\n");
    return 0;
}

VERILUA_PRIVATE static PLI_INT32 final_callback(p_cb_data cb_data) {
    VL_STATIC_DEBUG("[cbEndOfSimulation] enter final_callback()\n");

    VeriluaEnv::get_instance().finalize();

    VL_STATIC_DEBUG("[cbEndOfSimulation] leave final_callback()\n");
    return 0;
}

VERILUA_PRIVATE void register_start_calllback(void) {
    auto &env = VeriluaEnv::get_instance();
    if(env.has_start_cb) return;


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

    VL_STATIC_DEBUG("register_start_calllback()\n");
    env.has_start_cb = true;
}

VERILUA_PRIVATE void register_final_calllback(void) {
    auto &env = VeriluaEnv::get_instance();
    if(env.has_final_cb) return;

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

    VL_STATIC_DEBUG("register_final_calllback()\n");
    env.has_final_cb = true;
}

VERILUA_PRIVATE void register_readwrite_synch_calllback(void) {
    static bool registered = false;
    if (registered) return;

    vpiHandle callback_handle;
    s_cb_data cb_data_s;
    s_vpi_time time_s;

    time_s.type = vpiSimTime;
    time_s.high = 0;
    time_s.low = 0;

    cb_data_s.reason = cbReadWriteSynch;
    cb_data_s.cb_rtn = readwrite_synch_callback;

    cb_data_s.obj = nullptr;
    cb_data_s.time = &time_s;
    cb_data_s.value = nullptr;
    cb_data_s.user_data = nullptr;

    callback_handle = vpi_register_cb(&cb_data_s);
    vpi_free_object(callback_handle); // Free the callback handle

    VL_STATIC_DEBUG("register_readwrite_synch_calllback()\n");
    registered = true;
}

VERILUA_PRIVATE void register_next_sim_time_calllback(void) {
    static bool registered = false;
    if (registered) return;

    vpiHandle callback_handle;
    s_cb_data cb_data_s;
    s_vpi_time time_s;

    time_s.type = vpiSimTime;
    time_s.high = 0;
    time_s.low = 0;

    cb_data_s.reason = cbNextSimTime;
    cb_data_s.cb_rtn = next_sim_time_callback;

    cb_data_s.obj = nullptr;
    cb_data_s.time = &time_s;
    cb_data_s.value = nullptr;
    cb_data_s.user_data = nullptr;

    callback_handle = vpi_register_cb(&cb_data_s);
    vpi_free_object(callback_handle); // Free the callback handle

    VL_STATIC_DEBUG("register_next_sim_time_calllback()\n");
    registered = true;
}
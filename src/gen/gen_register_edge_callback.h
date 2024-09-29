
// -------------------------------------------------------------------
// Auto generated by `gen_register_edge_callback.py`
// -------------------------------------------------------------------

struct EdgeCbData2 {
    TaskID      task_id[2];
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};

VERILUA_PRIVATE inline void execute_sim_event2(TaskID id1, TaskID id2) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event2(id1, id2);

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
}

inline static void register_edge_callback2(vpiHandle &handle, TaskID id1, TaskID id2,  EdgeType edge_type) {
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto &env = VeriluaEnv::get_instance();

        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;
        EdgeCbData2 *user_data = reinterpret_cast<EdgeCbData2 *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event2(user_data->task_id[0], user_data->task_id[1]);
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData2 *>(cb_data->user_data);
        }

        return 0;
    };

    EdgeCbData2 *user_data = new EdgeCbData2;
    user_data->task_id[0] = id1;
    user_data->task_id[1] = id2;
    user_data->expected_value = edge_type_to_value(edge_type);
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}


struct EdgeCbData3 {
    TaskID      task_id[3];
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};

VERILUA_PRIVATE inline void execute_sim_event3(TaskID id1, TaskID id2, TaskID id3) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event3(id1, id2, id3);

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
}

inline static void register_edge_callback3(vpiHandle &handle, TaskID id1, TaskID id2, TaskID id3,  EdgeType edge_type) {
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto &env = VeriluaEnv::get_instance();

        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;
        EdgeCbData3 *user_data = reinterpret_cast<EdgeCbData3 *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event3(user_data->task_id[0], user_data->task_id[1], user_data->task_id[2]);
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData3 *>(cb_data->user_data);
        }

        return 0;
    };

    EdgeCbData3 *user_data = new EdgeCbData3;
    user_data->task_id[0] = id1;
    user_data->task_id[1] = id2;
    user_data->task_id[2] = id3;
    user_data->expected_value = edge_type_to_value(edge_type);
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}


struct EdgeCbData4 {
    TaskID      task_id[4];
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};

VERILUA_PRIVATE inline void execute_sim_event4(TaskID id1, TaskID id2, TaskID id3, TaskID id4) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event4(id1, id2, id3, id4);

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
}

inline static void register_edge_callback4(vpiHandle &handle, TaskID id1, TaskID id2, TaskID id3, TaskID id4,  EdgeType edge_type) {
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto &env = VeriluaEnv::get_instance();

        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;
        EdgeCbData4 *user_data = reinterpret_cast<EdgeCbData4 *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event4(user_data->task_id[0], user_data->task_id[1], user_data->task_id[2], user_data->task_id[3]);
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData4 *>(cb_data->user_data);
        }

        return 0;
    };

    EdgeCbData4 *user_data = new EdgeCbData4;
    user_data->task_id[0] = id1;
    user_data->task_id[1] = id2;
    user_data->task_id[2] = id3;
    user_data->task_id[3] = id4;
    user_data->expected_value = edge_type_to_value(edge_type);
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}


struct EdgeCbData5 {
    TaskID      task_id[5];
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};

VERILUA_PRIVATE inline void execute_sim_event5(TaskID id1, TaskID id2, TaskID id3, TaskID id4, TaskID id5) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event5(id1, id2, id3, id4, id5);

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
}

inline static void register_edge_callback5(vpiHandle &handle, TaskID id1, TaskID id2, TaskID id3, TaskID id4, TaskID id5,  EdgeType edge_type) {
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto &env = VeriluaEnv::get_instance();

        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;
        EdgeCbData5 *user_data = reinterpret_cast<EdgeCbData5 *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event5(user_data->task_id[0], user_data->task_id[1], user_data->task_id[2], user_data->task_id[3], user_data->task_id[4]);
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData5 *>(cb_data->user_data);
        }

        return 0;
    };

    EdgeCbData5 *user_data = new EdgeCbData5;
    user_data->task_id[0] = id1;
    user_data->task_id[1] = id2;
    user_data->task_id[2] = id3;
    user_data->task_id[3] = id4;
    user_data->task_id[4] = id5;
    user_data->expected_value = edge_type_to_value(edge_type);
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}


struct EdgeCbData6 {
    TaskID      task_id[6];
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};

VERILUA_PRIVATE inline void execute_sim_event6(TaskID id1, TaskID id2, TaskID id3, TaskID id4, TaskID id5, TaskID id6) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event6(id1, id2, id3, id4, id5, id6);

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
}

inline static void register_edge_callback6(vpiHandle &handle, TaskID id1, TaskID id2, TaskID id3, TaskID id4, TaskID id5, TaskID id6,  EdgeType edge_type) {
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto &env = VeriluaEnv::get_instance();

        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;
        EdgeCbData6 *user_data = reinterpret_cast<EdgeCbData6 *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event6(user_data->task_id[0], user_data->task_id[1], user_data->task_id[2], user_data->task_id[3], user_data->task_id[4], user_data->task_id[5]);
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData6 *>(cb_data->user_data);
        }

        return 0;
    };

    EdgeCbData6 *user_data = new EdgeCbData6;
    user_data->task_id[0] = id1;
    user_data->task_id[1] = id2;
    user_data->task_id[2] = id3;
    user_data->task_id[3] = id4;
    user_data->task_id[4] = id5;
    user_data->task_id[5] = id6;
    user_data->expected_value = edge_type_to_value(edge_type);
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}


struct EdgeCbData7 {
    TaskID      task_id[7];
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};

VERILUA_PRIVATE inline void execute_sim_event7(TaskID id1, TaskID id2, TaskID id3, TaskID id4, TaskID id5, TaskID id6, TaskID id7) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event7(id1, id2, id3, id4, id5, id6, id7);

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
}

inline static void register_edge_callback7(vpiHandle &handle, TaskID id1, TaskID id2, TaskID id3, TaskID id4, TaskID id5, TaskID id6, TaskID id7,  EdgeType edge_type) {
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto &env = VeriluaEnv::get_instance();

        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;
        EdgeCbData7 *user_data = reinterpret_cast<EdgeCbData7 *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event7(user_data->task_id[0], user_data->task_id[1], user_data->task_id[2], user_data->task_id[3], user_data->task_id[4], user_data->task_id[5], user_data->task_id[6]);
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData7 *>(cb_data->user_data);
        }

        return 0;
    };

    EdgeCbData7 *user_data = new EdgeCbData7;
    user_data->task_id[0] = id1;
    user_data->task_id[1] = id2;
    user_data->task_id[2] = id3;
    user_data->task_id[3] = id4;
    user_data->task_id[4] = id5;
    user_data->task_id[5] = id6;
    user_data->task_id[6] = id7;
    user_data->expected_value = edge_type_to_value(edge_type);
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}


struct EdgeCbData8 {
    TaskID      task_id[8];
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
};

VERILUA_PRIVATE inline void execute_sim_event8(TaskID id1, TaskID id2, TaskID id3, TaskID id4, TaskID id5, TaskID id6, TaskID id7, TaskID id8) {
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event8(id1, id2, id3, id4, id5, id6, id7, id8);

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, {}", err.what());
    }
}

inline static void register_edge_callback8(vpiHandle &handle, TaskID id1, TaskID id2, TaskID id3, TaskID id4, TaskID id5, TaskID id6, TaskID id7, TaskID id8,  EdgeType edge_type) {
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        auto &env = VeriluaEnv::get_instance();

        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;
        EdgeCbData8 *user_data = reinterpret_cast<EdgeCbData8 *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {
            execute_sim_event8(user_data->task_id[0], user_data->task_id[1], user_data->task_id[2], user_data->task_id[3], user_data->task_id[4], user_data->task_id[5], user_data->task_id[6], user_data->task_id[7]);
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData8 *>(cb_data->user_data);
        }

        return 0;
    };

    EdgeCbData8 *user_data = new EdgeCbData8;
    user_data->task_id[0] = id1;
    user_data->task_id[1] = id2;
    user_data->task_id[2] = id3;
    user_data->task_id[3] = id4;
    user_data->task_id[4] = id5;
    user_data->task_id[5] = id6;
    user_data->task_id[6] = id7;
    user_data->task_id[7] = id8;
    user_data->expected_value = edge_type_to_value(edge_type);
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}

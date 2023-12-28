#include "vpi_callback.h"


extern lua_State *L;
extern IdPool edge_cb_idpool;
extern std::unordered_map<int, vpiHandle> edge_cb_hdl_map;

#ifdef ACCUMULATE_LUA_TIME
#include <chrono>
extern double lua_time;
double start_time = 0.0;
double end_time = 0.0;
#endif

TO_LUA void c_register_time_callback(uint64_t time, int id) {
    s_cb_data cb_data;
    s_vpi_time vpi_time;
    vpi_time.type = vpiSimTime;
    vpi_time.high = (time >> 32) << 32;
    vpi_time.low = (time << 32) >> 32;

    cb_data.reason = cbAfterDelay;
    // cb_data.cb_rtn = time_callback;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        execute_sim_event((int *)cb_data->user_data);
        free(cb_data->user_data);
        return 0;
    };
    cb_data.time = &vpi_time;
    cb_data.value = NULL;
    int *id_p = (int *)malloc(sizeof(int));
    *id_p = id;
    cb_data.user_data = (PLI_BYTE8*) id_p;
    vpi_register_cb(&cb_data);
}


static inline void register_edge_callback_basic(vpiHandle handle, int edge_type, int id) {
    s_cb_data cb_data;
    s_vpi_time vpi_time;
    s_vpi_value vpi_value;

    vpi_time.type = vpiSuppressTime;
    vpi_value.format = vpiIntVal;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        vpi_get_value(cb_data->obj, cb_data->value);
        int new_value = cb_data->value->value.integer;

        edge_cb_data_t *user_data = (edge_cb_data_t *)cb_data->user_data;
        if(new_value == user_data->expected_value || user_data->expected_value == 2) {
            execute_sim_event(user_data->task_id);

            vpi_remove_cb(edge_cb_hdl_map[user_data->cb_hdl_id]);
            edge_cb_idpool.release_id(user_data->cb_hdl_id);

            free(cb_data->user_data);
        }

        return 0;
    };
    cb_data.time = &vpi_time;
    cb_data.value = &vpi_value;

    cb_data.obj = handle;

    int expected_value = 0;
    if(edge_type == 0) { // Posedge
        expected_value = 1;
    } else if(edge_type == 1) { // Negedge
        expected_value = 0;
    } else if(edge_type == 2) { // Both edge
        expected_value = 2;
    }

    edge_cb_data_t *user_data = (edge_cb_data_t *)malloc(sizeof(edge_cb_data_t));
    user_data->task_id = id;
    user_data->expected_value = expected_value;
    user_data->cb_hdl_id = edge_cb_idpool.alloc_id();
    cb_data.user_data = (PLI_BYTE8 *) user_data;

    edge_cb_hdl_map[user_data->cb_hdl_id] =  vpi_register_cb(&cb_data);
}

TO_LUA void c_register_edge_callback(const char *path, int edge_type, int id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(signal_handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);
    register_edge_callback_basic(signal_handle, edge_type, id);
}

TO_LUA void c_register_edge_callback_hdl(long long handle, int edge_type, int id) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, edge_type, id);
}

TO_LUA void c_register_edge_callback_hdl_always(long long handle, int edge_type, int id) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_cb_data cb_data;
    s_vpi_time vpi_time;
    s_vpi_value vpi_value;

    vpi_time.type = vpiSuppressTime;
    vpi_value.format = vpiIntVal;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        vpi_get_value(cb_data->obj, cb_data->value);
        int new_value = cb_data->value->value.integer;

        edge_cb_data_t *user_data = (edge_cb_data_t *)cb_data->user_data; 
        if(new_value == user_data->expected_value || user_data->expected_value == 2) {
            execute_sim_event(user_data->task_id);
        }

        return 0;
    };
    cb_data.time = &vpi_time;
    cb_data.value = &vpi_value;

    cb_data.obj = actual_handle;

    int expected_value = 0;
    if(edge_type == 0) { // Posedge
        expected_value = 1;
    } else if(edge_type == 1) { // Negedge
        expected_value = 0;
    } else if(edge_type == 2) { // Both edge
        expected_value = 2;
    }

    edge_cb_data_t *user_data = (edge_cb_data_t *)malloc(sizeof(edge_cb_data_t));
    user_data->task_id = id;
    user_data->expected_value = expected_value;
    user_data->cb_hdl_id = edge_cb_idpool.alloc_id();
    cb_data.user_data = (PLI_BYTE8 *) user_data;
    
    edge_cb_hdl_map[user_data->cb_hdl_id] =  vpi_register_cb(&cb_data);
}

TO_LUA void c_register_read_write_synch_callback(int id) {
    s_cb_data cb_data;

    fmt::print("Register cbReadWriteSynch {}\n", id);

    cb_data.reason = cbReadWriteSynch;
    // cb_data.cb_rtn = read_write_synch_callback;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        fmt::print("hello from cbReadWriteSynch id {}\n", *(int *)cb_data->user_data);
        execute_sim_event((int *)cb_data->user_data);

        free(cb_data->user_data);
        return 0;
    };
    cb_data.time = NULL;
    cb_data.value = NULL;

    int *id_p = (int *)malloc(sizeof(int));
    *id_p = id;
    cb_data.user_data = (PLI_BYTE8*) id_p;

    assert(vpi_register_cb(&cb_data) != NULL);
}


static PLI_INT32 start_callback(p_cb_data cb_data) {
    verilua_init();
#ifdef ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
    start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start.time_since_epoch()).count();
#endif
    fmt::print("[{}:{}] Start callback\n", __FILE__, __LINE__);
    return 0;
}

static PLI_INT32 final_callback(p_cb_data cb_data) {

    execute_final_callback();

    lua_close(L);

#ifdef ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end.time_since_epoch()).count();
    double time_taken = end_time - start_time;
    double percent = lua_time * 100 / time_taken;

    fmt::print("[{}:{}] time_taken: {:.2f} sec   lua_time_taken: {:.2f} sec   lua_overhead: {:.2f}%\n", __FILE__, __LINE__, time_taken, lua_time, percent);
#endif
    fmt::print("[{}:{}] Final callback\n", __FILE__, __LINE__);
    return 0;
}

void register_start_calllback(void) {
    vpiHandle callback_handle;
    s_cb_data cb_data_s;

    cb_data_s.reason = cbStartOfSimulation; // The reason for the callback
    cb_data_s.cb_rtn = start_callback; // The function to call back
    cb_data_s.obj = NULL; // Not associated with a particular object
    cb_data_s.time = NULL; // Will be called at the next simulation time
    cb_data_s.value = NULL; // No value to pass
    cb_data_s.user_data = NULL; // No user data to pass

    callback_handle = vpi_register_cb(&cb_data_s);
    vpi_free_object(callback_handle); // Free the callback handle
}

void register_final_calllback(void) {
    vpiHandle callback_handle;
    s_cb_data cb_data_s;

    cb_data_s.reason = cbEndOfSimulation; // The reason for the callback
    cb_data_s.cb_rtn = final_callback; // The function to call back
    cb_data_s.obj = NULL; // Not associated with a particular object
    cb_data_s.time = NULL; // Will be called at the next simulation time
    cb_data_s.value = NULL; // No value to pass
    cb_data_s.user_data = NULL; // No user data to pass

    callback_handle = vpi_register_cb(&cb_data_s);
    vpi_free_object(callback_handle); // Free the callback handle
}

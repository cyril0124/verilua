#include "vpi_callback.h"
#include <fstream>
#include <iostream>

extern lua_State *L;
extern IDPool edge_cb_idpool;
extern std::unordered_map<int, vpiHandle> edge_cb_hdl_map;
extern std::unordered_map<std::string, vpiHandle> handle_cache;
extern std::unordered_map<vpiHandle, VpiPrivilege_t> handle_cache_rev;
extern bool enable_vpi_learn;

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
    VL_FATAL(signal_handle, "No handle found: {}", path);
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

    VL_INFO("Register cbReadWriteSynch {}\n", id);

    cb_data.reason = cbReadWriteSynch;
    // cb_data.cb_rtn = read_write_synch_callback;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        VL_INFO("hello from cbReadWriteSynch id {}\n", *(int *)cb_data->user_data);
        execute_sim_event((int *)cb_data->user_data);

        free(cb_data->user_data);
        return 0;
    };
    cb_data.time = NULL;
    cb_data.value = NULL;

    int *id_p = (int *)malloc(sizeof(int));
    *id_p = id;
    cb_data.user_data = (PLI_BYTE8*) id_p;

    VL_FATAL(vpi_register_cb(&cb_data) != NULL);
}


static PLI_INT32 start_callback(p_cb_data cb_data) {
    static bool already_start = false;

    if (already_start) return 0;

    verilua_init();
#ifdef ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
    start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start.time_since_epoch()).count();
#endif
    
    VL_INFO("Start callback\n");
    already_start = true;
    
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

    VL_INFO("time_taken: {:.2f} sec   lua_time_taken: {:.2f} sec   lua_overhead: {:.2f}%\n", time_taken, lua_time, percent);
#endif
    
    if (enable_vpi_learn) {
        std::ofstream outfile("vpi_learn.log");
        if (!outfile.is_open()) {
            VL_FATAL("Failed to create or open the file.");
        }

        int index = 0;
        VL_INFO("------------- VPI handle_cache -------------\n");
        for(const auto& pair: handle_cache) {
            auto search = handle_cache_rev.find(pair.second);
            VL_FATAL(search != handle_cache_rev.end());

            VL_INFO("[{}]\t{}\t{}\n", index, pair.first, (int)search->second);
            outfile << pair.first << "\t" << "rw:" << (int)search->second << std::endl;
            ++index;
        }
        VL_INFO("\n");

        outfile.close();
    }

    VL_INFO("Final callback\n");
    return 0;
}

void register_start_calllback(void) {
    static bool has_start_callback = false;

    if(has_start_callback) return;

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

    VL_INFO("register_start_calllback\n");
    has_start_callback = true;
}

void register_final_calllback(void) {
    static bool has_final_callback = false;
    if (has_final_callback) return;

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

    VL_INFO("register_final_calllback\n");
    has_final_callback = true;
}

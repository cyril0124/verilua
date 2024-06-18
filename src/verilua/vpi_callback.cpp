#include "vpi_callback.h"
#include "fmt/core.h"
#include "lua_vpi.h"
#include "vpi_user.h"
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <unordered_map>

struct EdgeCbInfo {
    vpiHandle handle;
    int edge_type;
    int id;
    int count;
};

extern lua_State *L;
extern IDPool edge_cb_idpool;
extern std::unordered_map<uint64_t, vpiHandle> edge_cb_hdl_map;
extern std::unordered_map<std::string, vpiHandle> handle_cache;
extern std::unordered_map<vpiHandle, VpiPrivilege_t> handle_cache_rev;
extern bool enable_vpi_learn;

#ifdef ACCUMULATE_LUA_TIME
#include <chrono>
extern double lua_time;
double start_time = 0.0;
double end_time = 0.0;
#endif

TO_LUA void verilua_time_callback(uint64_t time, int id) {
    p_cb_data cb_data = new s_cb_data {
        .reason = cbAfterDelay,
        .cb_rtn = [](p_cb_data cb_data) {
            execute_sim_event((int *)cb_data->user_data);
            delete cb_data->user_data;
            return 0;
        },
        .time = new s_vpi_time
    };
    cb_data->time->type = vpiSimTime;
    cb_data->time->low = time & 0xFFFFFFFF;
    cb_data->time->high = (time >> 32) & 0xFFFFFFFF;

    auto id_p = new int(id);
    cb_data->user_data = reinterpret_cast<PLI_BYTE8 *>(id_p);
    vpi_register_cb(cb_data);
}

TO_LUA void c_register_time_callback(uint64_t time, int id) {
    s_cb_data cb_data;
    s_vpi_time vpi_time;
    vpi_time.type = vpiSimTime;
    vpi_time.low = time & 0xFFFFFFFF;
    vpi_time.high = (time >> 32) & 0xFFFFFFFF;

    cb_data.reason = cbAfterDelay;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        execute_sim_event((int *)cb_data->user_data);
        free(cb_data->user_data);
        return 0;
    };
    cb_data.time = &vpi_time;
    cb_data.value = nullptr;
    auto id_p = new int(id);
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(id_p);
    vpi_register_cb(&cb_data);
}


static inline void register_edge_callback_basic(vpiHandle handle, int edge_type, int id) {
    s_cb_data cb_data;

    p_vpi_time vpi_time = new s_vpi_time{
        .type = vpiSuppressTime,
    };

    p_vpi_value vpi_value = new s_vpi_value{
        .format = vpiIntVal
    };

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        vpi_get_value(cb_data->obj, cb_data->value);
        int new_value = cb_data->value->value.integer;

        edge_cb_data_t *user_data = reinterpret_cast<edge_cb_data_t *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == 2) {
            execute_sim_event(user_data->task_id);

            vpi_remove_cb(edge_cb_hdl_map[user_data->cb_hdl_id]);
            edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete cb_data->user_data;
        }

        return 0;
    };
    cb_data.time = vpi_time;
    cb_data.value = vpi_value;

    cb_data.obj = handle;

    int expected_value = 0;
    if(edge_type == 0) { // Posedge
        expected_value = 1;
    } else if(edge_type == 1) { // Negedge
        expected_value = 0;
    } else if(edge_type == 2) { // Both edge
        expected_value = 2;
    }

    edge_cb_data_t *user_data = new edge_cb_data_t;
    user_data->task_id = id;
    user_data->expected_value = expected_value;
    user_data->cb_hdl_id = edge_cb_idpool.alloc_id();
    cb_data.user_data = (PLI_BYTE8 *) user_data;

    edge_cb_hdl_map[user_data->cb_hdl_id] =  vpi_register_cb(&cb_data);
}

TO_LUA void verilua_posedge_callback(const char *path, int id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: {}", path);
    register_edge_callback_basic(signal_handle, 0, id);
}

TO_LUA void verilua_posedge_callback_hdl(long long handle, int id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, 0, id);
}

TO_LUA void verilua_negedge_callback(const char *path, int id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: {}", path);
    register_edge_callback_basic(signal_handle, 1, id);
}

TO_LUA void verilua_negedge_callback_hdl(long long handle, int id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, 1, id);
}

TO_LUA void verilua_edge_callback(const char *path, int id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: {}", path);
    register_edge_callback_basic(signal_handle, 2, id);
}

TO_LUA void verilua_edge_callback_hdl(long long handle, int id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, 2, id);
}


TO_LUA void c_register_edge_callback(const char *path, int edge_type, int id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, nullptr);
    VL_FATAL(signal_handle, "No handle found: {}", path);
    register_edge_callback_basic(signal_handle, edge_type, id);
}

TO_LUA void c_register_edge_callback_hdl(long long handle, int edge_type, int id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, edge_type, id);
}

TO_LUA void c_register_edge_callback_hdl_always(long long handle, int edge_type, int id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_cb_data cb_data;

    p_vpi_time vpi_time = new s_vpi_time {
        .type = vpiSuppressTime
    };

    p_vpi_value vpi_value = new s_vpi_value {
        .format = vpiIntVal
    };

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        vpi_get_value(cb_data->obj, cb_data->value);
        int new_value = cb_data->value->value.integer;

        edge_cb_data_t *user_data = reinterpret_cast<edge_cb_data_t *>(cb_data->user_data); 
        if(new_value == user_data->expected_value || user_data->expected_value == 2) {
            execute_sim_event(user_data->task_id);
        }

        return 0;
    };
    cb_data.time = vpi_time;
    cb_data.value = vpi_value;

    cb_data.obj = actual_handle;

    int expected_value = 0;
    if(edge_type == 0) { // Posedge
        expected_value = 1;
    } else if(edge_type == 1) { // Negedge
        expected_value = 0;
    } else if(edge_type == 2) { // Both edge
        expected_value = 2;
    }

    edge_cb_data_t *user_data = new edge_cb_data_t;
    user_data->task_id = id;
    user_data->expected_value = expected_value;
    user_data->cb_hdl_id = edge_cb_idpool.alloc_id();
    cb_data.user_data = (PLI_BYTE8 *) user_data;
    
    edge_cb_hdl_map[user_data->cb_hdl_id] =  vpi_register_cb(&cb_data);
}

TO_LUA void verilua_posedge_callback_hdl_always(long long handle, int id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_cb_data cb_data;
    p_vpi_time vpi_time = new s_vpi_time {
        .type = vpiSuppressTime
    };

    p_vpi_value vpi_value = new s_vpi_value {
        .format = vpiIntVal
    };

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        vpi_get_value(cb_data->obj, cb_data->value);
        int new_value = cb_data->value->value.integer;

        edge_cb_data_t *user_data = reinterpret_cast<edge_cb_data_t *>(cb_data->user_data); 
        if(new_value == user_data->expected_value || user_data->expected_value == 2) {
            execute_sim_event(user_data->task_id);
        }

        return 0;
    };
    cb_data.time = vpi_time;
    cb_data.value = vpi_value;

    cb_data.obj = actual_handle;

    int expected_value = 1; // Posedge

    edge_cb_data_t *user_data = new edge_cb_data_t;
    user_data->task_id = id;
    user_data->expected_value = expected_value;
    user_data->cb_hdl_id = edge_cb_idpool.alloc_id();;
    cb_data.user_data = (PLI_BYTE8 *) user_data;

    edge_cb_hdl_map[user_data->cb_hdl_id] =  vpi_register_cb(&cb_data);
}

TO_LUA void verilua_negedge_callback_hdl_always(long long handle, int id) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_cb_data cb_data;
    p_vpi_time vpi_time = new s_vpi_time {
        .type = vpiSuppressTime
    };

    p_vpi_value vpi_value = new s_vpi_value {
        .format = vpiIntVal
    };

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        vpi_get_value(cb_data->obj, cb_data->value);
        int new_value = cb_data->value->value.integer;

        edge_cb_data_t *user_data = reinterpret_cast<edge_cb_data_t *>(cb_data->user_data); 
        if(new_value == user_data->expected_value || user_data->expected_value == 2) {
            execute_sim_event(user_data->task_id);
        }

        return 0;
    };
    cb_data.time = vpi_time;
    cb_data.value = vpi_value;

    cb_data.obj = actual_handle;

    int expected_value = 0; // Negedge

    edge_cb_data_t *user_data = new edge_cb_data_t;
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
    cb_data.cb_rtn = [](p_cb_data cb_data) {
        VL_INFO("hello from cbReadWriteSynch id {}\n", *(int *)cb_data->user_data);
        execute_sim_event((int *)cb_data->user_data);

        free(cb_data->user_data);
        return 0;
    };
    cb_data.time = nullptr;
    cb_data.value = nullptr;

    int *id_p = new int(id);
    cb_data.user_data = (PLI_BYTE8*) id_p;

    VL_FATAL(vpi_register_cb(&cb_data) != nullptr);
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
    verilua_final();

    lua_close(L);

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

    cb_data_s.reason = cbStartOfSimulation;
    cb_data_s.cb_rtn = start_callback;
    cb_data_s.obj = nullptr;
    cb_data_s.time = nullptr;
    cb_data_s.value = nullptr;
    cb_data_s.user_data = nullptr;

    callback_handle = vpi_register_cb(&cb_data_s);
    vpi_free_object(callback_handle);

    VL_INFO("register_start_calllback\n");
    has_start_callback = true;
}

void register_final_calllback(void) {
    static bool has_final_callback = false;
    if (has_final_callback) return;

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

    VL_INFO("register_final_calllback\n");
    has_final_callback = true;
}

#pragma once

#include "lua_vpi.h"

TO_LUA void verilua_time_callback(uint64_t time, TaskID id);

TO_LUA void c_register_edge_callback(const char *path, int edge_type, TaskID id);
TO_LUA void c_register_edge_callback_hdl(long long handle, int edge_type, TaskID id);
TO_LUA void c_register_edge_callback_hdl_always(long long handle, int edge_type, TaskID id);

TO_LUA void c_register_read_write_synch_callback(TaskID id);

void register_start_calllback(void);
void register_final_calllback(void);
void register_readwrite_synch_calllback(void);
void register_next_sim_time_calllback(void);

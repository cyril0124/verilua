#include "lua_vpi.h"

// data type:
//  _____________________
// | Lua    |    C       |
// |________|____________|
// | string |  char *    |
// | number |  long long |
// | float  |  double    |
// |________|____________|

lua_State *L;

TO_LUA void simulator_control(long long cmd) {
    // #define vpiStop                  66   /* execute simulator's $stop */
    // #define vpiFinish                67   /* execute simulator's $finish */
    // #define vpiReset                 68   /* execute simulator's $reset */
    // #define vpiSetInteractiveScope   69   /* set simulator's interactive scope */
    vpi_control(cmd);
}

TO_LUA long long get_signal_value(const char *path) {
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);

    s_vpi_value v;
    v.format = vpiVectorVal;
    vpi_get_value(handle, &v);
    return v.value.vector[0].aval;
}

// return datas with more than 64bit, each table entry is a 32bit value(4 byte)
TO_LUA int get_signal_value_multi(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    const int n = luaL_checkinteger(L, 2);

    // printf("path: %s n: %d\n", path, n);

    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);

    s_vpi_value v;
    v.format = vpiVectorVal;
    vpi_get_value(handle, &v);

    // return a Lua table
    lua_newtable(L);
    for (int i = 0; i < n; i++) {
        lua_pushinteger(L, i + 1); // table index of Lua is started from 1
        lua_pushinteger(L, v.value.vector[i].aval);
        lua_settable(L, -3);
    }
    return 1;
}

TO_LUA void set_signal_value(const char *path, long long value) {
    // printf("set_signal_value: %s => value:%lld\n", path, value);
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);

    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(handle, &v, NULL, vpiNoDelay);
}

TO_LUA void set_signal_value_multi(const char *path, luabridge::LuaRef values_table) {
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);
    
    // Create a vector of s_vpi_vecval, and fill it with the values from the Lua table
    std::vector<s_vpi_vecval> vector(values_table.length());
    for (int i = 1; i <= values_table.length(); i++) {
        vector[i - 1].aval = values_table[i].cast<uint32_t>();
        vector[i - 1].bval = 0;  // Assuming you don't need the bval field
    }

    s_vpi_value v;
    v.format = vpiVectorVal;
    v.value.vector = vector.data();  // Pass the data of the vector to v.value.vector
    vpi_put_value(handle, &v, NULL, vpiNoDelay);
}


static PLI_INT32 time_callback(p_cb_data cb_data) {
    try {
        luabridge::LuaRef sim_event = luabridge::getGlobal(L, "sim_event");
        sim_event((int *)cb_data->user_data);
    } catch (const luabridge::LuaException& e) {
        m_assert(false, "Lua error: %s", e.what());
    }
    

    free(cb_data->user_data);
    return 0;
}

TO_LUA void register_time_callback(long long low, long long high, int id) {
    s_cb_data cb_data;
    s_vpi_time vpi_time;
    vpi_time.type = vpiSimTime;
    vpi_time.high = high;
    vpi_time.low = low;
    // printf("register low:%lld, high:%lld, id:%d\n", low, high, id);

    cb_data.reason = cbAfterDelay;
    cb_data.cb_rtn = time_callback;
    cb_data.time = &vpi_time;
    cb_data.value = NULL;
    int *id_p = (int *)malloc(sizeof(int));
    *id_p = id;
    cb_data.user_data = (PLI_BYTE8*) id_p;
    vpi_register_cb(&cb_data);
}

static IdPool edge_cb_idpool(50);
static std::unordered_map<int, vpiHandle> edge_cb_hdl_map;
static PLI_INT32 edge_callback(p_cb_data cb_data) {
    vpi_get_value(cb_data->obj, cb_data->value);
    int new_value = cb_data->value->value.vector[0].aval;

    edge_cb_data_t *user_data = (edge_cb_data_t *)cb_data->user_data;
    if(new_value == user_data->expected_value || user_data->expected_value == 2) {
        try {
            luabridge::LuaRef sim_event = luabridge::getGlobal(L, "sim_event");
            sim_event(user_data->task_id);
        } catch (const luabridge::LuaException& e) {
            m_assert(false, "Lua error: %s", e.what());
        }

        vpi_remove_cb(edge_cb_hdl_map[user_data->cb_hdl_id]);
        edge_cb_idpool.release_id(user_data->cb_hdl_id);

        free(cb_data->user_data);
    }

    return 0;
}

static PLI_INT32 edge_callback_always(p_cb_data cb_data) {
    vpi_get_value(cb_data->obj, cb_data->value);
    int new_value = cb_data->value->value.vector[0].aval;

    edge_cb_data_t *user_data = (edge_cb_data_t *)cb_data->user_data;
    if(new_value == user_data->expected_value || user_data->expected_value == 2) {
        try {
            luabridge::LuaRef sim_event = luabridge::getGlobal(L, "sim_event");
            sim_event(user_data->task_id);
        } catch (const luabridge::LuaException& e) {
            m_assert(false, "Lua error: %s", e.what());
        }
    }

    return 0;
}

static void register_edge_callback_basic(vpiHandle handle, int edge_type, int id) {
    s_cb_data cb_data;
    s_vpi_time vpi_time;
    s_vpi_value vpi_value;

    vpi_time.type = vpiSuppressTime;
    vpi_value.format = vpiVectorVal;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = edge_callback;
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

TO_LUA void register_edge_callback(const char *path, int edge_type, int id) {
    vpiHandle signal_handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(signal_handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);
    register_edge_callback_basic(signal_handle, edge_type, id);
}

TO_LUA void register_edge_callback_hdl(long long handle, int edge_type, int id) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    register_edge_callback_basic(actual_handle, edge_type, id);
}

TO_LUA void register_edge_callback_hdl_always(long long handle, int edge_type, int id) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_cb_data cb_data;
    s_vpi_time vpi_time;
    s_vpi_value vpi_value;

    vpi_time.type = vpiSuppressTime;
    vpi_value.format = vpiVectorVal;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = edge_callback_always;
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

static PLI_INT32 read_write_synch_callback(p_cb_data cb_data) {
    assert(false);
    try {
        assert(false);
        luabridge::LuaRef sim_event = luabridge::getGlobal(L, "sim_event");
        sim_event((int *)cb_data->user_data);
    } catch (const luabridge::LuaException& e) {
        m_assert(false, "Lua error: %s", e.what());
    }

    free(cb_data->user_data);
    return 0;
}

TO_LUA void register_read_write_synch_callback(int id) {
    s_cb_data cb_data;

    cb_data.reason = cbReadWriteSynch;
    cb_data.cb_rtn = read_write_synch_callback;
    cb_data.time = NULL;
    cb_data.value = NULL;

    int *id_p = (int *)malloc(sizeof(int));
    *id_p = id;
    cb_data.user_data = (PLI_BYTE8*) id_p;

    vpi_register_cb(&cb_data);
}

TO_LUA long long handle_by_name(const char *name) {
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8*)name, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, name);
    long long handle_as_ll = reinterpret_cast<long long>(handle);
    return handle_as_ll;
}

TO_LUA long long get_value(long long handle) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;
    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);
    return v.value.vector[0].aval;
}

TO_LUA luabridge::LuaRef get_value_multi(long long handle, int n, lua_State *L) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);

    s_vpi_value v;
    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);

    // return a Lua table
    luabridge::LuaRef t = luabridge::newTable(L);
    for (int i = 0; i < n; i++) {
        t[ i + 1 ] = v.value.vector[i].aval;
    }
    return t;
}

TO_LUA void set_value(long long handle, long long value) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
}

TO_LUA void set_value_multi(long long handle, luabridge::LuaRef values_table) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);

    // Create a vector of s_vpi_vecval, and fill it with the values from the Lua table
    std::vector<s_vpi_vecval> vector(values_table.length());
    for (int i = 1; i <= values_table.length(); i++) {
        vector[i - 1].aval = values_table[i].cast<uint32_t>();
        vector[i - 1].bval = 0;  // Assuming you don't need the bval field
    }

    s_vpi_value v;
    v.format = vpiVectorVal;
    v.value.vector = vector.data();  // Pass the data of the vector to v.value.vector
    vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
}

TO_LUA long long get_signal_width(long long handle) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    return vpi_get(vpiSize, actual_handle);
}


void lua_init(void) {
    L = luaL_newstate();

    luaL_openlibs(L);

    // Register functions for lua
    luabridge::getGlobalNamespace(L)
        .beginNamespace("vpi")
        .addFunction("read_signal", get_signal_value)
        .addFunction("write_signal", set_signal_value)
        .addFunction("simulator_control", simulator_control)
        .addFunction("register_time_callback", register_time_callback)
        .addFunction("register_edge_callback", register_edge_callback)
        .addFunction("register_edge_callback_hdl", register_edge_callback_hdl)
        .addFunction("register_edge_callback_hdl_always", register_edge_callback_hdl_always)
        .addFunction("register_read_write_synch_callback", register_read_write_synch_callback)
        .addFunction("handle_by_name", handle_by_name)
        .addFunction("get_value", get_value)
        .addFunction("set_value", set_value)
        .addFunction("read_signal_multi", get_signal_value_multi)
        .addFunction("write_signal_multi", set_signal_value_multi)
        .addFunction("get_value_multi", get_value_multi)
        .addFunction("set_value_multi", set_value_multi)
        .addFunction("get_signal_width", get_signal_width)
        .endNamespace();

    
    // Load lua main script
    const char *LUA_SCRIPT = getenv("LUA_SCRIPT");
    if (luaL_dofile(L, LUA_SCRIPT) != LUA_OK) {
            const char *error_msg = lua_tostring(L, -1);
            std::cerr << "Error calling LuaMain.lua: " << error_msg << std::endl;
            lua_pop(L, 1);
            m_assert(false, " ");
    }


    try {
        luabridge::LuaRef verilua_init = luabridge::getGlobal(L, "verilua_init");
        verilua_init();
    } catch (const luabridge::LuaException& e) {
        m_assert(false, "Lua error: %s", e.what());
    }
}


static PLI_INT32 start_callback(p_cb_data cb_data) {
    lua_init();
    
    // register_value_cb();
    // register_time_callback();
    // register_read_write_synch_callback();
    // register_read_only_synch_callback();
    
    printf("[%s:%d] Start callback\n", __FILE__, __LINE__);

    return 0;
}

void execute_final_callback() {
    { // This is the working filed of LuaRef, when we leave this file, LuaRef will release the allocated memory thus not course segmentation fault when use lua_close(L).
        try {
            luabridge::LuaRef lua_finish_callback = luabridge::getGlobal(L, "finish_callback");
            lua_finish_callback();
        } catch (const luabridge::LuaException& e) {
            printf("[execute_final_callback] Lua error: %s", e.what());
            assert(false);
        }
    }
}

static PLI_INT32 final_callback(p_cb_data cb_data) {

    execute_final_callback();

    lua_close(L);

    printf("[%s:%d] Final callback\n", __FILE__, __LINE__);
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

#ifndef WITHOUT_BOOT_STRAP
void (*vlog_startup_routines[])() = {
    register_start_calllback,
    register_final_calllback, 
    nullptr
};
#endif

// For non-VPI compliant applications that cannot find vlog_startup_routines
void vlog_startup_routines_bootstrap() {
    // call each routine in turn like VPI would
    for (auto it = &vlog_startup_routines[0]; *it != nullptr; it++) {
        auto routine = *it;
        routine();
    }
}

void lua_main_step(void) {
    try {
        luabridge::LuaRef main_step = luabridge::getGlobal(L, "lua_main_step");
        main_step();
    } catch (const luabridge::LuaException& e) {
        m_assert(false, "Lua error: %s", e.what());
    }
}


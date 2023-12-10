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
// luabridge::LuaRef sim_event(L);
// luabridge::LuaRef main_step(L);
sol::protected_function sim_event; 
sol::protected_function main_step; 

static IdPool edge_cb_idpool(50);
static std::unordered_map<int, vpiHandle> edge_cb_hdl_map;


inline void execute_sim_event(int *id) {
    auto ret = sim_event(*id);
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
    }
    
    // try {
    //     sim_event(id);
    // } catch (const luabridge::LuaException& e) {
    //     m_assert(false, "Lua error: %s", e.what());
    // }
}

inline void execute_sim_event(int id) {
    auto ret = sim_event(id);
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
    }
    
    // try {
    //     sim_event(id);
    // } catch (const luabridge::LuaException& e) {
    //     m_assert(false, "Lua error: %s", e.what());
    // }
}

inline void execute_final_callback() {
    { // This is the working filed of LuaRef, when we leave this file, LuaRef will release the allocated memory thus not course segmentation fault when use lua_close(L).
        try {
            luabridge::LuaRef lua_finish_callback = luabridge::getGlobal(L, "finish_callback");
            lua_finish_callback();
        } catch (const luabridge::LuaException& e) {
            fmt::print("[{}:{}] [execute_final_callback] Lua error: {}\n", __FILE__, __LINE__, e.what());
            assert(false);
        }
    }
}

inline void execute_main_step() {
    auto ret = main_step();
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
    }
}

TO_LUA uint64_t bitfield64(uint64_t begin, uint64_t end, uint64_t val) {
    // printf("bitfield64: val is 0x%lx\n", val);
    uint64_t mask = ((1ULL << (end - begin + 1)) - 1) << begin;
    // printf("bitfield64: return 0x%lx\n", (val & mask) >> begin);
    return (val & mask) >> begin;
}

TO_LUA void c_simulator_control(long long cmd) {
    // #define vpiStop                  66   /* execute simulator's $stop */
    // #define vpiFinish                67   /* execute simulator's $finish */
    // #define vpiReset                 68   /* execute simulator's $reset */
    // #define vpiSetInteractiveScope   69   /* set simulator's interactive scope */
    vpi_control(cmd);
}

TO_LUA std::string c_get_top_module() {
    vpiHandle iter, top_module;

    // Get module handle 
    iter = vpi_iterate(vpiModule, NULL);
    m_assert(iter != NULL, "No module exist...\n");

    // Scan the first module (Usually this will be the top module of your DUT)
    top_module = vpi_scan(iter);
    m_assert(top_module != NULL, "Cannot find top module!\n");

    if(setenv("DUT_TOP", vpi_get_str(vpiName, top_module), 1)) {
        m_assert(false, "setenv error for DUT_TOP");
    }
    
    if(const char* env_val = std::getenv("DUT_TOP")) {
        std::cout << "DUT_TOP is " << env_val << '\n';
        return std::string(env_val);
    }
    else {
        m_assert(false, "Error while getenv(DUT_TOP)");
    }
}

// TODO: adapt for signals with bit-width greater than 32-bit
TO_LUA long long c_get_value_by_name(const char *path) {
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);

    s_vpi_value v;

    // v.format = vpiIntVal;
    // vpi_get_value(handle, &v);
    // return v.value.integer;

    v.format = vpiVectorVal;
    vpi_get_value(handle, &v);
    return v.value.vector[0].aval;
}

// return datas with more than 64bit, each table entry is a 32bit value(4 byte)
TO_LUA int c_get_value_multi_by_name(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    const int n = luaL_checkinteger(L, 2);

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

TO_LUA void c_set_value_by_name(const char *path, long long value) {
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);

    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(handle, &v, NULL, vpiNoDelay);
}

// TODO: Force/Release statement only work in VCS. (Verilator cannot use Force/Release for some reason. It would be fix in the future. )
TO_LUA void c_force_value_by_name(const char *path, long long value) {
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);

    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(handle, &v, NULL, vpiForceFlag);
}

TO_LUA void c_release_value_by_name(const char *path) {
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, path);

    s_vpi_value v;
    v.format = vpiSuppressVal;
    vpi_put_value(handle, &v, NULL, vpiReleaseFlag);
}

TO_LUA void c_force_value(long long handle, long long value) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(actual_handle, &v, NULL, vpiForceFlag);
}

TO_LUA void c_release_value(long long handle) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;
    v.format = vpiSuppressVal;
    vpi_put_value(actual_handle, &v, NULL, vpiReleaseFlag);
}

TO_LUA int c_set_value_multi_by_name(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);  // Check and get the first argument
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);

    luaL_checktype(L, 2, LUA_TTABLE);  // Check the second argument is a table

    // int table_length = luaL_len(L, 2);  // Get table length
    int table_length = lua_objlen(L, 2);
    std::vector<s_vpi_vecval> vector(table_length);

    for (int idx = 1; idx <= table_length; idx++) {
        lua_pushinteger(L, idx);  // Push the index onto the stack
        lua_gettable(L, 2);  // Get the table value at the index

        uint32_t value = luaL_checkinteger(L, -1);  // Check and get the value
        vector[idx-1].aval = value;
        vector[idx-1].bval = 0;

        lua_pop(L, 1);  // Pop the value from the stack
    }

    s_vpi_value v;
    v.format = vpiVectorVal;
    v.value.vector = vector.data();
    vpi_put_value(handle, &v, NULL, vpiNoDelay);

    return 0;  // Number of return values
}

// TO_LUA void c_register_time_callback(long long low, long long high, int id) {
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
        // try {
        //     sim_event((int *)cb_data->user_data);
        // } catch (const luabridge::LuaException& e) {
        //     m_assert(false, "Lua error: %s", e.what());
        // }
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

TO_LUA long long c_handle_by_name(const char *name) {
    vpiHandle handle = vpi_handle_by_name((PLI_BYTE8*)name, NULL);
    m_assert(handle, "%s:%d No handle found: %s\n", __FILE__, __LINE__, name);
    long long handle_as_ll = reinterpret_cast<long long>(handle);
    return handle_as_ll;
}

TO_LUA uint32_t c_get_value(long long handle) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    // v.format = vpiIntVal;
    // vpi_get_value(actual_handle, &v);
    // return v.value.integer;

    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);
    return v.value.vector[0].aval;
}

TO_LUA uint64_t c_get_value64(long long handle) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);

    uint32_t lo = v.value.vector[0].aval;
    uint32_t hi = v.value.vector[1].aval;
    uint64_t value = ((uint64_t)hi << 32) | lo; 
    return value;
}

TO_LUA int c_get_value_multi(lua_State *L) {
    long long handle = luaL_checkinteger(L, 1);  // Check and get the first argument
    int n = luaL_checkinteger(L, 2);  // Check and get the second argument
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    s_vpi_value v;
    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);

    lua_newtable(L);  // Create a new table and push it onto the stack
    for (int i = 0; i < n; i++) {
        lua_pushinteger(L, i + 1);  // Push the index onto the stack (Lua indices start at 1)
        lua_pushinteger(L, v.value.vector[i].aval);  // Push the value onto the stack
        lua_settable(L, -3);  // Set the table value at the index to the value
    }

    return 1;  // Number of return values (the table is already on the stack)
}

TO_LUA void c_set_value(long long handle, uint32_t value) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    s_vpi_vecval vec_val;
    vec_val.aval = value;
    vec_val.bval = 0;
    v.format = vpiVectorVal;
    v.value.vector = &vec_val;
    vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
}

TO_LUA void c_set_value_force_single(long long handle, uint32_t value, uint32_t size) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    t_vpi_vecval vec_val[size];
    for(int i = 0; i < size; i++) {
        vec_val[i].aval = 0;
        vec_val[i].bval = 0;
    }
    vec_val[0].aval = value;
    
    v.format = vpiVectorVal;
    v.value.vector = vec_val;
    vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
}

TO_LUA void c_set_value64(long long handle, uint64_t value) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    p_vpi_vecval vec_val = (s_vpi_vecval *)malloc(2 * sizeof(s_vpi_vecval));
    vec_val[1].aval = value >> 32;
    vec_val[1].bval = 0;
    vec_val[0].aval = (value << 32) >> 32;
    vec_val[0].bval = 0;
    
    v.format = vpiVectorVal;
    v.value.vector = vec_val;
    vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
    free(vec_val);
}

TO_LUA int c_set_value_multi(lua_State *L) {
    long long handle = luaL_checkinteger(L, 1);  // Check and get the first argument
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    luaL_checktype(L, 2, LUA_TTABLE);  // Check the second argument is a table

    // int table_length = luaL_len(L, 2);  // Get table length
    int table_length = lua_objlen(L, 2);
    std::vector<s_vpi_vecval> vector(table_length);

    for (int idx = 1; idx <= table_length; idx++) {
        lua_pushinteger(L, idx);  // Push the index onto the stack
        lua_gettable(L, 2);  // Get the table value at the index

        uint32_t value = luaL_checkinteger(L, -1);  // Check and get the value
        vector[idx-1].aval = value;
        vector[idx-1].bval = 0;

        lua_pop(L, 1);  // Pop the value from the stack
    }

    s_vpi_value v;
    v.format = vpiVectorVal;
    v.value.vector = vector.data();
    vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);

    return 0;  // Number of return values
}

TO_LUA long long c_get_signal_width(long long handle) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    return vpi_get(vpiSize, actual_handle);
}


void lua_init(void) {
    // Create lua virtual machine
    L = luaL_newstate();

    // Open all the necessary libraried required by lua script. (e.g. os / math / jit/ bit32 / string / coroutine)
    // Import all libraries if we pass no args in.
    luaL_openlibs(L);

    // Assign sol state
    sol::state_view lua(L);

    // Register functions for lua
    luabridge::getGlobalNamespace(L)
        .beginNamespace("vpi")
            .addFunction("get_top_module", c_get_top_module)
            .addFunction("get_value_by_name", c_get_value_by_name)
            .addFunction("set_value_by_name", c_set_value_by_name)
            .addFunction("simulator_control", c_simulator_control)
            .addFunction("register_time_callback", c_register_time_callback)
            .addFunction("register_edge_callback", c_register_edge_callback)
            .addFunction("register_edge_callback_hdl", c_register_edge_callback_hdl)
            .addFunction("register_edge_callback_hdl_always", c_register_edge_callback_hdl_always)
            .addFunction("register_read_write_synch_callback", c_register_read_write_synch_callback)
            .addFunction("handle_by_name", c_handle_by_name)
            .addFunction("get_value", c_get_value)
            .addFunction("set_value", c_set_value)
            .addFunction("get_value_multi_by_name", c_get_value_multi_by_name)
            .addFunction("set_value_multi_by_name", c_set_value_multi_by_name)
            .addFunction("get_value_multi", c_get_value_multi)
            .addFunction("set_value_multi", c_set_value_multi)
            .addFunction("get_signal_width", c_get_signal_width)
            .addFunction("bitfield64", bitfield64)
        .endNamespace();


    // Register breakpoint function for lua
    // DebugPort is 8818
    const char *debug_enable = getenv("VL_DEBUG");
    if (debug_enable != nullptr && (std::strcmp(debug_enable, "1") == 0 || std::strcmp(debug_enable, "enable") == 0) ) {
        luabridge::getGlobalNamespace(L)
            .addFunction("bp", [](lua_State *L){
                    // Execute the Lua code when bp() is called
                    luaL_dostring(L,"require('LuaPanda').start('localhost', 8818); local ret = LuaPanda and LuaPanda.BP and LuaPanda.BP();");
                    return 0;
                }
        );
    } else {
        luabridge::getGlobalNamespace(L)
            .addFunction("bp", [](lua_State *L){
                    // Execute the Lua code when bp() is called
                    luaL_dostring(L,"print(\" Invalid breakpoint! \")");
                    return 0;
                }
        );
    }


    // Load lua main script
    const char *LUA_SCRIPT = getenv("LUA_SCRIPT");
    // if (luaL_dofile(L, LUA_SCRIPT) != LUA_OK) {
    //         const char *error_msg = lua_tostring(L, -1);
    //         std::cerr << "Error calling "<< LUA_SCRIPT << ": " << error_msg << std::endl;
    //         lua_pop(L, 1);
    //         m_assert(false, " ");
    // }
    try {
        lua.script_file(LUA_SCRIPT);
    } catch (const sol::error& err) {
        m_assert(false, "Error calling %s: %s", LUA_SCRIPT, err.what());
    }

    // try {
    //     luabridge::LuaRef verilua_init = luabridge::getGlobal(L, "verilua_init");
    //     verilua_init();
    // } catch (const luabridge::LuaException& e) {
    //     m_assert(false, "Lua error: %s", e.what());
    // }
    sol::protected_function verilua_init = lua["verilua_init"];
    verilua_init.set_error_handler(lua["debug"]["traceback"]);
    
    auto ret = verilua_init();
    if(!ret.valid()) {
        sol::error  err = ret;
        m_assert(false, "Lua error: %s", err.what());
    }

    // sim_event = luabridge::getGlobal(L, "sim_event");
    // main_step = luabridge::getGlobal(L, "lua_main_step");
    sim_event = lua["sim_event"];
    sim_event.set_error_handler(lua["debug"]["traceback"]); 
    main_step = lua["lua_main_step"];
    main_step.set_error_handler(lua["debug"]["traceback"]); 
}


static PLI_INT32 start_callback(p_cb_data cb_data) {
    lua_init();
    
    fmt::print("[{}:{}] Start callback\n", __FILE__, __LINE__);
    return 0;
}

static PLI_INT32 final_callback(p_cb_data cb_data) {

    execute_final_callback();

    lua_close(L);

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
    execute_main_step();
}

// Only for test (LuaJIT FFI)
// "TO_LUA" is necessary since FFI can only access C type function
TO_LUA void hello() {
  printf("hello from C\n");
  fmt::print("hello from fmt:print\n");
}

TO_LUA void c_get_value_parallel(long long *hdls, uint32_t *values, int length) {
    for(int i = 0; i < length; i++) {
        unsigned int* actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        s_vpi_value v;

        v.format = vpiVectorVal;
        vpi_get_value(actual_handle, &v);
        values[i] = v.value.vector[0].aval;
    }
}

TO_LUA void c_get_value64_parallel(long long *hdls, uint64_t *values, int length) {
    for(int i = 0; i < length; i++) {
        unsigned int* actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        s_vpi_value v;

        v.format = vpiVectorVal;
        vpi_get_value(actual_handle, &v);

        uint32_t lo = v.value.vector[0].aval;
        uint32_t hi = v.value.vector[1].aval;
        uint64_t value = ((uint64_t)hi << 32) | lo; 
        values[i] = value;
    }
}


TO_LUA void c_set_value_parallel(long long *hdls, uint32_t *values, int length) {
    for(int i = 0; i < length; i++) {
        unsigned int* actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        s_vpi_value v;
        v.format = vpiIntVal;
        v.value.integer = values[i];
        vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
    }
}

TO_LUA void c_set_value64_parallel(long long *hdls, uint64_t *values, int length) {
    for(int i = 0; i < length; i++) {
        unsigned int* actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        s_vpi_value v;

        p_vpi_vecval vec_val = (s_vpi_vecval *)malloc(2 * sizeof(s_vpi_vecval));
        vec_val[1].aval = values[i] >> 32;
        vec_val[1].bval = 0;
        vec_val[0].aval = (values[i] << 32) >> 32;
        vec_val[0].bval = 0;

        v.format = vpiVectorVal;
        v.value.vector = vec_val;
        vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
        free(vec_val);
    }
}

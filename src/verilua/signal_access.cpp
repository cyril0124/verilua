#include "signal_access.h"

// Cache to store handles
extern std::unordered_map<std::string, vpiHandle> handle_cache;
extern std::unordered_map<vpiHandle, VpiPrivilege_t> handle_cache_rev;
extern bool enable_vpi_learn;

inline vpiHandle _vpi_handle_by_name(PLI_BYTE8 *name, vpiHandle scope) {
    // Check if the name is in the cache
    auto search = handle_cache.find(name);
    if (search != handle_cache.end()) {
        // Name found in cache, return the stored handle
        return search->second;
    }

    auto hdl = vpi_handle_by_name((PLI_BYTE8*)name, NULL);
    if(hdl) {
        handle_cache[name] = hdl;
        if(enable_vpi_learn) handle_cache_rev[hdl] = VpiPrivilege_t::READ;
    }

    return hdl;
}


TO_LUA long long c_handle_by_name(const char* name) {
    // Name not in cache, look it up
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8*)name, NULL);
    VL_FATAL(handle, "No handle found: {}", name);

    // Cast the handle to long long and store it in the cache
    long long handle_as_ll = reinterpret_cast<long long>(handle);

    // Return the handle
    return handle_as_ll;
}

TO_LUA long long c_get_signal_width(long long handle) {
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    return vpi_get(vpiSize, actual_handle);
}

// TODO: adapt for signals with bit-width greater than 32-bit
TO_LUA long long c_get_value_by_name(const char *path) {
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}", path);

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

    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

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
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    if(enable_vpi_learn) handle_cache_rev[handle] = VpiPrivilege_t::WRITE;

    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(handle, &v, NULL, vpiNoDelay);
}

TO_LUA int c_set_value_multi_by_name(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);  // Check and get the first argument
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    if(enable_vpi_learn) handle_cache_rev[handle] = VpiPrivilege_t::WRITE;

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

// TODO: Force/Release statement only work in VCS. (Verilator cannot use Force/Release for some reason. It would be fix in the future. )
TO_LUA void c_force_value_by_name(const char *path, long long value) {
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(handle, &v, NULL, vpiForceFlag);
}

TO_LUA void c_release_value_by_name(const char *path) {
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

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

TO_LUA void c_get_value_multi_1(long long handle, int n, uint32_t *result_arr) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    s_vpi_value v;
    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);
    for(int i = 0; i < n; i++) {
        result_arr[i] = v.value.vector[i].aval;
    }
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
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    if(enable_vpi_learn)  handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

    s_vpi_value v;

    s_vpi_vecval vec_val;
    vec_val.aval = value;
    vec_val.bval = 0;
    v.format = vpiVectorVal;
    v.value.vector = &vec_val;
    vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
}

TO_LUA void c_set_value_force_single(long long handle, uint32_t value, uint32_t size) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    if(enable_vpi_learn) handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

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
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    if(enable_vpi_learn) handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

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
    if(enable_vpi_learn) handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

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
        vpiHandle actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        if(enable_vpi_learn) handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

        s_vpi_value v;
        v.format = vpiIntVal;
        v.value.integer = values[i];
        vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
    }
}

TO_LUA void c_set_value64_parallel(long long *hdls, uint64_t *values, int length) {
    for(int i = 0; i < length; i++) {
        vpiHandle actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        if(enable_vpi_learn) handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;
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

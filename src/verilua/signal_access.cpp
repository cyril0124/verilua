#include "signal_access.h"
#include "lua_vpi.h"

// Cache to store handles
extern std::unordered_map<std::string, vpiHandle> handle_cache;
extern std::unordered_map<vpiHandle, VpiPrivilege_t> handle_cache_rev;
extern bool enable_vpi_learn;

std::mutex vpi_lock_;

#define VPI_REGION_LOG(...)
// #define VPI_REGION_LOG(...) \
//     do { \
//         fmt::print("[{}:{}:{}] [{}VPI_REGION_LOG{}] ", __FILE__, __func__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET); \
//         fmt::print(__VA_ARGS__); \
//     } while(0)

#define VPI_LOCK_GUART() 
// #define VPI_LOCK_GUART() \
//         std::lock_guard guard(vpi_lock_);

#define ENTER_VPI_REGION() \
        VPI_REGION_LOG("TRY_GET\n"); \
        VPI_LOCK_GUART(); \
        VPI_REGION_LOG("GET\n"); 

#define LEAVE_VPI_REGION() \
        VPI_REGION_LOG("RELEASE\n");


inline vpiHandle _vpi_handle_by_name(PLI_BYTE8 *name, vpiHandle scope) {
    // Check if the name is in the cache
    auto search = handle_cache.find(name);
    if (search != handle_cache.end()) [[unlikely]] {
        // Name found in cache, return the stored handle
        return search->second;
    }

    auto hdl = vpi_handle_by_name((PLI_BYTE8*)name, NULL);
    if(hdl) [[likely]] {
        handle_cache[name] = hdl;
        if(enable_vpi_learn) [[unlikely]] handle_cache_rev[hdl] = VpiPrivilege_t::READ;
    }

    return hdl;
}


TO_LUA long long c_handle_by_name(const char* name) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    // Name not in cache, look it up
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8*)name, NULL);
    VL_FATAL(handle, "No handle found: {}", name);

    // Cast the handle to long long and store it in the cache
    long long handle_as_ll = reinterpret_cast<long long>(handle);


#ifndef VCS
    LEAVE_VPI_REGION();
#endif

    // Return the handle
    return handle_as_ll;
}

TO_LUA long long c_get_signal_width(long long handle) {
    ENTER_VPI_REGION();
    
    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);

    LEAVE_VPI_REGION();
    return vpi_get(vpiSize, actual_handle);
}

// TODO: adapt for signals with bit-width greater than 32-bit
TO_LUA long long c_get_value_by_name(const char *path) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}", path);

    s_vpi_value v;

    // v.format = vpiIntVal;
    // vpi_get_value(handle, &v);
    // return v.value.integer;

    v.format = vpiVectorVal;
    vpi_get_value(handle, &v);

#ifndef VCS
    LEAVE_VPI_REGION();
#endif

    return v.value.vector[0].aval;
}

// return datas with more than 64bit, each table entry is a 32bit value(4 byte)
TO_LUA int c_get_value_multi_by_name(lua_State *L) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

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

#ifndef VCS
    LEAVE_VPI_REGION();
#endif
    return 1;
}

TO_LUA void c_set_value_by_name(const char *path, long long value) {
    ENTER_VPI_REGION();
    
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    if(enable_vpi_learn) [[unlikely]] handle_cache_rev[handle] = VpiPrivilege_t::WRITE;

    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;

    vpi_put_value(handle, &v, NULL, vpiNoDelay);

    LEAVE_VPI_REGION();
}

TO_LUA int c_set_value_multi_by_name(lua_State *L) {
    ENTER_VPI_REGION();
    
    const char *path = luaL_checkstring(L, 1);  // Check and get the first argument
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    if(enable_vpi_learn) [[unlikely]] handle_cache_rev[handle] = VpiPrivilege_t::WRITE;

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

    LEAVE_VPI_REGION();
    return 0;  // Number of return values
}

// TODO: Force/Release statement only work in VCS. (Verilator cannot use Force/Release for some reason. It would be fix in the future. )
TO_LUA void c_force_value_by_name(const char *path, long long value) {
#ifdef VCS
    // ! Make sure that the VCS compile cmd has included "-debug_access+all" instead of "-debug_access+class" although the later may contribute to better simulation performance.
    ENTER_VPI_REGION();

    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(handle, &v, NULL, vpiForceFlag);

     VL_INFO("force {}  ==> 0x{:x}\n", path, value);

    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "force value only supported by VCS");
#endif
}

TO_LUA void c_release_value_by_name(const char *path) {
#ifdef VCS
    ENTER_VPI_REGION();

    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    s_vpi_value v;
    v.format = vpiSuppressVal;
    vpi_put_value(handle, &v, NULL, vpiReleaseFlag);

    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "release value only supported by VCS");
#endif
}

TO_LUA void c_force_value(long long handle, long long value) {
#ifdef VCS
    ENTER_VPI_REGION();

    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(actual_handle, &v, NULL, vpiForceFlag);

    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "force value only supported by VCS");
#endif
}

TO_LUA void c_release_value(long long handle) {
#ifdef VCS
    ENTER_VPI_REGION();

    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;
    v.format = vpiSuppressVal;
    vpi_put_value(actual_handle, &v, NULL, vpiReleaseFlag);

    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "release value only supported by VCS");
#endif
}

TO_LUA uint32_t c_get_value(long long handle) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    // v.format = vpiIntVal;
    // vpi_get_value(actual_handle, &v);
    // return v.value.integer;

    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);

#ifndef VCS
    LEAVE_VPI_REGION();
#endif
    return v.value.vector[0].aval;
}

TO_LUA uint64_t c_get_value64(long long handle) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    unsigned int* actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);

    uint32_t lo = v.value.vector[0].aval;
    uint32_t hi = v.value.vector[1].aval;
    uint64_t value = ((uint64_t)hi << 32) | lo; 

#ifndef VCS
    LEAVE_VPI_REGION();
#endif

    return value;
}

TO_LUA void c_get_value_multi_1(long long handle, int n, uint32_t *result_arr) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif 

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    s_vpi_value v;
    v.format = vpiVectorVal;
    vpi_get_value(actual_handle, &v);
    for(int i = 0; i < n; i++) {
        result_arr[i] = v.value.vector[i].aval;
    }

#ifndef VCS
    LEAVE_VPI_REGION();
#endif
}

TO_LUA int c_get_value_multi(lua_State *L) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

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

#ifndef VCS
    LEAVE_VPI_REGION();
#endif
    return 1;  // Number of return values (the table is already on the stack)
}

TO_LUA void c_set_value(long long handle, uint32_t value) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    if(enable_vpi_learn) [[unlikely]]  handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

    s_vpi_value v;

    s_vpi_vecval vec_val;
    vec_val.aval = value;
    vec_val.bval = 0;
    v.format = vpiVectorVal;
    v.value.vector = &vec_val;
    vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);

    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value_force_single(long long handle, uint32_t value, uint32_t size) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    if(enable_vpi_learn) [[unlikely]] handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

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

    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value64(long long handle, uint64_t value) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    if(enable_vpi_learn) [[unlikely]] handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

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

    LEAVE_VPI_REGION();
}

TO_LUA int c_set_value_multi(lua_State *L) {
    ENTER_VPI_REGION();

    long long handle = luaL_checkinteger(L, 1);  // Check and get the first argument
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    if(enable_vpi_learn) [[unlikely]] handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

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

    LEAVE_VPI_REGION();
    return 0;  // Number of return values
}

TO_LUA void c_get_value_parallel(long long *hdls, uint32_t *values, int length) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    for(int i = 0; i < length; i++) {
        unsigned int* actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        s_vpi_value v;

        v.format = vpiVectorVal;
        vpi_get_value(actual_handle, &v);
        values[i] = v.value.vector[0].aval;
    }

    LEAVE_VPI_REGION();
}

TO_LUA void c_get_value64_parallel(long long *hdls, uint64_t *values, int length) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

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

#ifndef VCS
    LEAVE_VPI_REGION();
#endif
}


TO_LUA void c_set_value_parallel(long long *hdls, uint32_t *values, int length) {
    ENTER_VPI_REGION();

    for(int i = 0; i < length; i++) {
        vpiHandle actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        if(enable_vpi_learn) [[unlikely]] handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;

        s_vpi_value v;
        v.format = vpiIntVal;
        v.value.integer = values[i];
        vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
    }

    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value64_parallel(long long *hdls, uint64_t *values, int length) {
    ENTER_VPI_REGION();

    for(int i = 0; i < length; i++) {
        vpiHandle actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        if(enable_vpi_learn) [[unlikely]] handle_cache_rev[actual_handle] = VpiPrivilege_t::WRITE;
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

    LEAVE_VPI_REGION();
}

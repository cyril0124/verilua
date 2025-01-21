#include "vpi_access.h"

#define VPI_REGION_LOG(...)
// #define VPI_REGION_LOG(...) \
//     do { \
//         fmt::print("[{}:{}:{}] [{}VPI_REGION_LOG{}] ", __FILE__, __func__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET); \
//         fmt::print(__VA_ARGS__); \
//     } while(0)

#ifdef VL_DEF_VPI_LOCK_GUARD
std::mutex vpi_lock_;

#define VPI_LOCK_GUART() \
        std::lock_guard guard(vpi_lock_);
#else
#define VPI_LOCK_GUART() 
#endif

#define ENTER_VPI_REGION() \
        VPI_REGION_LOG("TRY_GET\n"); \
        VPI_LOCK_GUART(); \
        VPI_REGION_LOG("GET\n"); 

#define LEAVE_VPI_REGION() \
        VPI_REGION_LOG("RELEASE\n");

VERILUA_PRIVATE inline void _vpi_get_value(vpiHandle expr, p_vpi_value value_p) {
    vpi_get_value(expr, value_p);
}

VERILUA_PRIVATE inline void _vpi_get_value_vec_simple(vpiHandle expr, p_vpi_value value_p) {
#ifdef VL_DEF_OPT_VEC_SIMPLE_ACCESS
    auto &env =  VeriluaEnv::get_instance();

    // VL_FATAL(value_p->format == vpiVectorVal);

    auto it = env.vec_value_cache.find(expr);
    if(it != env.vec_value_cache.end()) {
        s_vpi_vecval vecval[2] = {{it->second.u32[0], 0}, {it->second.u32[1], 0}};
        // VL_INFO("[{}] get value from vec_value_cache => {:x}\n", env.handle_to_name(expr), it->second.u64);
        value_p->value.vector = vecval;
    } else {
        vpi_get_value(expr, value_p);

        env.vec_value_cache[expr] = SimpleVecValue{.u32 = {value_p->value.vector[0].aval, value_p->value.vector[1].aval}};
    }
#else
    vpi_get_value(expr, value_p);
#endif
}

VERILUA_PRIVATE inline vpiHandle _vpi_put_value(vpiHandle object, p_vpi_value value_p, p_vpi_time time_p, PLI_INT32 flags) {
    return vpi_put_value(object, value_p, time_p, flags);
}

VERILUA_PRIVATE inline vpiHandle _vpi_handle_by_name(PLI_BYTE8 *name, vpiHandle scope) {
    auto &env = VeriluaEnv::get_instance();

    // Check if the name is in the cache
    auto search = env.hdl_cache.find(name);
    if (search != env.hdl_cache.end()) [[unlikely]] {
        // Name found in cache, return the stored handle
        return search->second;
    }

    auto hdl = vpi_handle_by_name((PLI_BYTE8*)name, NULL);
    if(hdl) [[likely]] {
        env.hdl_cache[name] = hdl;
#ifdef VL_DEF_VPI_LEARN
        env.hdl_cache_rev[hdl] = VpiPermission::READ;
#endif
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

TO_LUA long long c_handle_by_name_safe(const char* name) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    // Name not in cache, look it up
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8*)name, NULL);
    if(handle == nullptr) {
        return -1;
    }

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
    
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    LEAVE_VPI_REGION();
    return vpi_get(vpiSize, actual_handle);
}

TO_LUA const char *c_get_hdl_type(long long handle) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    LEAVE_VPI_REGION();
    return vpi_get_str(vpiType, actual_handle);
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
    // _vpi_get_value(handle, &v);
    // return v.value.integer;

    v.format = vpiVectorVal;
    // _vpi_get_value(handle, &v);
    _vpi_get_value_vec_simple(handle, &v);

#ifndef VCS
    LEAVE_VPI_REGION();
#endif

#ifndef IVERILOG
    return v.value.vector[0].aval;
#else
    if(VeriluaEnv::get_instance().resolve_x_as_zero && v.value.vector[0].bval != 0)
        return 0;
    else
        return v.value.vector[0].aval;
#endif
}

TO_LUA void c_set_value_by_name(const char *path, uint64_t value) {
    ENTER_VPI_REGION();
    
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

#ifdef VL_DEF_VPI_LEARN
    VeriluaEnv::get_instance().hdl_cache_rev[handle] = VpiPermission::WRITE;
#endif

    s_vpi_value v;
    s_vpi_vecval *vector = new s_vpi_vecval[2];
    vector[1].aval = value >> 32;
    vector[1].bval = 0;
    vector[0].aval = (value << 32) >> 32;
    vector[0].bval = 0;
    
    v.format = vpiVectorVal; // Notice: vpiIntVal cannot be used by Verilator if the signal has more than 32 bits, use vpiVectorVal instead
    v.value.vector = vector;

    _vpi_put_value(handle, &v, NULL, vpiNoDelay);
    delete vector;

    LEAVE_VPI_REGION();
}

// TODO: Force/Release statement only work in VCS. (Verilator cannot use Force/Release for some reason. It would be fix in the future. )
TO_LUA void c_force_value_by_name(const char *path, long long value) {
#if defined(VCS) || defined(IVERILOG)
    // ! Make sure that the VCS compile cmd has included "-debug_access+all" instead of "-debug_access+class" although the later may contribute to better simulation performance.
    ENTER_VPI_REGION();

    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;

    s_vpi_time t;
    t.type = vpiSimTime;
    t.high = 0;
    t.low = 0;

    _vpi_put_value(handle, &v, &t, vpiForceFlag);

    // VL_INFO("force {}  ==> 0x{:x}\n", path, value);

    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "force value only supported by VCS / Iverilog");
#endif
}

TO_LUA void c_release_value_by_name(const char *path) {
#if defined(VCS) || defined(IVERILOG)
    ENTER_VPI_REGION();

    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
    VL_FATAL(handle, "No handle found: {}\n", path);

    s_vpi_value v;
    v.format = vpiVectorVal; // TODO: other kinds of value

    // Tips from cocotb:
    //      Best to pass its current value to the sim when releasing
    _vpi_get_value(handle, &v);
    _vpi_put_value(handle, &v, nullptr, vpiReleaseFlag);

    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "release value only supported by VCS / Iverilog");
#endif
}

TO_LUA void c_force_value(long long handle, long long value) {
#if defined(VCS) || defined(IVERILOG)
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    
    s_vpi_time t;
    t.type = vpiSimTime;
    t.high = 0;
    t.low = 0;

    _vpi_put_value(actual_handle, &v, &t, vpiForceFlag);

    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "force value only supported by VCS / Iverilog");
#endif
}

TO_LUA void c_release_value(long long handle) {
#if defined(VCS) || defined(IVERILOG)
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;
    v.format = vpiSuppressVal;
    _vpi_put_value(actual_handle, &v, NULL, vpiReleaseFlag);

    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "release value only supported by VCS / Iverilog");
#endif
}

TO_LUA uint32_t c_get_value(long long handle) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    // v.format = vpiIntVal;
    // _vpi_get_value(actual_handle, &v);
    // return v.value.integer;

    v.format = vpiVectorVal;
    // _vpi_get_value(actual_handle, &v);
    _vpi_get_value_vec_simple(actual_handle, &v);

#ifndef VCS
    LEAVE_VPI_REGION();
#endif

#ifndef IVERILOG
    return v.value.vector[0].aval;
#else
    if(VeriluaEnv::get_instance().resolve_x_as_zero && v.value.vector[0].bval != 0)
        return 0;
    else
        return v.value.vector[0].aval;
#endif
}

TO_LUA uint64_t c_get_value64(long long handle) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    s_vpi_value v;

    v.format = vpiVectorVal;
    _vpi_get_value_vec_simple(actual_handle, &v);

#ifndef IVERILOG
    uint32_t lo = v.value.vector[0].aval;
    uint32_t hi = v.value.vector[1].aval;
    uint64_t value = ((uint64_t)hi << 32) | lo; 
#else
    uint32_t lo = 0;
    uint32_t hi = 0;
    uint64_t value = 0;
    if(VeriluaEnv::get_instance().resolve_x_as_zero && (v.value.vector[0].bval != 0 || v.value.vector[1].bval != 0)) {
        // remain zero
    } else {
        lo = v.value.vector[0].aval;
        hi = v.value.vector[1].aval;
        value = ((uint64_t)hi << 32) | lo;
    }
#endif

#ifndef VCS
    LEAVE_VPI_REGION();
#endif

    return value;
}

TO_LUA void c_get_value_multi(long long handle, uint32_t *ret, int n) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif 

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    s_vpi_value v;
    v.format = vpiVectorVal;
    _vpi_get_value(actual_handle, &v);

    for(int i = 1; i < (n + 1); i++) {
#ifndef IVERILOG
        ret[i] = v.value.vector[i - 1].aval;
        // VL_INFO("a aval:0x{:x} bval:0x{:x}\n", v.value.vector[i - 1].aval, v.value.vector[i - 1].bval);
#else
        if(VeriluaEnv::get_instance().resolve_x_as_zero && v.value.vector[i - 1].bval != 0)
            ret[i] = 0;
        else {
            ret[i] = v.value.vector[i - 1].aval;
            // VL_INFO("aval:0x{:x} bval:0x{:x}\n", v.value.vector[i - 1].aval, v.value.vector[i - 1].bval);
        }
#endif
    }

    ret[0] = n; // number of returned beat

#ifndef VCS
    LEAVE_VPI_REGION();
#endif
}

TO_LUA void c_set_value(long long handle, uint32_t value) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

#ifdef VL_DEF_VPI_LEARN
    VeriluaEnv::get_instance().hdl_cache_rev[actual_handle] = VpiPermission::WRITE;
#endif

    s_vpi_value v;

    s_vpi_vecval vec_val;
    vec_val.aval = value;
    vec_val.bval = 0;
    v.format = vpiVectorVal;
    v.value.vector = &vec_val;
    _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);

    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value64_force_single(long long handle, uint64_t value, uint32_t size) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

#ifdef VL_DEF_VPI_LEARN
    VeriluaEnv::get_instance().hdl_cache_rev[actual_handle] = VpiPermission::WRITE;
#endif

    static s_vpi_vecval vector[1000]; // TODO: Configurable
    s_vpi_value v;

    for(int i = 0; i < size; i++) {
        vector[i].aval = 0;
        vector[i].bval = 0;
    }

    vector[1].aval = value >> 32;
    vector[0].aval = (value << 32) >> 32;
    
    v.format = vpiVectorVal;
    v.value.vector = vector;
    _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);

    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value64(long long handle, uint64_t value) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

#ifdef VL_DEF_VPI_LEARN
    VeriluaEnv::get_instance().hdl_cache_rev[actual_handle] = VpiPermission::WRITE;
#endif

    static s_vpi_vecval vector[2];
    s_vpi_value v;

    vector[1].aval = value >> 32;
    vector[1].bval = 0;
    vector[0].aval = (value << 32) >> 32;
    vector[0].bval = 0;
    
    v.format = vpiVectorVal;
    v.value.vector = vector;
    _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);

    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value_multi(long long handle, uint32_t *values, int n) {
    ENTER_VPI_REGION();
    
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

#ifdef VL_DEF_VPI_LEARN
    VeriluaEnv::get_instance().hdl_cache_rev[actual_handle] = VpiPermission::WRITE;
#endif

    static s_vpi_vecval vector[1000]; // TODO: Configurable

    for(int i = 0; i < n; i++) {
        vector[i].aval = values[i];
        vector[i].bval = 0;
    }

    s_vpi_value v;
    v.format = vpiVectorVal;
    v.value.vector = vector;
    _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
    
    LEAVE_VPI_REGION();
}


// 
// https://en.wikipedia.org/wiki/X_macro
// 
#define ARG_1  uint32_t v0
#define ARG_2  ARG_1, uint32_t v1
#define ARG_3  ARG_2, uint32_t v2
#define ARG_4  ARG_3, uint32_t v3
#define ARG_5  ARG_4, uint32_t v4
#define ARG_6  ARG_5, uint32_t v5
#define ARG_7  ARG_6, uint32_t v6
#define ARG_8  ARG_7, uint32_t v7

#define ASSIGN_1 vector[0].aval = v0;
#define ASSIGN_2 ASSIGN_1 vector[1].aval = v1;
#define ASSIGN_3 ASSIGN_2 vector[2].aval = v2;
#define ASSIGN_4 ASSIGN_3 vector[3].aval = v3;
#define ASSIGN_5 ASSIGN_4 vector[4].aval = v4;
#define ASSIGN_6 ASSIGN_5 vector[5].aval = v5;
#define ASSIGN_7 ASSIGN_6 vector[6].aval = v6;
#define ASSIGN_8 ASSIGN_7 vector[7].aval = v7;

#define ARG_SELECT(N) ARG_##N
#define ASSIGN_SELECT(N) ASSIGN_##N

#ifdef VL_DEF_VPI_LEARN
#define GENERATE_FUNCTION(NUM) \
    TO_LUA void c_set_value_multi_beat_##NUM(long long handle, ARG_SELECT(NUM)) { \
        ENTER_VPI_REGION(); \
        vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle); \
        VeriluaEnv::get_instance().hdl_cache_rev[actual_handle] = VpiPermission::WRITE; \
        s_vpi_vecval vector[NUM] = {0}; \
        ASSIGN_SELECT(NUM); \
        s_vpi_value v; \
        v.format = vpiVectorVal; \
        v.value.vector = vector; \
        _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay); \
        LEAVE_VPI_REGION(); \
    }
#else
#define GENERATE_FUNCTION(NUM) \
    TO_LUA void c_set_value_multi_beat_##NUM(long long handle, ARG_SELECT(NUM)) { \
        ENTER_VPI_REGION(); \
        vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle); \
        s_vpi_vecval vector[NUM] = {0}; \
        ASSIGN_SELECT(NUM); \
        s_vpi_value v; \
        v.format = vpiVectorVal; \
        v.value.vector = vector; \
        _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay); \
        LEAVE_VPI_REGION(); \
    }
#endif

GENERATE_FUNCTION(2)
GENERATE_FUNCTION(3)
GENERATE_FUNCTION(4)
GENERATE_FUNCTION(5)
GENERATE_FUNCTION(6)
GENERATE_FUNCTION(7)

// 
// Signal access function generator
// Then macro GENERATE_FUNCTION(8) will be expanded as: 
// 
GENERATE_FUNCTION(8)
// TO_LUA void c_set_value_multi_beat_8(
//     long long handle, 
//     uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, 
//     uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7 
// ) {
//     ENTER_VPI_REGION();
    
//     vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
// #ifdef VL_DEF_VPI_LEARN     
//     VeriluaEnv::get_instance().hdl_cache_rev[actual_handle] = VpiPermission::WRITE;
// #endif
//     s_vpi_vecval vector[8] = {0};
//     vector[0].aval = v0;
//     vector[1].aval = v1;
//     vector[2].aval = v2;
//     vector[3].aval = v3;
//     vector[4].aval = v4;
//     vector[5].aval = v5;
//     vector[6].aval = v6;
//     vector[7].aval = v7;

//     s_vpi_value v;
//     v.format = vpiVectorVal;
//     v.value.vector = vector;
//     _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);

//     LEAVE_VPI_REGION();
// }


TO_LUA void c_get_value_parallel(long long *hdls, uint32_t *values, int length) {
#ifndef VCS
    ENTER_VPI_REGION();
#endif

    for(int i = 0; i < length; i++) {
        unsigned int* actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);
        s_vpi_value v;

        v.format = vpiVectorVal;
        _vpi_get_value(actual_handle, &v);
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
        _vpi_get_value_vec_simple(actual_handle, &v);

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

#ifdef VL_DEF_VPI_LEARN
        VeriluaEnv::get_instance().hdl_cache_rev[actual_handle] = VpiPermission::WRITE;
#endif

        s_vpi_value v;
        v.format = vpiIntVal;
        v.value.integer = values[i];
        _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);
    }

    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value64_parallel(long long *hdls, uint64_t *values, int length) {
    ENTER_VPI_REGION();

    for(int i = 0; i < length; i++) {
        vpiHandle actual_handle = reinterpret_cast<vpiHandle>(hdls[i]);

#ifdef VL_DEF_VPI_LEARN
        VeriluaEnv::get_instance().hdl_cache_rev[actual_handle] = VpiPermission::WRITE;
#endif
        s_vpi_value v;

        s_vpi_vecval *vector = (s_vpi_vecval *)malloc(2 * sizeof(s_vpi_vecval));
        vector[1].aval = values[i] >> 32;
        vector[1].bval = 0;
        vector[0].aval = (values[i] << 32) >> 32;
        vector[0].bval = 0;

        v.format = vpiVectorVal;
        v.value.vector = vector;
        _vpi_put_value(actual_handle, &v, NULL, vpiNoDelay);

        free((void *)vector);
    }

    LEAVE_VPI_REGION();
}


TO_LUA void c_set_value_str(long long handle, const char *str) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    s_vpi_value value_s;
    const char *value_str = str;

    if (strncmp(str, "0b", 2) == 0) {
        // Binary
        value_s.format = vpiBinStrVal;
        value_str += 2; // Skip prefix
    } else if (strncmp(str, "0x", 2) == 0) {
        // Hexadecimal
        value_s.format = vpiHexStrVal;
        value_str += 2; // Skip prefix
    } else {
        // Decimal
        value_s.format = vpiDecStrVal;
    }

    value_s.value.str = const_cast<char*>(value_str);
    
    _vpi_put_value(actual_handle, &value_s, nullptr, vpiNoDelay);
    
    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value_hex_str(long long handle, const char *str) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);

    s_vpi_value value_s;
    value_s.format = vpiHexStrVal;
    value_s.value.str = (char *)str;

    _vpi_put_value(actual_handle, &value_s, nullptr, vpiNoDelay);
    
    LEAVE_VPI_REGION();
}

TO_LUA void c_set_value_str_by_name(const char *path, const char *str) {
    ENTER_VPI_REGION();

    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);

    s_vpi_value value_s;
    const char *value_str = str;

    if (strncmp(str, "0b", 2) == 0) {
        // Binary
        value_s.format = vpiBinStrVal;
        value_str += 2; // Skip prefix
    } else if (strncmp(str, "0x", 2) == 0) {
        // Hexadecimal
        value_s.format = vpiHexStrVal;
        value_str += 2; // Skip prefix
    } else {
        // Decimal
        value_s.format = vpiDecStrVal;
    }

    value_s.value.str = const_cast<char*>(value_str);

    _vpi_put_value(handle, &value_s, nullptr, vpiNoDelay);

    LEAVE_VPI_REGION();
}

TO_LUA void c_force_value_str_by_name(const char *path, const char *str) {
#if defined(VCS) || defined(IVERILOG)
    ENTER_VPI_REGION();

    static s_vpi_time t = {.type = vpiSimTime, .high = 0, .low = 0};
    vpiHandle handle = _vpi_handle_by_name((PLI_BYTE8 *)path, NULL);

    s_vpi_value value_s;
    const char *value_str = str;

    if (strncmp(str, "0b", 2) == 0) {
        // Binary
        value_s.format = vpiBinStrVal;
        value_str += 2; // Skip prefix
    } else if (strncmp(str, "0x", 2) == 0) {
        // Hexadecimal
        value_s.format = vpiHexStrVal;
        value_str += 2; // Skip prefix
    } else {
        // Decimal
        value_s.format = vpiDecStrVal;
    }

    value_s.value.str = const_cast<char*>(value_str);
    
    _vpi_put_value(handle, &value_s, &t, vpiForceFlag);
    
    LEAVE_VPI_REGION();
#else
    VL_FATAL(false, "force value only supported by VCS / Iverilog");
#endif
}

TO_LUA const char *c_get_value_str(long long handle, int format) {
    ENTER_VPI_REGION();

    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(handle);
    
    s_vpi_value value_s;

    switch (format) {
        // #define vpiBinStrVal          1
        // #define vpiOctStrVal          2
        // #define vpiDecStrVal          3
        // #define vpiHexStrVal          4
        case 1:
            value_s.format = vpiBinStrVal;
            break;
        case 2:
            value_s.format = vpiOctStrVal;
            break;
        case 3:
            value_s.format = vpiDecStrVal;
            break;
        case 4:
            value_s.format = vpiHexStrVal;
            break;
        default:
            value_s.format = vpiDecStrVal;
            break;
    }
    
    _vpi_get_value(actual_handle, &value_s);
    
    LEAVE_VPI_REGION();

    return value_s.value.str;
}

TO_LUA long long c_handle_by_index(const char *parent_name, long long hdl, int index) {
    vpiHandle actual_handle = reinterpret_cast<vpiHandle>(hdl);

    vpiHandle handle = vpi_handle_by_index(actual_handle, (PLI_INT32)index);
    VL_FATAL(handle, "No handle found: parent_name => {} index => {}", parent_name, index);

    long long handle_as_ll = reinterpret_cast<long long>(handle);

    return handle_as_ll;
}

TO_LUA void iterate_vpi_type(const char *module_name, int type) {
    vpiHandle ref_module_hdl = vpi_handle_by_name((PLI_BYTE8 *)module_name, NULL);
    VL_FATAL(ref_module_hdl, "No handle found: {}", module_name);

    vpiHandle iter = vpi_iterate(type, ref_module_hdl);

    std::string type_name = "";
    switch (type) {
        case vpiNet:
            type_name = "vpiNet";
            break;
        case vpiReg: 
            type_name = "vpiReg";
            break;
        case vpiMemory:
            type_name = "vpiMemory";
            break;
        default: 
            type_name = "Unknown"; 
    }

    VL_INFO("start iterate on module_name => {} type => {}/{}\n", module_name, type, type_name);

    vpiHandle hdl;
    int count = 0;
    while ((hdl = vpi_scan(iter)) != NULL) {
        const char *name = vpi_get_str(vpiName, hdl);
        const char *vpi_type = vpi_get_str(vpiType, hdl);

        fmt::println("[{}] name => {} type => {}", count, name, vpi_type);

        count++;
    }

    if(count == 0) 
        VL_WARN("iterate obj is 0!\n");
}



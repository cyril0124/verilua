#include "lua_vpi.h"

TO_LUA long long c_handle_by_name(const char* name);
TO_LUA long long c_get_signal_width(long long handle);


TO_LUA long long c_get_value_by_name(const char *path);
TO_LUA int c_get_value_multi_by_name(lua_State *L);
TO_LUA void c_set_value_by_name(const char *path, long long value);
TO_LUA int c_set_value_multi_by_name(lua_State *L);


TO_LUA void c_force_value_by_name(const char *path, long long value);
TO_LUA void c_release_value_by_name(const char *path);


TO_LUA void c_force_value(long long handle, long long value);
TO_LUA void c_release_value(long long handle);


TO_LUA uint32_t c_get_value(long long handle);
TO_LUA uint64_t c_get_value64(long long handle);
TO_LUA void c_get_value_multi_1(long long handle, int n, uint32_t *result_arr);
TO_LUA int c_get_value_multi(lua_State *L);


TO_LUA void c_set_value(long long handle, uint32_t value);
TO_LUA void c_set_value_force_single(long long handle, uint32_t value, uint32_t size);
TO_LUA void c_set_value64(long long handle, uint64_t value);
TO_LUA int c_set_value_multi(lua_State *L);


TO_LUA void c_get_value_parallel(long long *hdls, uint32_t *values, int length);
TO_LUA void c_get_value64_parallel(long long *hdls, uint64_t *values, int length);
TO_LUA void c_set_value_parallel(long long *hdls, uint32_t *values, int length);
TO_LUA void c_set_value64_parallel(long long *hdls, uint64_t *values, int length);

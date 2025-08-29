local ffi = require "ffi"

local C = ffi.C

-- `GLOBAL_VERILUA_ENV` is set by `libverilua/src/verilua_env.rs`
local env = _G.GLOBAL_VERILUA_ENV

ffi.cdef [[
    const char *vpiml_get_top_module();
    const char *vpiml_get_simulator_auto();

    void vpiml_register_rd_synch_callback(int id);
    void vpiml_register_rw_synch_callback(int id);
    void vpiml_register_next_sim_time_callback(int id);
    void vpiml_register_time_callback(void *env, uint64_t time, int id);
    void vpiml_register_posedge_callback(long long handle, int id);
    void vpiml_register_negedge_callback(long long handle, int id);
    void vpiml_register_edge_callback(long long handle, int id);
    void vpiml_register_posedge_callback_always(long long handle, int id);
    void vpiml_register_negedge_callback_always(long long handle, int id);

    long long vpiml_handle_by_name(void *env, const char* name);
    long long vpiml_handle_by_name_safe(void *env, const char* name);
    long long vpiml_handle_by_index(void *env, long long hdl, int index);

    const char *vpiml_get_hdl_type(long long handle);
    unsigned int vpiml_get_signal_width(long long handle);

    uint32_t vpiml_get_value(long long handle);
    uint64_t vpiml_get_value64(long long handle);
    void vpiml_get_value_multi(long long handle, uint32_t *ret, int n);

    void vpiml_set_value(long long handle, uint32_t value);
    void vpiml_set_value64(long long handle, uint64_t value);
    void vpiml_set_value64_force_single(long long handle, uint64_t value);
    void vpiml_set_value_multi(long long handle, uint32_t *values);
    void vpiml_set_value_multi_beat_2(long long handle, uint32_t v0, uint32_t v1);
    void vpiml_set_value_multi_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2);
    void vpiml_set_value_multi_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
    void vpiml_set_value_multi_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
    void vpiml_set_value_multi_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
    void vpiml_set_value_multi_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
    void vpiml_set_value_multi_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);

    void vpiml_set_imm_value(long long handle, uint32_t value);
    void vpiml_set_imm_value64(long long handle, uint64_t value);
    void vpiml_set_imm_value64_force_single(long long handle, uint64_t value);
    void vpiml_set_imm_value_multi(long long handle, uint32_t *values);
    void vpiml_set_imm_value_multi_beat_2(long long handle, uint32_t v0, uint32_t v1);
    void vpiml_set_imm_value_multi_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2);
    void vpiml_set_imm_value_multi_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
    void vpiml_set_imm_value_multi_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
    void vpiml_set_imm_value_multi_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
    void vpiml_set_imm_value_multi_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
    void vpiml_set_imm_value_multi_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);

    void vpiml_force_value(long long handle, uint32_t value);
    void vpiml_force_value64(long long handle, uint64_t value);
    void vpiml_force_value64_force_single(long long handle, uint64_t value);
    void vpiml_force_value_str(long long handle, const char *str);
    void vpiml_force_value_multi(long long handle, uint32_t *values);
    void vpiml_force_value_multi_beat_2(long long handle, uint32_t v0, uint32_t v1);
    void vpiml_force_value_multi_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2);
    void vpiml_force_value_multi_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
    void vpiml_force_value_multi_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
    void vpiml_force_value_multi_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
    void vpiml_force_value_multi_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
    void vpiml_force_value_multi_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);

    void vpiml_force_imm_value(long long handle, uint32_t value);
    void vpiml_force_imm_value64(long long handle, uint64_t value);
    void vpiml_force_imm_value64_force_single(long long handle, uint64_t value);
    void vpiml_force_imm_value_str(long long handle, const char *str);
    void vpiml_force_imm_value_multi(long long handle, uint32_t *values);
    void vpiml_force_imm_value_multi_beat_2(long long handle, uint32_t v0, uint32_t v1);
    void vpiml_force_imm_value_multi_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2);
    void vpiml_force_imm_value_multi_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
    void vpiml_force_imm_value_multi_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
    void vpiml_force_imm_value_multi_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
    void vpiml_force_imm_value_multi_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
    void vpiml_force_imm_value_multi_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);

    void vpiml_release_value(long long handle);

    void vpiml_release_imm_value(long long handle);

    const char *vpiml_get_value_str(long long handle, int format);
    const char *vpiml_get_value_hex_str(long long handle);
    const char *vpiml_get_value_bin_str(long long handle);
    const char *vpiml_get_value_dec_str(long long handle);

    void vpiml_set_value_str(long long handle, const char *str);
    void vpiml_set_value_hex_str(long long handle, const char *str);
    void vpiml_set_value_bin_str(long long handle, const char *str);
    void vpiml_set_value_dec_str(long long handle, const char *str);

    void vpiml_set_imm_value_str(long long handle, const char *str);
    void vpiml_set_imm_value_hex_str(long long handle, const char *str);
    void vpiml_set_imm_value_bin_str(long long handle, const char *str);
    void vpiml_set_imm_value_dec_str(long long handle, const char *str);

    void vpiml_set_shuffled(long long handle);
    void vpiml_set_freeze(long long handle);

    void vpiml_set_imm_shuffled(long long handle);
    void vpiml_set_imm_freeze(long long handle);

    void vpiml_shuffled_range_u32(long long handle, uint32_t *u32_vec, uint32_t u32_vec_len);
    void vpiml_shuffled_range_u64(long long handle, uint64_t *u64_vec, uint64_t u64_vec_len);
    void vpiml_shuffled_range_hex_str(long long handle, const char **hex_str_vec, uint32_t hex_str_vec_len);
    void vpiml_reset_shuffled_range(long long handle);
]]

---@class VpimlNormal
local vpiml = {
    ---@type fun(): string
    vpiml_get_top_module = C.vpiml_get_top_module,
    ---@type fun(): string
    vpiml_get_simulator_auto = C.vpiml_get_simulator_auto,

    ---@type fun(id: TaskID)
    vpiml_register_rd_synch_callback = function(id) C.vpiml_register_rd_synch_callback(id) end,
    ---@type fun(id: TaskID)
    vpiml_register_rw_synch_callback = function(id) C.vpiml_register_rw_synch_callback(id) end,
    ---@type fun(id: TaskID)
    vpiml_register_next_sim_time_callback = function(id) C.vpiml_register_next_sim_time_callback(id) end,
    ---@type fun(time: integer, id: TaskID)
    vpiml_register_time_callback = function(time, id) C.vpiml_register_time_callback(env, time, id) end,
    ---@type fun(handle: ComplexHandleRaw, id: TaskID)
    vpiml_register_posedge_callback = C.vpiml_register_posedge_callback,
    ---@type fun(handle: ComplexHandleRaw, id: TaskID)
    vpiml_register_negedge_callback = C.vpiml_register_negedge_callback,
    ---@type fun(handle: ComplexHandleRaw, id: TaskID)
    vpiml_register_edge_callback = C.vpiml_register_edge_callback,
    ---@type fun(handle: ComplexHandleRaw, id: TaskID)
    vpiml_register_posedge_callback_always = C.vpiml_register_posedge_callback_always,
    ---@type fun(handle: ComplexHandleRaw, id: TaskID)
    vpiml_register_negedge_callback_always = C.vpiml_register_negedge_callback_always,

    ---@type fun(name: string): ComplexHandleRaw
    vpiml_handle_by_name = function(name) return C.vpiml_handle_by_name(env, name) end,
    ---@type fun(hdl: ComplexHandleRaw, idx: integer): ComplexHandleRaw
    vpiml_handle_by_index = function(hdl, idx) return C.vpiml_handle_by_index(env, hdl, idx) end,

    --- Safe version of `vpiml_handle_by_name`, can be used to check if a handle exists without throwing an error.
    --- Returns `-1` if the handle does not exist.
    ---@type fun(name: string): integer
    vpiml_handle_by_name_safe = function(name) return C.vpiml_handle_by_name_safe(env, name) end,

    ---@type fun(handle: ComplexHandleRaw): string
    vpiml_get_hdl_type = C.vpiml_get_hdl_type,
    ---@type fun(handle: ComplexHandleRaw): integer
    vpiml_get_signal_width = C.vpiml_get_signal_width,

    ---@type fun(handle: ComplexHandleRaw): integer
    vpiml_get_value = C.vpiml_get_value,
    ---@type fun(handle: ComplexHandleRaw): integer
    vpiml_get_value64 = C.vpiml_get_value64,
    ---@type fun(handle: ComplexHandleRaw, ret: ffi.cdata*[], len: integer)
    vpiml_get_value_multi = C.vpiml_get_value_multi,

    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_set_value = C.vpiml_set_value,
    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_set_value64 = C.vpiml_set_value64,
    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_set_value64_force_single = C.vpiml_set_value64_force_single,
    ---@type fun(handle: ComplexHandleRaw, values: ffi.cdata*[])
    vpiml_set_value_multi = C.vpiml_set_value_multi,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer)
    vpiml_set_value_multi_beat_2 = C.vpiml_set_value_multi_beat_2,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer)
    vpiml_set_value_multi_beat_3 = C.vpiml_set_value_multi_beat_3,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer)
    vpiml_set_value_multi_beat_4 = C.vpiml_set_value_multi_beat_4,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer)
    vpiml_set_value_multi_beat_5 = C.vpiml_set_value_multi_beat_5,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer)
    vpiml_set_value_multi_beat_6 = C.vpiml_set_value_multi_beat_6,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer, v6: integer)
    vpiml_set_value_multi_beat_7 = C.vpiml_set_value_multi_beat_7,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer, v6: integer, v7: integer)
    vpiml_set_value_multi_beat_8 = C.vpiml_set_value_multi_beat_8,

    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_set_imm_value = C.vpiml_set_imm_value,
    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_set_imm_value64 = C.vpiml_set_imm_value64,
    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_set_imm_value64_force_single = C.vpiml_set_imm_value64_force_single,
    ---@type fun(handle: ComplexHandleRaw, values: ffi.cdata*[])
    vpiml_set_imm_value_multi = C.vpiml_set_imm_value_multi,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer)
    vpiml_set_imm_value_multi_beat_2 = C.vpiml_set_imm_value_multi_beat_2,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer)
    vpiml_set_imm_value_multi_beat_3 = C.vpiml_set_imm_value_multi_beat_3,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer)
    vpiml_set_imm_value_multi_beat_4 = C.vpiml_set_imm_value_multi_beat_4,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer)
    vpiml_set_imm_value_multi_beat_5 = C.vpiml_set_imm_value_multi_beat_5,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer)
    vpiml_set_imm_value_multi_beat_6 = C.vpiml_set_imm_value_multi_beat_6,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer, v6: integer)
    vpiml_set_imm_value_multi_beat_7 = C.vpiml_set_imm_value_multi_beat_7,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer, v6: integer, v7: integer)
    vpiml_set_imm_value_multi_beat_8 = C.vpiml_set_imm_value_multi_beat_8,

    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_force_value = C.vpiml_force_value,
    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_force_value64 = C.vpiml_force_value64,
    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_force_value64_force_single = C.vpiml_force_value64_force_single,
    ---@type fun(handle: ComplexHandleRaw, str: string)
    vpiml_force_value_str = C.vpiml_force_value_str,
    ---@type fun(handle: ComplexHandleRaw, values: ffi.cdata*[])
    vpiml_force_value_multi = C.vpiml_force_value_multi,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer)
    vpiml_force_value_multi_beat_2 = C.vpiml_force_value_multi_beat_2,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer)
    vpiml_force_value_multi_beat_3 = C.vpiml_force_value_multi_beat_3,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer)
    vpiml_force_value_multi_beat_4 = C.vpiml_force_value_multi_beat_4,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer)
    vpiml_force_value_multi_beat_5 = C.vpiml_force_value_multi_beat_5,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer)
    vpiml_force_value_multi_beat_6 = C.vpiml_force_value_multi_beat_6,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer, v6: integer)
    vpiml_force_value_multi_beat_7 = C.vpiml_force_value_multi_beat_7,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer, v6: integer, v7: integer)
    vpiml_force_value_multi_beat_8 = C.vpiml_force_value_multi_beat_8,

    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_force_imm_value = C.vpiml_force_imm_value,
    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_force_imm_value64 = C.vpiml_force_imm_value64,
    ---@type fun(handle: ComplexHandleRaw, value: integer)
    vpiml_force_imm_value64_force_single = C.vpiml_force_imm_value64_force_single,
    ---@type fun(handle: ComplexHandleRaw, str: string)
    vpiml_force_imm_value_str = C.vpiml_force_imm_value_str,
    ---@type fun(handle: ComplexHandleRaw, values: ffi.cdata*[])
    vpiml_force_imm_value_multi = C.vpiml_force_imm_value_multi,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer)
    vpiml_force_imm_value_multi_beat_2 = C.vpiml_force_imm_value_multi_beat_2,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer)
    vpiml_force_imm_value_multi_beat_3 = C.vpiml_force_imm_value_multi_beat_3,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer)
    vpiml_force_imm_value_multi_beat_4 = C.vpiml_force_imm_value_multi_beat_4,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer)
    vpiml_force_imm_value_multi_beat_5 = C.vpiml_force_imm_value_multi_beat_5,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer)
    vpiml_force_imm_value_multi_beat_6 = C.vpiml_force_imm_value_multi_beat_6,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer, v6: integer)
    vpiml_force_imm_value_multi_beat_7 = C.vpiml_force_imm_value_multi_beat_7,
    ---@type fun(handle: ComplexHandleRaw, v0: integer, v1: integer, v2: integer, v3: integer, v4: integer, v5: integer, v6: integer, v7: integer)
    vpiml_force_imm_value_multi_beat_8 = C.vpiml_force_imm_value_multi_beat_8,

    ---@type fun(handle: ComplexHandleRaw)
    vpiml_release_value = C.vpiml_release_value,

    ---@type fun(handle: ComplexHandleRaw)
    vpiml_release_imm_value = C.vpiml_release_imm_value,

    ---@type fun(handle: ComplexHandleRaw): string
    vpiml_get_value_str = C.vpiml_get_value_str,
    ---@type fun(handle: ComplexHandleRaw): string
    vpiml_get_value_hex_str = C.vpiml_get_value_hex_str,
    ---@type fun(handle: ComplexHandleRaw): string
    vpiml_get_value_bin_str = C.vpiml_get_value_bin_str,
    ---@type fun(handle: ComplexHandleRaw): string
    vpiml_get_value_dec_str = C.vpiml_get_value_dec_str,

    ---@type fun(handle: ComplexHandleRaw, str: string)
    vpiml_set_value_str = C.vpiml_set_value_str,
    ---@type fun(handle: ComplexHandleRaw, str: string)
    vpiml_set_value_hex_str = C.vpiml_set_value_hex_str,
    ---@type fun(handle: ComplexHandleRaw, str: string)
    vpiml_set_value_bin_str = C.vpiml_set_value_bin_str,
    ---@type fun(handle: ComplexHandleRaw, str: string)
    vpiml_set_value_dec_str = C.vpiml_set_value_dec_str,

    ---@type fun(handle: ComplexHandleRaw)
    vpiml_set_shuffled = C.vpiml_set_shuffled,
    ---@type fun(handle: ComplexHandleRaw)
    vpiml_set_freeze = C.vpiml_set_freeze,

    ---@type fun(handle: ComplexHandleRaw)
    vpiml_set_imm_shuffled = C.vpiml_set_imm_shuffled,
    ---@type fun(handle: ComplexHandleRaw)
    vpiml_set_imm_freeze = C.vpiml_set_imm_freeze,

    ---@type fun(handle: ComplexHandleRaw, u32_vec: ffi.cdata*[], u32_vec_len: integer)
    vpiml_shuffled_range_u32 = C.vpiml_shuffled_range_u32,
    ---@type fun(handle: ComplexHandleRaw, u64_vec: ffi.cdata*[], u64_vec_len: integer)
    vpiml_shuffled_range_u64 = C.vpiml_shuffled_range_u64,
    ---@type fun(handle: ComplexHandleRaw, hex_str_vec: ffi.cdata*[][], hex_str_vec_len: integer)
    vpiml_shuffled_range_hex_str = C.vpiml_shuffled_range_hex_str,
    ---@type fun(handle: ComplexHandleRaw)
    vpiml_reset_shuffled_range = C.vpiml_reset_shuffled_range,
}

return vpiml

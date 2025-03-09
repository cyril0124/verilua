local ffi = require "ffi"

local C = ffi.C
local f = string.format
local ffi_string = ffi.string

local vpiml = {}

if os.getenv("VL_PREBUILD") == "1" then
    setmetatable(vpiml, {
        __index = function (t, k)
            return function(...)
                assert(false, f("[VL_PREBUILD] `%s` is not implemented", k))
            end
        end
    })
else
    ffi.cdef[[
        void vpiml_register_time_callback(uint64_t time, int id);
        void vpiml_register_posedge_callback(const char *path, int id);
        void vpiml_register_posedge_callback_hdl(long long handle, int id);
        void vpiml_register_negedge_callback(const char *path, int id);
        void vpiml_register_negedge_callback_hdl(long long handle, int id);
        void vpiml_register_edge_callback(const char *path, int id);
        void vpiml_register_edge_callback_hdl(long long handle, int id);
        void vpiml_register_posedge_callback_hdl_always(long long handle, int id);
        void vpiml_register_negedge_callback_hdl_always(long long handle, int id);

        long long vpiml_handle_by_name(const char* name);
        long long vpiml_handle_by_name_safe(const char* name);
        long long vpiml_handle_by_index(long long hdl, int index);

        const char *vpiml_get_hdl_type(long long handle);
        unsigned int vpiml_get_signal_width(long long handle);

        uint32_t vpiml_get_value(long long handle);
        uint64_t vpiml_get_value64(long long handle);
        uint64_t vpiml_get_value_by_name(const char *path);
        void vpiml_get_value_multi(long long handle, uint32_t *ret, int n);

        void vpiml_set_value(long long handle, uint32_t value);
        void vpiml_set_value64(long long handle, uint64_t value);
        void vpiml_set_value64_force_single(long long handle, uint64_t value);
        void vpiml_set_value_by_name(const char *path, uint64_t value);
        void vpiml_set_value_str_by_name(const char *path, const char *str);
        void vpiml_set_value_multi(long long handle, uint32_t *values);
        void vpiml_set_value_multi_beat_2(long long handle, uint32_t v0, uint32_t v1);
        void vpiml_set_value_multi_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2); 
        void vpiml_set_value_multi_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
        void vpiml_set_value_multi_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
        void vpiml_set_value_multi_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
        void vpiml_set_value_multi_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
        void vpiml_set_value_multi_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);

        void vpiml_force_value(long long handle, uint32_t value);
        void vpiml_force_value64(long long handle, uint64_t value);
        void vpiml_force_value64_force_single(long long handle, uint64_t value);
        void vpiml_force_value_by_name(const char *path, uint32_t value);
        void vpiml_force_value_str_by_name(const char *path, const char *str);
        void vpiml_force_value_multi(long long handle, uint32_t *values);
        void vpiml_force_value_multi_beat_2(long long handle, uint32_t v0, uint32_t v1);
        void vpiml_force_value_multi_beat_3(long long handle, uint32_t v0, uint32_t v1, uint32_t v2);
        void vpiml_force_value_multi_beat_4(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3);
        void vpiml_force_value_multi_beat_5(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4);
        void vpiml_force_value_multi_beat_6(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5);
        void vpiml_force_value_multi_beat_7(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6);
        void vpiml_force_value_multi_beat_8(long long handle, uint32_t v0, uint32_t v1, uint32_t v2, uint32_t v3, uint32_t v4, uint32_t v5, uint32_t v6, uint32_t v7);
        void vpiml_release_value(long long handle);
        void vpiml_release_value_by_name(const char *path);

        const char *vpiml_get_value_str(long long handle, int format);
        const char *vpiml_get_value_hex_str(long long handle);
        const char *vpiml_get_value_bin_str(long long handle);
        const char *vpiml_get_value_dec_str(long long handle);

        void vpiml_set_value_str(long long handle, const char *str);
        void vpiml_set_value_hex_str(long long handle, const char *str);
        void vpiml_set_value_bin_str(long long handle, const char *str);
        void vpiml_set_value_dec_str(long long handle, const char *str);

        void vpiml_set_shuffled(long long handle);
        void vpiml_set_shuffled_by_name(const char *path);
    ]]

    vpiml.vpiml_register_time_callback = C.vpiml_register_time_callback
    vpiml.vpiml_register_posedge_callback = C.vpiml_register_posedge_callback
    vpiml.vpiml_register_posedge_callback_hdl = C.vpiml_register_posedge_callback_hdl
    vpiml.vpiml_register_negedge_callback = C.vpiml_register_negedge_callback
    vpiml.vpiml_register_negedge_callback_hdl = C.vpiml_register_negedge_callback_hdl
    vpiml.vpiml_register_edge_callback = C.vpiml_register_edge_callback
    vpiml.vpiml_register_edge_callback_hdl = C.vpiml_register_edge_callback_hdl
    vpiml.vpiml_register_posedge_callback_hdl_always = C.vpiml_register_posedge_callback_hdl_always
    vpiml.vpiml_register_negedge_callback_hdl_always = C.vpiml_register_negedge_callback_hdl_always

    vpiml.vpiml_handle_by_name = C.vpiml_handle_by_name
    vpiml.vpiml_handle_by_name_safe = C.vpiml_handle_by_name_safe
    vpiml.vpiml_handle_by_index = C.vpiml_handle_by_index

    vpiml.vpiml_get_hdl_type = C.vpiml_get_hdl_type
    vpiml.vpiml_get_signal_width = C.vpiml_get_signal_width

    vpiml.vpiml_get_value = C.vpiml_get_value
    vpiml.vpiml_get_value64 = C.vpiml_get_value64
    vpiml.vpiml_get_value_by_name = C.vpiml_get_value_by_name
    vpiml.vpiml_get_value_multi = C.vpiml_get_value_multi

    vpiml.vpiml_set_value = C.vpiml_set_value
    vpiml.vpiml_set_value64 = C.vpiml_set_value64
    vpiml.vpiml_set_value64_force_single = C.vpiml_set_value64_force_single
    vpiml.vpiml_set_value_by_name = C.vpiml_set_value_by_name
    vpiml.vpiml_set_value_str_by_name = C.vpiml_set_value_str_by_name
    vpiml.vpiml_set_value_multi = C.vpiml_set_value_multi
    vpiml.vpiml_set_value_multi_beat_2 = C.vpiml_set_value_multi_beat_2
    vpiml.vpiml_set_value_multi_beat_3 = C.vpiml_set_value_multi_beat_3
    vpiml.vpiml_set_value_multi_beat_4 = C.vpiml_set_value_multi_beat_4
    vpiml.vpiml_set_value_multi_beat_5 = C.vpiml_set_value_multi_beat_5
    vpiml.vpiml_set_value_multi_beat_6 = C.vpiml_set_value_multi_beat_6
    vpiml.vpiml_set_value_multi_beat_7 = C.vpiml_set_value_multi_beat_7
    vpiml.vpiml_set_value_multi_beat_8 = C.vpiml_set_value_multi_beat_8

    vpiml.vpiml_force_value = C.vpiml_force_value
    vpiml.vpiml_force_value64 = C.vpiml_force_value64
    vpiml.vpiml_force_value64_force_single = C.vpiml_force_value64_force_single
    vpiml.vpiml_force_value_by_name = C.vpiml_force_value_by_name
    vpiml.vpiml_force_value_str_by_name = C.vpiml_force_value_str_by_name
    vpiml.vpiml_force_value_multi = C.vpiml_force_value_multi
    vpiml.vpiml_force_value_multi_beat_2 = C.vpiml_force_value_multi_beat_2
    vpiml.vpiml_force_value_multi_beat_3 = C.vpiml_force_value_multi_beat_3
    vpiml.vpiml_force_value_multi_beat_4 = C.vpiml_force_value_multi_beat_4
    vpiml.vpiml_force_value_multi_beat_5 = C.vpiml_force_value_multi_beat_5
    vpiml.vpiml_force_value_multi_beat_6 = C.vpiml_force_value_multi_beat_6
    vpiml.vpiml_force_value_multi_beat_7 = C.vpiml_force_value_multi_beat_7
    vpiml.vpiml_force_value_multi_beat_8 = C.vpiml_force_value_multi_beat_8
    vpiml.vpiml_release_value = C.vpiml_release_value
    vpiml.vpiml_release_value_by_name = C.vpiml_release_value_by_name
    vpiml.vpiml_get_value_str = C.vpiml_get_value_str
    vpiml.vpiml_get_value_hex_str = C.vpiml_get_value_hex_str
    vpiml.vpiml_get_value_bin_str = C.vpiml_get_value_bin_str
    vpiml.vpiml_get_value_dec_str = C.vpiml_get_value_dec_str

    vpiml.vpiml_set_value_str = C.vpiml_set_value_str
    vpiml.vpiml_set_value_hex_str = C.vpiml_set_value_hex_str
    vpiml.vpiml_set_value_bin_str = C.vpiml_set_value_bin_str
    vpiml.vpiml_set_value_dec_str = C.vpiml_set_value_dec_str

    vpiml.vpiml_set_shuffled = C.vpiml_set_shuffled
    vpiml.vpiml_set_shuffled_by_name = C.vpiml_set_shuffled_by_name
end

return vpiml
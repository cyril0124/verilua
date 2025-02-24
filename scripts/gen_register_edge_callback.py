

MIN = 2
MAX = 8

policy_has_log = False
# policy_has_log = True

assert MIN <= MAX
assert MIN >= 2
assert MAX >= 3

code_cpp = ""
code_cpp_1 = ""
code_cpp_2 = ""
code_cpp_3 = ""
code_lua = ""

# -------------------------------------------------------------------------------------------------------------------------------------------


for N in range(MIN, MAX + 1):
    tmp = ""
    tmp2 = ""
    tmp3 = ""
    tmp4 = ""
    for i in range(1, N + 1):
        tmp = tmp + f"TaskID id{i}, "
        tmp2 = tmp2 + f"user_data->task_id[{i - 1}], "
        tmp3 = tmp3 + f"    user_data->task_id[{i - 1}] = id{i};\n"
        tmp4 = tmp4 + f"id{i}, "

    tmp2 = tmp2[:-2]
    tmp3 = tmp3[:-1]
    tmp4 = tmp4[:-2]

    code_cpp = code_cpp + f"""
struct EdgeCbData{N} {{
    TaskID      task_id[{N}];
    EdgeValue   expected_value;
    uint64_t    cb_hdl_id;
    s_vpi_value vpi_value;
    s_vpi_time  vpi_time;
}};

VERILUA_PRIVATE inline void execute_sim_event{N}({tmp[:-2]}) {{
    auto &env = VeriluaEnv::get_instance();
#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto start = std::chrono::high_resolution_clock::now();
#endif

    auto ret = env.sim_event{N}({tmp4});

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    auto end = std::chrono::high_resolution_clock::now();
    double time_taken = std::chrono::duration_cast<std::chrono::duration<double>>(end - start).count();
    env.lua_time += time_taken;
#endif

    if(!ret.valid()) [[unlikely]] {{
        env.finalize();
        sol::error  err = ret;
        VL_FATAL(false, "Error calling sim_event, %s", err.what());
    }}
}}

inline static void register_edge_callback{N}(vpiHandle &handle, {tmp} EdgeType edge_type) {{
    auto &env = VeriluaEnv::get_instance();
    s_cb_data cb_data;

    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = [](p_cb_data cb_data) {{
        auto &env = VeriluaEnv::get_instance();

        EdgeValue new_value = (EdgeValue)cb_data->value->value.integer;
        EdgeCbData{N} *user_data = reinterpret_cast<EdgeCbData{N} *>(cb_data->user_data);
        if(new_value == user_data->expected_value || user_data->expected_value == EdgeValue::DONTCARE) {{
            execute_sim_event{N}({tmp2});
            vpi_remove_cb(env.edge_cb_hdl_map[user_data->cb_hdl_id]);
            env.edge_cb_idpool.release_id(user_data->cb_hdl_id);
            delete reinterpret_cast<EdgeCbData{N} *>(cb_data->user_data);
        }}

        return 0;
    }};

    EdgeCbData{N} *user_data = new EdgeCbData{N};
{tmp3}
    user_data->expected_value = edge_type_to_value(edge_type);
    user_data->cb_hdl_id = env.edge_cb_idpool.alloc_id();
    user_data->vpi_value.format = vpiIntVal;
    user_data->vpi_time.type = vpiSuppressTime;

    cb_data.obj = handle;
    cb_data.time = &user_data->vpi_time;
    cb_data.value = &user_data->vpi_value;
    cb_data.user_data = reinterpret_cast<PLI_BYTE8 *>(user_data);

    env.edge_cb_hdl_map[user_data->cb_hdl_id] = vpi_register_cb(&cb_data);
}}

"""

    code_cpp_1 = code_cpp_1 + f"""
    this->sim_event{N} = (*this->lua)["sim_event{N}"];
    this->sim_event{N}.set_error_handler((*this->lua)["debug"]["traceback"]); 
"""

    code_cpp_2 = code_cpp_2 + f"""
    sol::protected_function sim_event{N};"""


# -------------------------------------------------------------------------------------------------------------------------------------------


for N in range(MIN, MAX + 1):
    m_tmp = ""
    m_tmp2 = ""

    for i in range(1, N + 1):
        m_tmp = m_tmp + f"\tscheduler:schedule_task(id{i})\n"
        m_tmp2 = m_tmp2 + f"id{i}, "
    
    m_tmp = m_tmp[:-1]
    m_tmp2 = m_tmp2[:-2]

    code_lua = code_lua + f"""
_G.sim_event{N} = function({m_tmp2})
{m_tmp}    
end

"""

def gen_callback_policy(edge):
    if edge == "posedge":
        edge_type_str = "EdgeType::POSEDGE"
    elif edge == "negedge":
        edge_type_str = "EdgeType::NEGEDGE"
    elif edge == "edge":
        edge_type_str = "EdgeType::EDGE"
    else:
        assert False, "Unknown edge => " + edge

    code_str = ""
    for i in range(MAX, MIN - 1, -1):
        m_tmp = ""
        for j in range(i):
            m_tmp = m_tmp + f"task_id_vec[idx + {j}], "

        common = f"""            idx += {i};
            task_id_size -= {i};"""

        policy_log = ""
        if policy_has_log:
            policy_log = f"""
            VL_INFO("hit register_edge_callback{i}()\\n");    
        """

        if i == MAX:
            code_str = code_str + f"""
        if(task_id_size >= {i}) {{{policy_log}
            register_edge_callback{i}(handle, {m_tmp} {edge_type_str});
{common}
        }} """
        else:
            code_str = code_str + f"""else if(task_id_size >= {i}) {{{policy_log}
            register_edge_callback{i}(handle, {m_tmp} {edge_type_str});
{common}
        }} """

    code_str = code_str + f"""else {{
            register_edge_callback(handle, task_id_vec[idx], {edge_type_str});
            idx += 1;
            task_id_size -= 1;
        }}
"""

    code_str = f"""
for(const auto& pair : env.pending_{edge}_cb_map) {{
    vpiHandle handle = pair.first;
    const std::vector<TaskID>& task_id_vec = pair.second;

    auto idx = 0;
    auto task_id_size = task_id_vec.size();
    while(task_id_size > 0) {{""" + code_str + f"    }}" + f"\n}}"

    return code_str

code_cpp_3 = code_cpp_3 + gen_callback_policy("posedge") + gen_callback_policy("negedge") + gen_callback_policy("edge") 

# -------------------------------------------------------------------------------------------------------------------------------------------


code_cpp = """
// -------------------------------------------------------------------
// Auto generated by `gen_register_edge_callback.py`
// -------------------------------------------------------------------
""" + code_cpp

code_cpp_1 = """
    // -------------------------------------------------------------------
    // Auto generated by `gen_register_edge_callback.py`
    // -------------------------------------------------------------------
""" + code_cpp_1

code_cpp_2 = """
    // -------------------------------------------------------------------
    // Auto generated by `gen_register_edge_callback.py`
    // -------------------------------------------------------------------
""" + code_cpp_2

code_cpp_3 = """
    // -------------------------------------------------------------------
    // Auto generated by `gen_register_edge_callback.py`
    // -------------------------------------------------------------------
""" + code_cpp_3

code_lua = """
---------------------------------------------------------------------
-- Auto generated by `gen_register_edge_callback.py`
---------------------------------------------------------------------
""" + code_lua



# -------------------------------------------------------------------------------------------------------------------------------------------


with open('../src/gen/gen_register_edge_callback.h', 'w') as file:
    file.write(code_cpp)

with open('../src/gen/gen_alloc_sim_event.h', 'w') as file:
    file.write(code_cpp_1)

with open('../src/gen/gen_new_sim_event.h', 'w') as file:
    file.write(code_cpp_2)

with open('../src/gen/gen_callback_policy.h', 'w') as file:
    file.write(code_cpp_3)

with open('../src/gen/gen_sim_event.lua', 'w') as file:
    file.write(code_lua)



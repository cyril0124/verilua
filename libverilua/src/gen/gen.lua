local MAX_CHUNK = 16

local f = string.format

getmetatable('').__index.render = function(template, vars)
    assert(type(template) == "string", "[render] template must be a `string`")
    assert(type(vars) == "table", "[render] vars must be a `table`")
    return (template:gsub("{{(.-)}}", function(key)
        if vars[key] == nil then
            assert(false, string.format("[render] key not found: %s\n\ttemplate_str is: %s\n" , key, template))
        end
        return tostring(vars[key] or "")
    end))
end

local write_file = function (filename, content)
    local file = io.open(filename, "w")
    if file then
        file:write(content)
        file:close()
        print("[write_file] write file: ", filename)
    else
        assert(false, string.format("[write_file] file open failed: %s", filename))
    end
end

-- local gen_callback_policy = function (num)
--     local gen_register_callback = function (num, edge)
--         local params = ""
--         for i = 0, num - 1 do
--             params = params .. ("&task_id_vec[idx + %d]"):format(i) .. ","
--         end
--         params = params:sub(1, -2)
--         return "unsafe {" .. [[do_register_edge_callback_chunk_]] .. num .. f("(handle, %s, &%s, &edge_cb_id)", params, edge) .. "}; "
--     end
    
--     local gen_chuk_schedule_body = function (num, edge)
--         local code = ""
--         for i = 1, num do
--             code = code .. ([[
--                     {{i}} => {
--                         let hdl = {{register_callback}}
--                         idx += {{i}};
--                         task_id_vec_size -= {{i}};

--                         hdl
--                     },
--     ]]):render {i = i, register_callback = gen_register_callback(i, edge)}
--         end
--         return code
--     end

--     local code = ""

--     for _, edge in ipairs({"EdgeType::Posedge", "EdgeType::Negedge", "EdgeType::Edge"}) do
--         code = code .. ([[
--         for (handle, task_id_vec) in &env.pending_{{edge}}_cb_map {
--             let mut idx = 0;
--             let mut task_id_vec_size = task_id_vec.len();
        
--             while task_id_vec_size > 0 {
--                 let edge_cb_id = env.edge_cb_idpool.alloc_id();

--                 let hdl = match std::cmp::min(task_id_vec_size, {{MAX_CHUNK}}) {
--                 {{chuk_schedule_body}}
--                     _ => unreachable!()
--                 };

--                 if let Some(_) = env.edge_cb_hdl_map.insert(edge_cb_id, hdl) {
--                     // TODO: Check ?
--                     // panic!("duplicate edge callback id => {}", edge_cb_id);
--                 };
--             }
--         }

--         ]]):render {MAX_CHUNK = num, chuk_schedule_body = gen_chuk_schedule_body(MAX_CHUNK, edge), edge = (function() 
--             if edge == "EdgeType::Posedge" then
--                 return "posedge"
--             elseif edge == "EdgeType::Negedge" then
--                 return "negedge"
--             else
--                 return "edge"
--             end
--         end)()}
--     end
    
--     return "{" .. code .. "}"
-- end

local gen_callback_policy = function (num)
    local gen_register_callback = function (num, edge)
        local params = ""
        for i = 0, num - 1 do
            params = params .. ("&chunk[%d]"):format(i) .. ","
        end
        params = params:sub(1, -2)
        return "do_register_edge_callback_chunk_" .. num .. f("(complex_handle, %s, &%s, &edge_cb_id)", params, edge)
    end
    
    local gen_chuk_schedule_body = function (num, edge)
        local code = ""
        for i = 1, num do
            code = code .. ([[
                    {{i}} => {{register_callback}},
    ]]):render {i = i, register_callback = gen_register_callback(i, edge)}
        end
        return code
    end

    local code = ""

    for _, edge in ipairs({"EdgeType::Posedge", "EdgeType::Negedge", "EdgeType::Edge"}) do
        code = code .. ([[
        for (complex_handle, task_id_vec) in &env.pending_{{edge}}_cb_map {
            let mut idx = 0;
            let task_id_vec_size = task_id_vec.len();
        
            while idx < task_id_vec_size {
                let chunk_end = usize::min(idx + {{MAX_CHUNK}}, task_id_vec_size);
                let chunk = &task_id_vec[idx..chunk_end];
                let edge_cb_id = env.edge_cb_idpool.alloc_id();

                let cb_hdl = unsafe {
                    match chunk.len() {
                    {{chuk_schedule_body}}
                        _ => unreachable!("{}", chunk.len()),
                    }
                };

                if let Some(_) = env.edge_cb_hdl_map.insert(edge_cb_id, cb_hdl) {
                    // TODO: Check ?
                    // panic!("duplicate edge callback id => {}", edge_cb_id);
                };

                idx = chunk_end;
            }
        }

        ]]):render {MAX_CHUNK = num, chuk_schedule_body = gen_chuk_schedule_body(MAX_CHUNK, edge), edge = (function() 
            if edge == "EdgeType::Posedge" then
                return "posedge"
            elseif edge == "EdgeType::Negedge" then
                return "negedge"
            else
                return "edge"
            end
        end)()}
    end
    
    return "{" .. code .. "}"
end

local gen_register_callback_func = function (num)
    local code = ""

    for i = 1, num do
        local task_id_params = ""
        local task_id_values = ""
        local task_id_vec_values = ""
        for j = 1, i do
            task_id_params = task_id_params .. "task_id_" .. j .. ": &TaskID,"
            task_id_values = task_id_values .. "*task_id_" .. j .. ","
            task_id_vec_values = task_id_vec_values .. "user_data.task_id_vec[" .. (j - 1) .. "],"
        end
        task_id_params = task_id_params:sub(1, -2)
        task_id_values = task_id_values:sub(1, -2)
        task_id_vec_values = task_id_vec_values:sub(1, -2)

        code = code .. ([[
struct EdgeCbDataChunk_{{i}} {
    pub task_id_vec: [TaskID; {{i}}],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_{{i}}(complex_handle_raw: &ComplexHandleRaw, {{task_id_params}}, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_{{i}} {
        task_id_vec: [{{task_id_values}}],
        complex_handle_raw: *complex_handle_raw,
        callback_id: *edge_cb_id,
        edge_type: *edge_type,
        vpi_time: t_vpi_time {
            type_: vpiSuppressTime as _,
            high: 0,
            low: 0,
            real: 0.0,
        },
        vpi_value: t_vpi_value {
            format: vpiIntVal as _,
            value: t_vpi_value__bindgen_ty_1 { integer: 0 },
        },
    }));

    let mut cb_data = s_cb_data {
        reason: cbValueChange as _,
        cb_rtn: Some(edge_callback_chunk_{{i}}),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_{{i}}(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_{{i}} = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_{{i}}) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_{{i}}
            .as_ref()
            .unwrap()
            .call::<()>({{caller_params}})
        {
            panic!("{}", e);
        }

        #[cfg(feature = "acc_time")]
        {
            env.lua_time += s.elapsed();
        }

        #[cfg(feature = "merge_cb")]
        {
            let complex_handle = ComplexHandle::from_raw(&user_data.complex_handle_raw);

            let mut any_task_finished = false;
            // let mut finished_tasks = Vec::with_capacity(user_data.task_id_vec.len());
            let mut finished_tasks: smallvec::SmallVec<[TaskID; {{MAX_CHUNK}}]> = smallvec::SmallVec::new();

            let (cb_count, pending_cb_chunk) = match user_data.edge_type {
                EdgeType::Posedge => (&mut complex_handle.posedge_cb_count, &mut env.pending_posedge_cb_chunk),
                EdgeType::Negedge => (&mut complex_handle.negedge_cb_count, &mut env.pending_negedge_cb_chunk),
                EdgeType::Edge => (&mut complex_handle.edge_cb_count, &mut env.pending_edge_cb_chunk),
            };

            for task_id in &user_data.task_id_vec {
                let count = cb_count.get_mut(task_id).unwrap();
                *count -= 1;
                if *count == 0 {
                    any_task_finished = true;
                    finished_tasks.push(*task_id);
                }
            }

            if !any_task_finished {
                #[cfg(feature = "debug")]
                log::trace!("chunk_task[{{i}}] any_task_finished {:?}", user_data.task_id_vec);
                
                if !pending_cb_chunk.contains_key(&user_data.callback_id) {
                    pending_cb_chunk.insert(user_data.callback_id, (user_data.complex_handle_raw, user_data.task_id_vec.to_vec()));
                }
            } else {
                for task_id in finished_tasks {
                    cb_count.remove(&task_id);
                }
                
                pending_cb_chunk.remove(&user_data.callback_id);

                unsafe { vpi_remove_cb(*env.edge_cb_hdl_map.get(&user_data.callback_id).unwrap()) };
                env.edge_cb_idpool.release_id(user_data.callback_id);
            }
        }

        #[cfg(not(feature = "merge_cb"))]
        {
            unsafe { vpi_remove_cb(*env.edge_cb_hdl_map.get(&user_data.callback_id).unwrap()) };
            env.edge_cb_idpool.release_id(user_data.callback_id);
        }
    }
    0
}

]]):render {
    i = i, 
    MAX_CHUNK = num,
    task_id_params = task_id_params, 
    task_id_values = task_id_values, 
    caller_params = (function() 
        if i == 1 then
            return task_id_vec_values
        else
            return "(" .. task_id_vec_values .. ")"
        end
    end)(),
}
    end

    return code
end

local gen_verilua_env_struct = function (num)
    local code = ""

    local lua_sim_event_chunk = ""
    for i = 1, num do
        lua_sim_event_chunk = lua_sim_event_chunk .. ([[
        #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_{{i}}: Option<LuaFunction>,
        ]]):render {i = i}
    end

    return ([[
#[derive(Debug)]
pub struct VeriluaEnv {
    pub hdl_cache: HashMap<String, ComplexHandleRaw>,
    pub hdl_put_value: Vec<ComplexHandleRaw>,

    #[cfg(feature = "chunk_task")]
    pub pending_posedge_cb_map: HashMap<ComplexHandleRaw, Vec<TaskID>>,
    #[cfg(feature = "chunk_task")]
    pub pending_negedge_cb_map: HashMap<ComplexHandleRaw, Vec<TaskID>>,
    #[cfg(feature = "chunk_task")]
    pub pending_edge_cb_map: HashMap<ComplexHandleRaw, Vec<TaskID>>,

    #[cfg(all(feature = "chunk_task", feature = "merge_cb"))]
    pub pending_posedge_cb_chunk: HashMap<EdgeCallbackID, (ComplexHandleRaw, Vec<TaskID>)>,
    #[cfg(all(feature = "chunk_task", feature = "merge_cb"))]
    pub pending_negedge_cb_chunk: HashMap<EdgeCallbackID, (ComplexHandleRaw, Vec<TaskID>)>,
    #[cfg(all(feature = "chunk_task", feature = "merge_cb"))]
    pub pending_edge_cb_chunk: HashMap<EdgeCallbackID, (ComplexHandleRaw, Vec<TaskID>)>,
    
    #[cfg(not(feature = "chunk_task"))]
    pub pending_edge_cb_map: HashMap<ComplexHandleRaw, Vec<CallbackInfo>>,

    {{lua_sim_event_chunk}}

    pub edge_cb_idpool: IDPool,
    pub edge_cb_hdl_map: HashMap<EdgeCallbackID, vpiHandle>,

    pub resolve_x_as_zero: bool,
    pub start_time: Instant,

    #[cfg(feature = "acc_time")]
    pub lua_time: Duration,

    pub lua: Lua,
    pub lua_sim_event: Option<LuaFunction>,
    pub lua_main_step: Option<LuaFunction>,
    pub lua_posedge_step: Option<LuaFunction>,
    pub lua_negedge_step: Option<LuaFunction>,

    pub initialized: bool,
    pub finalized: bool,
    pub has_start_cb: bool,
    pub has_final_cb: bool,
}
]]):render { lua_sim_event_chunk = lua_sim_event_chunk }
end

local gen_verilua_env_init = function (num)
    local code = ""

    local lua_sim_event_chunk_init = ""
    for i = 1, num do
        lua_sim_event_chunk_init = lua_sim_event_chunk_init .. ([[
        #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_{{i}}: None,
        ]]):render {i = i}
    end

    return ([[
Self {
    hdl_cache: HashMap::new(),
    hdl_put_value: Vec::new(),

    #[cfg(feature = "chunk_task")]
    pending_posedge_cb_map: HashMap::new(),
    #[cfg(feature = "chunk_task")]
    pending_negedge_cb_map: HashMap::new(),
    #[cfg(feature = "chunk_task")]
    pending_edge_cb_map: HashMap::new(),

    #[cfg(all(feature = "chunk_task", feature = "merge_cb"))]
    pending_posedge_cb_chunk: HashMap::new(),
    #[cfg(all(feature = "chunk_task", feature = "merge_cb"))]
    pending_negedge_cb_chunk: HashMap::new(),
    #[cfg(all(feature = "chunk_task", feature = "merge_cb"))]
    pending_edge_cb_chunk: HashMap::new(),

    #[cfg(not(feature = "chunk_task"))]
    pending_edge_cb_map: HashMap::new(),

    edge_cb_idpool: IDPool::new(10000),
    edge_cb_hdl_map: HashMap::new(),

    resolve_x_as_zero: false,
    start_time: Instant::now(),

    #[cfg(feature = "acc_time")]
    lua_time: Duration::default(),

    lua,
    lua_sim_event: None,
    lua_main_step: None,
    lua_posedge_step: None,
    lua_negedge_step: None,

    initialized: false,
    finalized: false,
    has_start_cb: false,
    has_final_cb: false,
    
    {{lua_sim_event_chunk_init}}
}
]]):render { lua_sim_event_chunk_init = lua_sim_event_chunk_init }
end

local gen_sim_event_chunk_init = function (num)
    local code = ""

    for i = 1, num do
        code = code .. ([[
        self.lua_sim_event_chunk_{{i}} = Some(
            self.lua
                .globals()
                .get("sim_event_chunk_{{i}}")
                .expect("Failed to load sim_event_chunk_{{i}}")
        );
        ]]):render {i = i}
    end

    return "#[cfg(feature = \"chunk_task\")]\n\t{" .. code .. "}"
end

local gen_lua_sim_event_chunk = function(num)
    local code = ""

    for i = 1, num do
        local task_id_params = ""
        local schedule_tasks = ""
        for j = 1, i do
            task_id_params = task_id_params .. "task_id_" .. j .. ", "
            schedule_tasks = schedule_tasks .. "\tscheduler:schedule_task(task_id_" .. j .. ")\n"
        end
        task_id_params = task_id_params:sub(1, -3)
        schedule_tasks = schedule_tasks:sub(1, -2)

        code = code .. ([[

_G.sim_event_chunk_{{i}} = function ({{task_id_params}})
{{schedule_tasks}}
end
]]):render {i = i, task_id_params = task_id_params, schedule_tasks = schedule_tasks}
    end

    return code
end

print(gen_callback_policy(MAX_CHUNK))
print(gen_register_callback_func(MAX_CHUNK))
print(gen_verilua_env_struct(MAX_CHUNK))
print(gen_verilua_env_init(MAX_CHUNK))
print(gen_sim_event_chunk_init(MAX_CHUNK))
print(gen_lua_sim_event_chunk(MAX_CHUNK))

write_file("gen_callback_policy.rs", gen_callback_policy(MAX_CHUNK))
write_file("gen_register_callback_func.rs", gen_register_callback_func(MAX_CHUNK))
write_file("gen_verilua_env_struct.rs", gen_verilua_env_struct(MAX_CHUNK))
write_file("gen_verilua_env_init.rs", gen_verilua_env_init(MAX_CHUNK))
write_file("gen_sim_event_chunk_init.rs", gen_sim_event_chunk_init(MAX_CHUNK))
write_file("sim_event_chunk.lua", gen_lua_sim_event_chunk(MAX_CHUNK))
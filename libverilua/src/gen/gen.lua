--[[
================================================================================
  Verilua Code Generator
================================================================================

  This script generates Rust code for the libverilua library to support
  "chunk task" callback optimization. The generator creates code that batches
  multiple task callbacks into chunks for better performance.

  Generated Files:
  ┌─────────────────────────────────┬──────────────────────────────────────────┐
  │ File                            │ Description                              │
  ├─────────────────────────────────┼──────────────────────────────────────────┤
  │ gen_callback_policy.rs          │ Callback dispatch logic for edge types   │
  │ gen_register_callback_func.rs   │ Chunk callback registration functions    │
  │ gen_verilua_env_struct.rs       │ VeriluaEnv struct field definitions      │
  │ gen_verilua_env_init.rs         │ VeriluaEnv initialization code           │
  │ gen_sim_event_chunk_init.rs     │ Lua function reference initialization    │
  │ sim_event_chunk.lua             │ Lua scheduler dispatch functions         │
  └─────────────────────────────────┴──────────────────────────────────────────┘

  Data Flow (Chunk Task Optimization):
  ┌──────────────┐     ┌───────────────────┐     ┌─────────────────────┐
  │ VPI Callback │────>│ Callback Handler  │────>│ Lua sim_event_chunk │
  │ (edge event) │     │ (Rust generated)  │     │ (batch scheduling)  │
  └──────────────┘     └───────────────────┘     └─────────────────────┘
                                │
                                ▼
                       ┌───────────────────┐
                       │  Task Scheduler   │
                       │  (schedule tasks) │
                       └───────────────────┘

  Usage:
      cd libverilua/src/gen
      luajit gen.lua

  Configuration:
      MAX_CHUNK: Maximum number of tasks per callback chunk (default: 16)

================================================================================
--]]

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Notice: `mlua` <Function>::call only accepts up to 16 arguments, so the
-- maximum chunk size is limited to 16 when `fast_lua_call` feature is disabled.
local MAX_CHUNK = 16  -- Maximum tasks per callback chunk

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local f = string.format
local concat = table.concat
local insert = table.insert

--- Template rendering: replaces {{key}} with values from vars table
--- @param template string Template string with {{key}} placeholders
--- @param vars table Key-value pairs for substitution
--- @return string Rendered string
getmetatable('').__index.render = function(template, vars)
    assert(type(template) == "string", "[render] template must be a `string`")
    assert(type(vars) == "table", "[render] vars must be a `table`")
    return (template:gsub("{{(.-)}}", function(key)
        if vars[key] == nil then
            assert(false, f("[render] key not found: %s\n\ttemplate_str is: %s\n", key, template))
        end
        return tostring(vars[key] or "")
    end))
end

--- Writes content to a file
--- @param filename string Path to the output file
--- @param content string Content to write
local function write_file(filename, content)
    local file = io.open(filename, "w")
    if file then
        file:write(content)
        file:close()
        print(f("[gen.lua] Generated: %s", filename))
    else
        assert(false, f("[gen.lua] Failed to write file: %s", filename))
    end
end

--------------------------------------------------------------------------------
-- Edge Type Mapping
--------------------------------------------------------------------------------

--- Maps EdgeType enum to Rust variable name suffix
--- @param edge_type string EdgeType enum value (e.g., "EdgeType::Posedge")
--- @return string Suffix for variable names (e.g., "posedge")
local function edge_type_to_suffix(edge_type)
    local mapping = {
        ["EdgeType::Posedge"] = "posedge",
        ["EdgeType::Negedge"] = "negedge",
        ["EdgeType::Edge"] = "edge"
    }
    return mapping[edge_type] or error("Unknown edge type: " .. edge_type)
end

local EDGE_TYPES = {"EdgeType::Posedge", "EdgeType::Negedge", "EdgeType::Edge"}

--------------------------------------------------------------------------------
-- Code Generators
--------------------------------------------------------------------------------

--[[
  Generates callback dispatch policy code.

  This function creates the Rust code that dispatches edge callbacks to
  the appropriate chunk handler based on the number of pending tasks.

  Structure:
      for each edge type (posedge, negedge, edge):
          for each pending callback:
              match chunk size -> call appropriate chunk handler
--]]
local function gen_callback_policy(max_chunk)
    --- Generates the function call for registering a chunk callback
    --- @param chunk_size number Number of tasks in the chunk
    --- @param edge_type string EdgeType enum value
    --- @return string Rust function call expression
    local function gen_register_callback_call(chunk_size, edge_type)
        local params = {}
        for i = 0, chunk_size - 1 do
            params[#params + 1] = f("&chunk[%d]", i)
        end
        return f("do_register_edge_callback_chunk_%d(complex_handle, %s, &%s, &edge_cb_id)",
            chunk_size, concat(params, ","), edge_type)
    end

    --- Generates match arms for chunk size dispatch
    --- @param max_size number Maximum chunk size
    --- @param edge_type string EdgeType enum value
    --- @return string Rust match arms
    local function gen_chunk_match_arms(max_size, edge_type)
        local arms = {}
        for i = 1, max_size do
            arms[#arms + 1] = f("                    %d => %s,", i, gen_register_callback_call(i, edge_type))
        end
        return concat(arms, "\n")
    end

    local EDGE_LOOP_TEMPLATE = [[
        for (complex_handle, task_id_vec) in &env.pending_{{suffix}}_cb_map {
            let mut idx = 0;
            let task_id_vec_size = task_id_vec.len();

            while idx < task_id_vec_size {
                let chunk_end = usize::min(idx + {{max_chunk}}, task_id_vec_size);
                let chunk = &task_id_vec[idx..chunk_end];
                let edge_cb_id = env.edge_cb_idpool.alloc_id();

                let cb_hdl = unsafe {
                    match chunk.len() {
{{match_arms}}
                        _ => unreachable!("{}", chunk.len()),
                    }
                };

                if let Some(_) = env.edge_cb_hdl_map.insert(edge_cb_id, cb_hdl as _) {
                    // TODO: Check ?
                    // panic!("duplicate edge callback id => {}", edge_cb_id);
                };

                idx = chunk_end;
            }
        }

]]

    local code_parts = {}
    for _, edge_type in ipairs(EDGE_TYPES) do
        code_parts[#code_parts + 1] = EDGE_LOOP_TEMPLATE:render({
            max_chunk = max_chunk,
            match_arms = gen_chunk_match_arms(max_chunk, edge_type),
            suffix = edge_type_to_suffix(edge_type)
        })
    end

    return "{" .. concat(code_parts, "") .. "}"
end

--[[
  Generates callback registration functions and callback handlers.

  For each chunk size (1 to MAX_CHUNK), generates:
    - EdgeCbDataChunk_N: Struct to hold callback data
    - do_register_edge_callback_chunk_N: Function to register the callback
    - edge_callback_chunk_N: Callback handler invoked by simulator

  Memory Layout:
      EdgeCbDataChunk_N {
          task_id_vec: [TaskID; N],     // Task IDs to schedule
          complex_handle_raw: Raw,       // VPI handle reference
          edge_type: EdgeType,           // Posedge/Negedge/Edge
          callback_id: ID,               // For callback management
          vpi_value: VPI value struct,   // Cached for reuse
          vpi_time: VPI time struct      // Cached for reuse
      }
--]]
local function gen_register_callback_func(max_chunk)
    local CHUNK_TEMPLATE = [[
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
        task_id_vec: [{{task_id_deref_values}}],
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
            .call::<()>({{lua_call_params}})
        {
            env.finalize();
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; {{max_chunk}}]> = smallvec::SmallVec::new();

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
                // #[cfg(feature = "debug")]
                // log::trace!("chunk_task[{{i}}] any_task_finished {:?}", user_data.task_id_vec);

                if !pending_cb_chunk.contains_key(&user_data.callback_id) {
                    pending_cb_chunk.insert(user_data.callback_id, (user_data.complex_handle_raw, user_data.task_id_vec.to_vec()));
                }
            } else {
                for task_id in finished_tasks {
                    cb_count.remove(&task_id);
                }

                pending_cb_chunk.remove(&user_data.callback_id);

                unsafe { vpi_remove_cb(*env.edge_cb_hdl_map.get(&user_data.callback_id).unwrap() as _) };
                env.edge_cb_idpool.release_id(user_data.callback_id);
            }
        }

        #[cfg(not(feature = "merge_cb"))]
        {
            unsafe { vpi_remove_cb(*env.edge_cb_hdl_map.get(&user_data.callback_id).unwrap() as _) };
            env.edge_cb_idpool.release_id(user_data.callback_id);
        }
    }
    0
}

]]

    local code_parts = {}
    for i = 1, max_chunk do
        -- Generate parameter lists
        local task_id_params = {}
        local task_id_deref_values = {}
        local task_id_vec_access = {}

        for j = 1, i do
            task_id_params[j] = f("task_id_%d: &TaskID", j)
            task_id_deref_values[j] = f("*task_id_%d", j)
            task_id_vec_access[j] = f("user_data.task_id_vec[%d]", j - 1)
        end

        -- Lua call params: single value or tuple
        local lua_call_params
        if i == 1 then
            lua_call_params = task_id_vec_access[1]
        else
            lua_call_params = "(" .. concat(task_id_vec_access, ",") .. ")"
        end

        code_parts[#code_parts + 1] = CHUNK_TEMPLATE:render({
            i = i,
            max_chunk = max_chunk,
            task_id_params = concat(task_id_params, ","),
            task_id_deref_values = concat(task_id_deref_values, ","),
            lua_call_params = lua_call_params
        })
    end

    return concat(code_parts, "")
end

--[[
  Generates VeriluaEnv struct definition with chunk task fields.

  Adds lua_sim_event_chunk_N fields for each chunk size, conditionally
  compiled with the "chunk_task" feature flag.
--]]
local function gen_verilua_env_struct(max_chunk)
    local STRUCT_TEMPLATE = [[
#[repr(C)]
#[derive(Debug)]
pub struct VeriluaEnv {
    pub hdl_cache: HashMap<String, ComplexHandleRaw>,
    pub hdl_put_value: Vec<ComplexHandleRaw>,
    pub hdl_put_value_bak: Vec<ComplexHandleRaw>,
    pub use_hdl_put_value_bak: bool,

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

{{chunk_fields}}

    pub edge_cb_idpool: IDPool,
    pub edge_cb_hdl_map: HashMap<EdgeCallbackID, u64>,

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
    pub has_next_sim_time_cb: bool,
}
]]

    local chunk_fields = {}
    for i = 1, max_chunk do
        chunk_fields[#chunk_fields + 1] = f("    #[cfg(feature = \"chunk_task\")]\n    pub lua_sim_event_chunk_%d: Option<LuaFunction>,", i)
    end

    return STRUCT_TEMPLATE:render({
        chunk_fields = concat(chunk_fields, "\n")
    })
end

--[[
  Generates VeriluaEnv initialization code.

  Creates the Self { ... } expression used in Default::default() impl.
--]]
local function gen_verilua_env_init(max_chunk)
    local INIT_TEMPLATE = [[
Self {
    hdl_cache: HashMap::new(),
    hdl_put_value: Vec::new(),
    hdl_put_value_bak: Vec::new(),
    use_hdl_put_value_bak: false,

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

    edge_cb_idpool: IDPool::new(100000), // The maximum number of edge callbacks is controlled by this value
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
    has_next_sim_time_cb: false,

{{chunk_init}}
}
]]

    local chunk_init = {}
    for i = 1, max_chunk do
        chunk_init[#chunk_init + 1] = f("    #[cfg(feature = \"chunk_task\")]\n    lua_sim_event_chunk_%d: None,", i)
    end

    return INIT_TEMPLATE:render({
        chunk_init = concat(chunk_init, "\n")
    })
end

--[[
  Generates Lua function reference initialization code.

  Called during VeriluaEnv::initialize() to load references to
  the sim_event_chunk_N functions from Lua globals.
--]]
local function gen_sim_event_chunk_init(max_chunk)
    local INIT_ITEM_TEMPLATE = [[
        self.lua_sim_event_chunk_{{i}} = Some(
            self.lua
                .globals()
                .get("sim_event_chunk_{{i}}")
                .expect("Failed to load sim_event_chunk_{{i}}")
        );]]

    local init_items = {}
    for i = 1, max_chunk do
        init_items[#init_items + 1] = INIT_ITEM_TEMPLATE:render({i = i})
    end

    return '#[cfg(feature = "chunk_task")]\n\t{' .. concat(init_items, "\n") .. "}"
end

--[[
  Generates Lua sim_event_chunk functions.

  These functions are called from Rust to schedule multiple tasks
  in a single Lua call, reducing cross-language overhead.

  Example output:
      _G.sim_event_chunk_2 = function(task_id_1, task_id_2)
          scheduler:schedule_task(task_id_1)
          scheduler:schedule_task(task_id_2)
      end
--]]
local function gen_lua_sim_event_chunk(max_chunk)
    local CHUNK_FUNC_TEMPLATE = [[

_G.sim_event_chunk_{{i}} = function({{params}})
{{body}}
end]]

    local code_parts = {}
    for i = 1, max_chunk do
        local params = {}
        local body_lines = {}

        for j = 1, i do
            local param_name = f("task_id_%d", j)
            params[#params + 1] = param_name
            body_lines[#body_lines + 1] = f("\tscheduler:schedule_task(%s)", param_name)
        end

        code_parts[#code_parts + 1] = CHUNK_FUNC_TEMPLATE:render({
            i = i,
            params = concat(params, ", "),
            body = concat(body_lines, "\n")
        })
    end

    return concat(code_parts, "")
end

--------------------------------------------------------------------------------
-- Main Entry Point
--------------------------------------------------------------------------------

local function main()
    print("================================================================================")
    print("  Verilua Code Generator")
    print(f("  MAX_CHUNK = %d", MAX_CHUNK))
    print("================================================================================")

    -- Generate and write all files
    write_file("gen_callback_policy.rs", gen_callback_policy(MAX_CHUNK))
    write_file("gen_register_callback_func.rs", gen_register_callback_func(MAX_CHUNK))
    write_file("gen_verilua_env_struct.rs", gen_verilua_env_struct(MAX_CHUNK))
    write_file("gen_verilua_env_init.rs", gen_verilua_env_init(MAX_CHUNK))
    write_file("gen_sim_event_chunk_init.rs", gen_sim_event_chunk_init(MAX_CHUNK))
    write_file("sim_event_chunk.lua", gen_lua_sim_event_chunk(MAX_CHUNK))

    print("================================================================================")
    print("  Generation complete!")
    print("================================================================================")
end

main()

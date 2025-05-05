#[repr(C)]
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

            #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_1: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_2: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_3: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_4: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_5: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_6: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_7: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_8: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_9: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_10: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_11: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_12: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_13: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_14: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_15: Option<LuaFunction>,
                #[cfg(feature = "chunk_task")]
        pub lua_sim_event_chunk_16: Option<LuaFunction>,
        

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

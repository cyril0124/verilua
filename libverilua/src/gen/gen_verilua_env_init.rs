Self {
    hdl_cache: HashMap::new(),

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

    initialized: false,
    finalized: false,
    has_start_cb: false,

            #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_1: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_2: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_3: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_4: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_5: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_6: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_7: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_8: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_9: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_10: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_11: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_12: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_13: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_14: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_15: None,
                #[cfg(feature = "chunk_task")]
        lua_sim_event_chunk_16: None,
        
}

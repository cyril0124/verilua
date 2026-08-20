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

    edge_cb_slab: slab::Slab::with_capacity(1024), // grows on demand; dense ids back the edge callbacks

    resolve_x_as_zero: false,
    rw_phase_passed: false,
    rw_cb_re_registered: false,
    flush_epoch: 0,
    rd_phase_active: false,
    start_time: Instant::now(),

    acc_lua_time: false,
    lua_time: Duration::default(),

    lua,
    lua_sim_event: 0,
    lua_main_step: None,
    lua_posedge_step: None,
    lua_negedge_step: None,

    initialized: false,
    finalized: false,
    has_start_cb: false,
    has_final_cb: false,
    has_next_sim_time_cb: false,

    #[cfg(feature = "chunk_task")]
    lua_sim_event_chunks: [0; SIM_EVENT_CHUNK_MAX],
}

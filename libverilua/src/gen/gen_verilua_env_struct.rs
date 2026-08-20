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

    #[cfg(feature = "chunk_task")]
    pub lua_sim_event_chunks: [i32; SIM_EVENT_CHUNK_MAX], // registry ids for sim_event_chunk_1..N

    pub edge_cb_slab: slab::Slab<u64>,

    pub resolve_x_as_zero: bool,
    pub rw_phase_passed: bool, // true after cbReadWriteSynch flush completes, reset at cbNextSimTime
    pub rw_cb_re_registered: bool, // guards against multiple re-registrations within one post-flush window
    pub flush_epoch: u64, // bumped each time apply_pending_put_values() commits >=1 value; used by await_rw wakeup deferral
    pub rd_phase_active: bool, // true while executing cbReadOnlySynch callbacks
    pub start_time: Instant,

    /// Runtime switch for Lua time accounting, set from `VL_ACC_LUA_TIME` in initialize()
    pub acc_lua_time: bool,
    pub lua_time: Duration,

    pub lua: Lua,
    /// Registry id of global `sim_event` (0 = unset). Hot path uses raw lua_pcall.
    pub lua_sim_event: i32,
    pub lua_main_step: Option<LuaFunction>,
    pub lua_posedge_step: Option<LuaFunction>,
    pub lua_negedge_step: Option<LuaFunction>,

    pub initialized: bool,
    pub finalized: bool,
    pub has_start_cb: bool,
    pub has_final_cb: bool,
    pub has_next_sim_time_cb: bool,
}

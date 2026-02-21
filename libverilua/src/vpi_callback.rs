//! # VPI Callback Module
//!
//! This module implements VPI callback registration and handling for Verilua.
//! It provides the bridge between HDL simulation events and Lua coroutine scheduling.
//!
//! ## VPI Callback Types
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────────────────┐
//! │                        VPI Callback Categories                              │
//! ├─────────────────────────────────────────────────────────────────────────────┤
//! │                                                                             │
//! │  ┌──────────────────────────────────────────────────────────────────────┐   │
//! │  │ Simulation Lifecycle Callbacks                                       │   │
//! │  │  • cbStartOfSimulation - Bootstrap verilua_init()                    │   │
//! │  │  • cbEndOfSimulation   - Finalize and cleanup                        │   │
//! │  └──────────────────────────────────────────────────────────────────────┘   │
//! │                                                                             │
//! │  ┌──────────────────────────────────────────────────────────────────────┐   │
//! │  │ Time-based Callbacks                                                 │   │
//! │  │  • cbNextSimTime  - Next simulation time tick (main driver)          │   │
//! │  │  • cbAfterDelay   - Scheduled future events (timer)                  │   │
//! │  └──────────────────────────────────────────────────────────────────────┘   │
//! │                                                                             │
//! │  ┌──────────────────────────────────────────────────────────────────────┐   │
//! │  │ Synchronization Callbacks                                            │   │
//! │  │  • cbReadWriteSynch - Apply pending put values (value settle)        │   │
//! │  │  • cbReadOnlySynch  - Read-only sync point                           │   │
//! │  └──────────────────────────────────────────────────────────────────────┘   │
//! │                                                                             │
//! │  ┌──────────────────────────────────────────────────────────────────────┐   │
//! │  │ Signal Callbacks                                                     │   │
//! │  │  • cbValueChange (posedge) - Rising edge detection                   │   │
//! │  │  • cbValueChange (negedge) - Falling edge detection                  │   │
//! │  │  • cbValueChange (edge)    - Any edge detection                      │   │
//! │  └──────────────────────────────────────────────────────────────────────┘   │
//! │                                                                             │
//! └─────────────────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Edge Callback Optimization (chunk_task + merge_cb)
//!
//! When both `chunk_task` and `merge_cb` features are enabled, edge callbacks
//! are batched and deduplicated for better performance:
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                 Edge Callback Batching Flow                     │
//! ├─────────────────────────────────────────────────────────────────┤
//! │                                                                 │
//! │  Lua: chdl:posedge_callback(task1)                              │
//! │  Lua: chdl:posedge_callback(task2)  ─┐                          │
//! │  Lua: chdl:posedge_callback(task1)   │  Multiple calls          │
//! │         │                            │                          │
//! │         ▼                            ▼                          │
//! │  ┌─────────────────────────────────────┐                        │
//! │  │ pending_posedge_cb_map              │  Accumulate tasks      │
//! │  │ {chdl → [task1, task2, task1]}      │                        │
//! │  └─────────────────────────────────────┘                        │
//! │         │                                                       │
//! │         ▼  (at NextSimTime)                                     │
//! │  ┌─────────────────────────────────────┐                        │
//! │  │ Merge: task1 appears twice          │                        │
//! │  │ Register: 1 callback for task1 (×2) │  Count-based           │
//! │  │ Register: 1 callback for task2 (×1) │                        │
//! │  └─────────────────────────────────────┘                        │
//! │                                                                 │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Callback Handler Flow
//!
//! ```text
//!   VPI Callback Triggered
//!          │
//!          ▼
//!   ┌──────────────┐
//!   │ Check edge   │  For edge callbacks only
//!   │ type match   │
//!   └──────────────┘
//!          │ matches
//!          ▼
//!   ┌──────────────┐
//!   │ Call Lua     │  env.lua_sim_event(task_id)
//!   │ sim_event    │
//!   └──────────────┘
//!          │
//!          ▼
//!   ┌──────────────┐
//!   │ Remove       │  For one-shot callbacks
//!   │ callback     │
//!   └──────────────┘
//! ```

#![allow(dead_code, non_camel_case_types, unused_variables)]
#[cfg(all(feature = "chunk_task", feature = "merge_cb"))]
use hashbrown::HashMap;

use crate::complex_handle::{ComplexHandle, ComplexHandleRaw};
use crate::verilua_env::{self, VeriluaEnv, get_verilua_env, get_verilua_env_no_init};
use crate::vpi_user::*;

use crate::EdgeCallbackID;
use crate::TaskID;

// ────────────────────────────────────────────────────────────────────────────────
// Edge Type Definitions
// ────────────────────────────────────────────────────────────────────────────────

/// Types of signal edge that can trigger a callback.
///
/// Used to specify what kind of signal transition should wake up a waiting task.
#[derive(Clone, Copy, Debug)]
#[repr(u8)]
pub enum EdgeType {
    /// Rising edge: signal transitions from 0 to 1
    Posedge = 0,
    /// Falling edge: signal transitions from 1 to 0
    Negedge = 1,
    /// Any edge: signal transitions in either direction
    Edge = 2,
}

/// Signal value state for edge detection comparison.
///
/// Mapped from VPI integer values to determine if edge condition is met.
#[derive(PartialEq, num_enum::TryFromPrimitive)]
#[repr(u8)]
pub enum EdgeValue {
    /// Logic low (0)
    Low = 0,
    /// Logic high (1)
    High = 1,
    /// Match any value (for EdgeType::Edge)
    DontCare = 2,
}

// ────────────────────────────────────────────────────────────────────────────────
// Callback Data Structures
// ────────────────────────────────────────────────────────────────────────────────

/// Information about a pending edge callback registration.
///
/// Used in the callback batching system to track what callbacks need
/// to be registered at the next simulation time.
#[derive(Debug)]
pub struct CallbackInfo {
    /// Type of edge to wait for
    pub edge_type: EdgeType,
    /// Lua task to resume when edge occurs
    pub task_id: TaskID,
}

/// User data passed to VPI for edge callbacks.
///
/// Contains all information needed to:
/// 1. Identify which task to resume
/// 2. Clean up the callback after triggering
/// 3. Provide time/value storage for VPI
pub struct EdgeCbData {
    /// Lua task ID to resume when edge is detected
    pub task_id: TaskID,
    /// Handle to the signal being monitored
    pub complex_handle_raw: ComplexHandleRaw,
    /// Type of edge that was registered
    pub edge_type: EdgeType,
    /// Unique ID for callback management (removal, reference counting)
    pub callback_id: EdgeCallbackID,
    /// VPI value structure for callback (required by VPI spec)
    pub vpi_value: t_vpi_value,
    /// VPI time structure for callback (required by VPI spec)
    pub vpi_time: t_vpi_time,
}

/// User data for simple callbacks (time-based, synch points).
///
/// Simpler than EdgeCbData since these callbacks don't need edge detection.
pub struct NormalCbData {
    pub task_id: TaskID,
}

/// Convert edge type to the expected signal value for comparison.
///
/// - Posedge expects High (signal went to 1)
/// - Negedge expects Low (signal went to 0)
/// - Edge matches DontCare (any transition)
#[inline(always)]
fn edge_type_to_value(edge_type: &EdgeType) -> EdgeValue {
    match edge_type {
        EdgeType::Posedge => EdgeValue::High,
        EdgeType::Negedge => EdgeValue::Low,
        EdgeType::Edge => EdgeValue::DontCare,
    }
}

// ────────────────────────────────────────────────────────────────────────────────
// Chunk Task Generated Code
// ────────────────────────────────────────────────────────────────────────────────

/// Includes generated callback registration functions for chunk_task optimization.
/// These functions batch multiple edge callbacks for the same signal type.
#[cfg(feature = "chunk_task")]
include!("./gen/gen_register_callback_func.rs");

// ────────────────────────────────────────────────────────────────────────────────
// Simulation Lifecycle Callbacks
// ────────────────────────────────────────────────────────────────────────────────

/// Registers a callback for simulation start.
///
/// This is called during VPI startup (typically from vlog_startup_routines).
/// The callback will trigger `verilua_init()` when simulation begins.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bootstrap_register_start_callback() {
    log::info!("bootstrap_register_start_callback");

    let env = get_verilua_env_no_init();
    if env.has_start_cb {
        return;
    } else {
        env.has_start_cb = true;
    }

    let mut cb_data = s_cb_data {
        reason: cbStartOfSimulation as _,
        cb_rtn: Some(start_callback),
        time: std::ptr::null_mut(),
        obj: std::ptr::null_mut(),
        user_data: std::ptr::null_mut(),
        value: std::ptr::null_mut(),
        index: 0,
    };

    let handle = unsafe { vpi_register_cb(&mut cb_data) };
    unsafe { vpi_free_object(handle) };
}

/// VPI callback handler for simulation start.
/// Initializes the Verilua environment when simulation begins.
unsafe extern "C" fn start_callback(_cb_data: *mut t_cb_data) -> PLI_INT32 {
    log::info!("start_callback");

    unsafe {
        verilua_env::verilua_init();
        bootstrap_register_next_sim_time_callback();
    }

    0
}

/// Internal helper to register final callback with proper environment reference.
#[inline(always)]
fn do_register_final_callback(env: &mut VeriluaEnv) {
    if env.has_final_cb {
        return;
    } else {
        env.has_final_cb = true;
    }

    let mut cb_data = s_cb_data {
        reason: cbEndOfSimulation as _,
        cb_rtn: Some(final_callback),
        time: std::ptr::null_mut(),
        obj: std::ptr::null_mut(),
        user_data: env as *mut _ as *mut i8,
        value: std::ptr::null_mut(),
        index: 0,
    };

    let handle = unsafe { vpi_register_cb(&mut cb_data) };
    unsafe { vpi_free_object(handle) };
}

/// Registers end-of-simulation callback (DPI variant).
///
/// When using DPI mode, the environment pointer must be passed explicitly
/// since we may not be able to use global state.
#[cfg(feature = "dpi")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bootstrap_register_final_callback(env: *mut libc::c_void) {
    log::info!("bootstrap_register_final_callback(dpi)");

    let env = VeriluaEnv::from_void_ptr(env);
    do_register_final_callback(env);
}

/// Registers end-of-simulation callback (VPI variant).
///
/// Standard VPI mode uses global environment state.
#[cfg(not(feature = "dpi"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bootstrap_register_final_callback() {
    log::info!("bootstrap_register_final_callback");

    let env = get_verilua_env_no_init();
    do_register_final_callback(env);
}

/// VPI callback handler for simulation end.
/// Calls finalize to print statistics and cleanup.
unsafe extern "C" fn final_callback(_cb_data: *mut t_cb_data) -> PLI_INT32 {
    log::info!("final_callback");
    let env = unsafe { &mut *((*_cb_data).user_data as *mut VeriluaEnv) };
    env.finalize();
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_rd_synch_callback(task_id: TaskID) {
    let user_data = Box::into_raw(Box::new(NormalCbData { task_id: task_id }));

    let mut cb_data = s_cb_data {
        reason: cbReadOnlySynch as _,
        cb_rtn: Some(rd_synch_callback),
        time: &mut t_vpi_time {
            type_: vpiSimTime as _,
            high: 0,
            low: 0,
            real: 0.0,
        },
        obj: std::ptr::null_mut(),
        user_data: user_data as *mut _,
        value: std::ptr::null_mut(),
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) };
}

unsafe extern "C" fn rd_synch_callback(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let user_data: Box<NormalCbData> =
        unsafe { Box::from_raw(cb_data.user_data as *mut NormalCbData) };
    let env = get_verilua_env();

    unsafe {
        if let Err(e) = env
            .lua_sim_event
            .as_ref()
            .unwrap_unchecked()
            .call::<()>(user_data.task_id)
        {
            env.finalize();
            panic!("{}", e);
        }
    }

    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_rw_synch_callback(task_id: TaskID) {
    let user_data = Box::into_raw(Box::new(NormalCbData { task_id: task_id }));

    let mut cb_data = s_cb_data {
        reason: cbReadWriteSynch as _,
        cb_rtn: Some(rw_synch_callback),
        time: &mut t_vpi_time {
            type_: vpiSimTime as _,
            high: 0,
            low: 0,
            real: 0.0,
        },
        obj: std::ptr::null_mut(),
        user_data: user_data as *mut _,
        value: std::ptr::null_mut(),
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) };
}

unsafe extern "C" fn rw_synch_callback(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let user_data: Box<NormalCbData> =
        unsafe { Box::from_raw(cb_data.user_data as *mut NormalCbData) };
    let env = get_verilua_env();

    unsafe {
        if let Err(e) = env
            .lua_sim_event
            .as_ref()
            .unwrap_unchecked()
            .call::<()>(user_data.task_id)
        {
            env.finalize();
            panic!("{}", e);
        }
    }

    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_next_sim_time_callback(task_id: TaskID) {
    let user_data = Box::into_raw(Box::new(NormalCbData { task_id: task_id }));

    let mut t = t_vpi_time {
        type_: vpiSimTime as _,
        high: 0,
        low: 0,
        real: 0.0,
    };

    let mut cb_data = s_cb_data {
        reason: cbNextSimTime as _,
        cb_rtn: Some(next_sim_time_callback),
        time: &mut t,
        obj: std::ptr::null_mut(),
        user_data: user_data as *mut _,
        value: std::ptr::null_mut(),
        index: 0,
    };

    let handle = unsafe { vpi_register_cb(&mut cb_data as _) };
    unsafe { vpi_free_object(handle) };
}

unsafe extern "C" fn next_sim_time_callback(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let user_data: Box<NormalCbData> =
        unsafe { Box::from_raw(cb_data.user_data as *mut NormalCbData) };
    let env = get_verilua_env();

    unsafe {
        if let Err(e) = env
            .lua_sim_event
            .as_ref()
            .unwrap_unchecked()
            .call::<()>(user_data.task_id)
        {
            env.finalize();
            panic!("{}", e);
        }
    }

    0
}

#[inline(always)]
#[unsafe(no_mangle)]
unsafe extern "C" fn libverilua_register_rw_synch_cb() {
    // `ReadWriteSynch` callback is used to settle value changes(e.g. put value or force value) in Verilua

    let mut t = t_vpi_time {
        type_: vpiSimTime as _,
        high: 0,
        low: 0,
        real: 0.0,
    };

    let mut cb_data = s_cb_data {
        reason: cbReadWriteSynch as _,
        cb_rtn: Some(libverilua_flush_put_values),
        time: &mut t,
        obj: std::ptr::null_mut(),
        user_data: std::ptr::null_mut(),
        value: std::ptr::null_mut(),
        index: 0,
    };

    let handle = unsafe { vpi_register_cb(&mut cb_data as _) };
    unsafe { vpi_free_object(handle) };
}

unsafe extern "C" fn libverilua_flush_put_values(cb_data: *mut t_cb_data) -> PLI_INT32 {
    if !cfg!(feature = "inertial_put") {
        let env: &'static mut VeriluaEnv = get_verilua_env();

        // Apply pending put values(or do value settles)
        // Here all signal values are updated to HDL
        env.apply_pending_put_values();
    }

    if !cfg!(feature = "verilator_inner_step_callback") {
        libverilua_do_register_next_sim_time_cb();
    }

    0
}

#[inline(always)]
fn libverilua_do_register_next_sim_time_cb() {
    // `libverilua_do_register_next_sim_time_cb` will be called in `libverilua_flush_put_values`
    // since we do all value settles in the `ReadWriteSynch` callback
    let mut t = t_vpi_time {
        type_: vpiSimTime as _,
        high: 0,
        low: 0,
        real: 0.0,
    };

    let mut cb_data = s_cb_data {
        reason: cbNextSimTime as _,
        cb_rtn: Some(libverilua_next_sim_time_cb),
        time: &mut t,
        obj: std::ptr::null_mut(),
        user_data: std::ptr::null_mut(),
        value: std::ptr::null_mut(),
        index: 0,
    };

    let handle = unsafe { vpi_register_cb(&mut cb_data as _) };
    unsafe { vpi_free_object(handle) };
}

/// Bootstrap function to register the next simulation time callback.
///
/// # Important Note (IEEE 1800 LRM 36.10.2)
///
/// According to the SystemVerilog LRM section 36.10.2, `vpi_register_cb()` with `cbNextSimTime`
/// **MUST NOT** be called from within `vlog_startup_routines`. The LRM specifies that:
///
/// > "The cbNextSimTime callback shall not be allowed in vlog_startup_routines."
///
/// Therefore, this function should only be called during the simulation initialization phase
/// (e.g., from within a `cbStartOfSimulation` callback), not directly from the startup routines array.
///
/// This function is expected to be called only once as a bootstrap step.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bootstrap_register_next_sim_time_callback() {
    let env = get_verilua_env_no_init();
    if env.has_next_sim_time_cb {
        return;
    } else {
        env.has_next_sim_time_cb = true;
    }

    if !cfg!(feature = "verilator_inner_step_callback") {
        libverilua_do_register_next_sim_time_cb();
    }
}

pub unsafe extern "C" fn libverilua_next_sim_time_cb(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let env = get_verilua_env();

    if cfg!(feature = "opt_cb_task") {
        #[cfg(all(feature = "chunk_task", feature = "merge_cb"))]
        {
            #[inline(always)]
            fn process_cb_chunk<'a>(
                cb_chunk: &'a HashMap<EdgeCallbackID, (ComplexHandleRaw, Vec<TaskID>)>,
                cb_map: &mut HashMap<ComplexHandleRaw, Vec<TaskID>>,
            ) {
                for (_, (complex_handle_raw, task_id_vec)) in cb_chunk {
                    if let Some(pending_cb_vec) = cb_map.get_mut(complex_handle_raw) {
                        let mut all_match = true;
                        for task_id in task_id_vec {
                            if !pending_cb_vec.contains(task_id) {
                                all_match = false;
                                break;
                            }
                        }

                        if all_match {
                            pending_cb_vec.retain(|id| !task_id_vec.contains(id));

                            if pending_cb_vec.is_empty() {
                                cb_map.remove(complex_handle_raw);
                            }
                        }
                    }
                }
            }

            process_cb_chunk(
                &env.pending_posedge_cb_chunk,
                &mut env.pending_posedge_cb_map,
            );
            process_cb_chunk(
                &env.pending_negedge_cb_chunk,
                &mut env.pending_negedge_cb_map,
            );
            process_cb_chunk(&env.pending_edge_cb_chunk, &mut env.pending_edge_cb_map);
        }

        #[cfg(feature = "chunk_task")]
        include!("./gen/gen_callback_policy.rs");

        #[cfg(not(feature = "chunk_task"))]
        for (complex_handle_raw, cb_infos) in &env.pending_edge_cb_map {
            let complex_handle = ComplexHandle::from_raw(complex_handle_raw);
            for cb_info in cb_infos {
                let edge_cb_id = env.edge_cb_idpool.alloc_id();
                let cb_hdl = unsafe {
                    do_register_edge_callback(
                        complex_handle_raw,
                        &cb_info.task_id,
                        &cb_info.edge_type,
                        &edge_cb_id,
                    )
                };

                if let Some(_) = env.edge_cb_hdl_map.insert(edge_cb_id, cb_hdl as _) {
                    // TODO: Check ?
                    // panic!("duplicate edge callback id => {}", edge_cb_id);
                };
            }
        }

        #[cfg(feature = "chunk_task")]
        {
            env.pending_posedge_cb_map.clear();
            env.pending_negedge_cb_map.clear();
            env.pending_edge_cb_map.clear();
        }

        #[cfg(not(feature = "chunk_task"))]
        env.pending_edge_cb_map.clear();
    }

    if cfg!(feature = "wave_vpi") {
        let handle = unsafe { vpi_register_cb(cb_data) };
        unsafe { vpi_free_object(handle) };
    } else {
        // NextSimTime callback will be registered in ReadWriteSynch callback
        unsafe { libverilua_register_rw_synch_cb() };
    }

    0
}

#[inline(always)]
unsafe fn do_register_edge_callback(
    complex_handle_raw: &ComplexHandleRaw,
    task_id: &TaskID,
    edge_type: &EdgeType,
    edge_cb_id: &EdgeCallbackID,
) -> vpiHandle {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbData {
        task_id: *task_id,
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
        cb_rtn: Some(edge_callback),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}

unsafe extern "C" fn edge_callback(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value =
        EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbData = unsafe { &*(cb_data.user_data as *const EdgeCbData) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare {
        let env = VeriluaEnv::from_complex_handle_raw(user_data.complex_handle_raw);

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        unsafe {
            if let Err(e) = env
                .lua_sim_event
                .as_ref()
                .unwrap_unchecked()
                .call::<()>(user_data.task_id)
            {
                env.finalize();
                panic!("{}", e);
            }
        }

        #[cfg(feature = "acc_time")]
        {
            env.lua_time += s.elapsed();
        }

        if cfg!(feature = "opt_cb_task") {
            #[cfg(feature = "merge_cb")]
            {
                let complex_handle = ComplexHandle::from_raw(&user_data.complex_handle_raw);

                let remove_cb = match user_data.edge_type {
                    EdgeType::Posedge => {
                        let t = complex_handle
                            .posedge_cb_count
                            .get_mut(&user_data.task_id)
                            .unwrap_unchecked();
                        *t -= 1;
                        *t == 0
                    }
                    EdgeType::Negedge => {
                        let t = complex_handle
                            .negedge_cb_count
                            .get_mut(&user_data.task_id)
                            .unwrap_unchecked();
                        *t -= 1;
                        *t == 0
                    }
                    EdgeType::Edge => {
                        let t = complex_handle
                            .edge_cb_count
                            .get_mut(&user_data.task_id)
                            .unwrap_unchecked();
                        *t -= 1;
                        *t == 0
                    }
                };

                if remove_cb {
                    unsafe {
                        vpi_remove_cb(
                            *env.edge_cb_hdl_map
                                .get(&user_data.callback_id)
                                .unwrap_unchecked() as _,
                        )
                    };
                    env.edge_cb_idpool.release_id(user_data.callback_id);
                }
            }

            #[cfg(not(feature = "merge_cb"))]
            {
                unsafe {
                    vpi_remove_cb(
                        *env.edge_cb_hdl_map
                            .get(&user_data.callback_id)
                            .unwrap_unchecked() as _,
                    )
                };
                env.edge_cb_idpool.release_id(user_data.callback_id);
            }
        } else {
            unsafe {
                vpi_remove_cb(
                    *env.edge_cb_hdl_map
                        .get(&user_data.callback_id)
                        .unwrap_unchecked() as _,
                )
            };
            env.edge_cb_idpool.release_id(user_data.callback_id);
        }
    }
    0
}

struct TaskIDWithEnv {
    env: *mut libc::c_void,
    task_id: TaskID,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_time_callback(
    env: *mut libc::c_void,
    time: u64,
    task_id: TaskID,
) {
    let mut t = t_vpi_time {
        type_: vpiSimTime as _,
        high: (time >> 32) as _,
        low: (time & 0xFFFFFFFF) as _,
        real: 0.0,
    };

    let mut cb_data = s_cb_data {
        reason: cbAfterDelay as _,
        cb_rtn: Some(time_callback_handler),
        time: &mut t,
        obj: std::ptr::null_mut(),
        user_data: Box::into_raw(Box::new(TaskIDWithEnv { env, task_id })) as *mut _,
        value: std::ptr::null_mut(),
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data as _) };
}

unsafe extern "C" fn time_callback_handler(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let task_id_with_env = unsafe { Box::from_raw((*cb_data).user_data as *mut TaskIDWithEnv) };
    let task_id = task_id_with_env.task_id;
    let env = VeriluaEnv::from_void_ptr(task_id_with_env.env);

    #[cfg(feature = "acc_time")]
    let s = std::time::Instant::now();

    unsafe {
        if let Err(e) = env
            .lua_sim_event
            .as_ref()
            .unwrap_unchecked()
            .call::<()>(task_id)
        {
            env.finalize();
            panic!("{}", e);
        }
    }

    #[cfg(feature = "acc_time")]
    {
        env.lua_time += s.elapsed()
    }
    0
}

macro_rules! gen_vpiml_register_edge_callback {
    ($(($edge_type:ident, $edge_type_enum:ty)),*) => {
        // Generate the callback function for the edge type: vpiml_register_<edge_type>_callback_hdl
        $(
            paste::paste! {
                #[inline(always)]
                unsafe fn [<vpiml_register_ $edge_type _callback_common>](complex_handle_raw: ComplexHandleRaw, task_id: TaskID) {
                    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);

                    if cfg!(feature = "opt_cb_task") {
                        #[cfg(feature = "merge_cb")]
                        {
                            let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);

                            let t = complex_handle.[<$edge_type _cb_count>].entry(task_id).or_default();
                            *t += 1;

                            #[cfg(not(feature = "chunk_task"))]
                            if *t > 1 {
                                return;
                            }
                        }

                        #[cfg(feature = "chunk_task")]
                        {
                            env.[<pending_ $edge_type _cb_map>].entry(complex_handle_raw)
                                .or_insert_with(|| Vec::with_capacity(32))
                                .push(task_id);
                        }

                        #[cfg(not(feature = "chunk_task"))]
                        env.pending_edge_cb_map
                            .entry(complex_handle_raw)
                            .or_insert_with(|| Vec::with_capacity(32))
                            .push(CallbackInfo {
                                edge_type: $edge_type_enum,
                                task_id,
                            });
                    } else {
                        let edge_cb_id = env.edge_cb_idpool.alloc_id();
                        let cb_hdl = unsafe { do_register_edge_callback(
                            &complex_handle_raw,
                            &task_id,
                            &$edge_type_enum,
                            &edge_cb_id
                        ) };

                        if let Some(_) = env.edge_cb_hdl_map.insert(edge_cb_id, cb_hdl as _) {
                            // TODO: Check ?
                            // panic!("duplicate edge callback id => {}", edge_cb_id);
                        };
                    }
                }

                #[unsafe(no_mangle)]
                pub unsafe extern "C" fn [<vpiml_register_ $edge_type _callback>](complex_handle_raw: ComplexHandleRaw, task_id: TaskID) {
                    unsafe { [<vpiml_register_ $edge_type _callback_common>](complex_handle_raw, task_id) };
                }
            }
        )*
    };
}
gen_vpiml_register_edge_callback!(
    (posedge, EdgeType::Posedge),
    (negedge, EdgeType::Negedge),
    (edge, EdgeType::Edge)
);

#[inline(always)]
unsafe fn do_register_edge_callback_always(
    complex_handle_raw: &ComplexHandleRaw,
    task_id: &TaskID,
    edge_type: &EdgeType,
    edge_cb_id: &EdgeCallbackID,
) -> vpiHandle {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbData {
        task_id: *task_id,
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
        cb_rtn: Some(edge_callback_always),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}

unsafe extern "C" fn edge_callback_always(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value =
        EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbData = unsafe { &*(cb_data.user_data as *const EdgeCbData) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        unsafe {
            if let Err(e) = env
                .lua_sim_event
                .as_ref()
                .unwrap_unchecked()
                .call::<()>(user_data.task_id)
            {
                env.finalize();
                panic!("{}", e);
            }
        }

        #[cfg(feature = "acc_time")]
        {
            env.lua_time += s.elapsed();
        }
    }
    0
}

macro_rules! gen_vpiml_register_edge_callback_always {
    // Generate the callback function for the edge type: vpiml_register_<edge_type>_callback_always
    ($(($edge_type:ident, $edge_type_enum:ty)),*) => {
        $(
            paste::paste! {
                #[unsafe(no_mangle)]
                pub unsafe extern "C" fn [<vpiml_register_ $edge_type _callback_always>](complex_handle_raw: ComplexHandleRaw, task_id: TaskID) {
                    let env = get_verilua_env();
                    unsafe { do_register_edge_callback_always(&complex_handle_raw, &task_id, &$edge_type_enum, &env.edge_cb_idpool.alloc_id()) };
                }
            }
        )*
    };
}

gen_vpiml_register_edge_callback_always!(
    (posedge, EdgeType::Posedge),
    (negedge, EdgeType::Negedge),
    (edge, EdgeType::Edge)
);

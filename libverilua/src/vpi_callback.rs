#![allow(dead_code, non_camel_case_types, unused_variables)]
use hashbrown::{HashMap, HashSet};
use libc::c_char;
use std::cell::Cell;

use crate::complex_handle::{ComplexHandle, ComplexHandleRaw};
use crate::verilua_env::{self, VeriluaEnv, get_verilua_env, get_verilua_env_no_init};
use crate::vpi_access::complex_handle_by_name;
use crate::vpi_user::*;

use crate::EdgeCallbackID;
use crate::TaskID;

#[derive(Clone, Copy, Debug)]
#[repr(u8)]
pub enum EdgeType {
    Posedge = 0,
    Negedge = 1,
    Edge = 2,
}

#[derive(PartialEq, num_enum::TryFromPrimitive)]
#[repr(u8)]
pub enum EdgeValue {
    Low = 0,
    High = 1,
    DontCare = 2,
}

#[derive(Debug)]
pub struct CallbackInfo {
    pub edge_type: EdgeType,
    pub task_id: TaskID,
}

pub struct EdgeCbData {
    pub task_id: TaskID,
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}

#[inline(always)]
fn edge_type_to_value(edge_type: &EdgeType) -> EdgeValue {
    match edge_type {
        EdgeType::Posedge => EdgeValue::High,
        EdgeType::Negedge => EdgeValue::Low,
        EdgeType::Edge => EdgeValue::DontCare,
    }
}

#[cfg(feature = "chunk_task")]
include!("./gen/gen_register_callback_func.rs");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_start_callback() {
    log::debug!("vpiml_register_start_callback");

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

unsafe extern "C" fn start_callback(_cb_data: *mut t_cb_data) -> PLI_INT32 {
    log::debug!("start_callback");

    unsafe { verilua_env::verilua_init() };
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_final_callback() {
    log::debug!("vpiml_register_final_callback");

    let env = get_verilua_env_no_init();
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

unsafe extern "C" fn final_callback(_cb_data: *mut t_cb_data) -> PLI_INT32 {
    log::debug!("final_callback");
    let env = unsafe { &mut *((*_cb_data).user_data as *mut VeriluaEnv) };
    env.finalize();
    0
}

#[inline(always)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_read_write_synch_callback() {
    log::debug!("vpiml_register_read_write_synch_callback()");

    let mut t = t_vpi_time {
        type_: vpiSimTime as _,
        high: 0,
        low: 0,
        real: 0.0,
    };

    let mut cb_data = s_cb_data {
        reason: cbReadWriteSynch as _,
        cb_rtn: Some(read_write_synch_callback),
        time: &mut t,
        obj: std::ptr::null_mut(),
        user_data: std::ptr::null_mut(),
        value: std::ptr::null_mut(),
        index: 0,
    };

    let handle = unsafe { vpi_register_cb(&mut cb_data as _) };
    unsafe { vpi_free_object(handle) };
}

unsafe extern "C" fn read_write_synch_callback(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let env = get_verilua_env();
    env.apply_pending_put_values();

    do_register_next_sim_time_callback();
    0
}

#[inline(always)]
fn do_register_next_sim_time_callback() {
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
        user_data: std::ptr::null_mut(),
        value: std::ptr::null_mut(),
        index: 0,
    };

    let handle = unsafe { vpi_register_cb(&mut cb_data as _) };
    unsafe { vpi_free_object(handle) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_next_sim_time_callback() {
    let env = get_verilua_env_no_init();
    if env.has_next_sim_time_cb {
        return;
    } else {
        env.has_next_sim_time_cb = true;
    }

    do_register_next_sim_time_callback();
}

unsafe extern "C" fn next_sim_time_callback(cb_data: *mut t_cb_data) -> PLI_INT32 {
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

                if let Some(_) = env.edge_cb_hdl_map.insert(edge_cb_id, cb_hdl) {
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
        unsafe { vpiml_register_read_write_synch_callback() };
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
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event
            .as_ref()
            .unwrap()
            .call::<()>(user_data.task_id)
        {
            env.finalize();
            panic!("{}", e);
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
                            .unwrap();
                        *t -= 1;
                        *t == 0
                    }
                    EdgeType::Negedge => {
                        let t = complex_handle
                            .negedge_cb_count
                            .get_mut(&user_data.task_id)
                            .unwrap();
                        *t -= 1;
                        *t == 0
                    }
                    EdgeType::Edge => {
                        let t = complex_handle
                            .edge_cb_count
                            .get_mut(&user_data.task_id)
                            .unwrap();
                        *t -= 1;
                        *t == 0
                    }
                };

                if remove_cb {
                    unsafe {
                        vpi_remove_cb(*env.edge_cb_hdl_map.get(&user_data.callback_id).unwrap() as _)
                    };
                    env.edge_cb_idpool.release_id(user_data.callback_id);
                }
            }

            #[cfg(not(feature = "merge_cb"))]
            {
                unsafe {
                    vpi_remove_cb(*env.edge_cb_hdl_map.get(&user_data.callback_id).unwrap() as _)
                };
                env.edge_cb_idpool.release_id(user_data.callback_id);
            }
        } else {
            unsafe {
                vpi_remove_cb(*env.edge_cb_hdl_map.get(&user_data.callback_id).unwrap() as _)
            };
            env.edge_cb_idpool.release_id(user_data.callback_id);
        }
    }
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_register_time_callback(time: u64, task_id: TaskID) {
    let mut t = t_vpi_time {
        type_: vpiSimTime as _,
        high: (time >> 32) as _,
        low: (time & 0xFFFF) as _,
        real: 0.0,
    };

    let mut cb_data = s_cb_data {
        reason: cbAfterDelay as _,
        cb_rtn: Some(time_callback_handler),
        time: &mut t,
        obj: std::ptr::null_mut(),
        user_data: Box::into_raw(Box::new(task_id)) as *mut _,
        value: std::ptr::null_mut(),
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data as _) };
}

unsafe extern "C" fn time_callback_handler(cb_data: *mut t_cb_data) -> PLI_INT32 {
    // let task_id = *Box::from_raw((*cb_data).user_data as *mut TaskID);
    let task_id = unsafe { *((*cb_data).user_data as *const TaskID) };
    let env = get_verilua_env();

    #[cfg(feature = "acc_time")]
    let s = std::time::Instant::now();

    if let Err(e) = env.lua_sim_event.as_ref().unwrap().call::<()>(task_id) {
        panic!("{}", e);
    };

    #[cfg(feature = "acc_time")]
    {
        env.lua_time += s.elapsed()
    }
    0
}

macro_rules! gen_vpiml_register_edge_callback {
    ($(($edge_type:ident, $edge_type_enum:ty)),*) => {
        // Generate the callback function for the edge type:
        //  1. vpiml_register_<edge_type>_callback_hdl
        //  2. vpiml_register_<edge_type>_callback
        $(
            paste::paste! {
                #[inline(always)]
                unsafe fn [<vpiml_register_ $edge_type _callback_common>](complex_handle_raw: ComplexHandleRaw, task_id: TaskID) {
                    let env = get_verilua_env();

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
                        let cb_hdl = do_register_edge_callback(
                            &complex_handle_raw,
                            &task_id,
                            &$edge_type_enum,
                            &edge_cb_id
                        );

                        if let Some(_) = env.edge_cb_hdl_map.insert(edge_cb_id, cb_hdl as _) {
                            // TODO: Check ?
                            // panic!("duplicate edge callback id => {}", edge_cb_id);
                        };
                    }
                }

                #[unsafe(no_mangle)]
                pub unsafe extern "C" fn [<vpiml_register_ $edge_type _callback_hdl>](complex_handle_raw: ComplexHandleRaw, task_id: TaskID) {
                    unsafe { [<vpiml_register_ $edge_type _callback_common>](complex_handle_raw, task_id) };
                }

                #[unsafe(no_mangle)]
                pub unsafe extern "C" fn [<vpiml_register_ $edge_type _callback>](path: *mut c_char, task_id: TaskID) {
                    let complex_handle_raw = unsafe { complex_handle_by_name(path, std::ptr::null_mut()) };
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

        if let Err(e) = env
            .lua_sim_event
            .as_ref()
            .unwrap()
            .call::<()>(user_data.task_id)
        {
            panic!("{}", e);
        }

        #[cfg(feature = "acc_time")]
        {
            env.lua_time += s.elapsed();
        }
    }
    0
}

macro_rules! gen_vpiml_register_edge_callback_always {
    // Generate the callback function for the edge type:
    //  1. vpiml_register_<edge_type>_callback_hdl_always
    //  2. vpiml_register_<edge_type>_callback_always
    ($(($edge_type:ident, $edge_type_enum:ty)),*) => {
        $(
            paste::paste! {
                #[unsafe(no_mangle)]
                pub unsafe extern "C" fn [<vpiml_register_ $edge_type _callback_hdl_always>](complex_handle_raw: ComplexHandleRaw, task_id: TaskID) {
                    let env = get_verilua_env();
                    unsafe { do_register_edge_callback_always(&complex_handle_raw, &task_id, &$edge_type_enum, &env.edge_cb_idpool.alloc_id()) };
                }

                #[unsafe(no_mangle)]
                pub unsafe extern "C" fn [<vpiml_register_ $edge_type _callback_always>](path: *mut c_char, task_id: TaskID) {
                    let complex_handle_raw = unsafe { complex_handle_by_name(path, std::ptr::null_mut()) };
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

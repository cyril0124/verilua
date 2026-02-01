struct EdgeCbDataChunk_1 {
    pub task_id_vec: [TaskID; 1],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_1(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_1 {
        task_id_vec: [*task_id_1],
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
        cb_rtn: Some(edge_callback_chunk_1),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_1(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_1 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_1) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_1
            .as_ref()
            .unwrap()
            .call::<()>(user_data.task_id_vec[0])
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[1] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_2 {
    pub task_id_vec: [TaskID; 2],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_2(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_2 {
        task_id_vec: [*task_id_1,*task_id_2],
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
        cb_rtn: Some(edge_callback_chunk_2),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_2(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_2 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_2) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_2
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[2] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_3 {
    pub task_id_vec: [TaskID; 3],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_3(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_3 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3],
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
        cb_rtn: Some(edge_callback_chunk_3),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_3(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_3 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_3) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_3
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[3] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_4 {
    pub task_id_vec: [TaskID; 4],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_4(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_4 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4],
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
        cb_rtn: Some(edge_callback_chunk_4),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_4(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_4 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_4) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_4
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[4] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_5 {
    pub task_id_vec: [TaskID; 5],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_5(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_5 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5],
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
        cb_rtn: Some(edge_callback_chunk_5),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_5(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_5 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_5) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_5
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[5] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_6 {
    pub task_id_vec: [TaskID; 6],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_6(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_6 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6],
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
        cb_rtn: Some(edge_callback_chunk_6),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_6(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_6 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_6) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_6
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[6] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_7 {
    pub task_id_vec: [TaskID; 7],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_7(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_7 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7],
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
        cb_rtn: Some(edge_callback_chunk_7),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_7(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_7 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_7) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_7
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[7] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_8 {
    pub task_id_vec: [TaskID; 8],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_8(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_8 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8],
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
        cb_rtn: Some(edge_callback_chunk_8),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_8(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_8 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_8) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_8
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[8] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_9 {
    pub task_id_vec: [TaskID; 9],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_9(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID,task_id_9: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_9 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8,*task_id_9],
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
        cb_rtn: Some(edge_callback_chunk_9),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_9(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_9 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_9) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_9
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7],user_data.task_id_vec[8]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[9] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_10 {
    pub task_id_vec: [TaskID; 10],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_10(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID,task_id_9: &TaskID,task_id_10: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_10 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8,*task_id_9,*task_id_10],
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
        cb_rtn: Some(edge_callback_chunk_10),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_10(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_10 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_10) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_10
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7],user_data.task_id_vec[8],user_data.task_id_vec[9]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[10] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_11 {
    pub task_id_vec: [TaskID; 11],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_11(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID,task_id_9: &TaskID,task_id_10: &TaskID,task_id_11: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_11 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8,*task_id_9,*task_id_10,*task_id_11],
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
        cb_rtn: Some(edge_callback_chunk_11),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_11(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_11 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_11) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_11
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7],user_data.task_id_vec[8],user_data.task_id_vec[9],user_data.task_id_vec[10]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[11] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_12 {
    pub task_id_vec: [TaskID; 12],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_12(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID,task_id_9: &TaskID,task_id_10: &TaskID,task_id_11: &TaskID,task_id_12: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_12 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8,*task_id_9,*task_id_10,*task_id_11,*task_id_12],
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
        cb_rtn: Some(edge_callback_chunk_12),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_12(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_12 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_12) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_12
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7],user_data.task_id_vec[8],user_data.task_id_vec[9],user_data.task_id_vec[10],user_data.task_id_vec[11]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[12] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_13 {
    pub task_id_vec: [TaskID; 13],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_13(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID,task_id_9: &TaskID,task_id_10: &TaskID,task_id_11: &TaskID,task_id_12: &TaskID,task_id_13: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_13 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8,*task_id_9,*task_id_10,*task_id_11,*task_id_12,*task_id_13],
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
        cb_rtn: Some(edge_callback_chunk_13),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_13(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_13 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_13) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_13
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7],user_data.task_id_vec[8],user_data.task_id_vec[9],user_data.task_id_vec[10],user_data.task_id_vec[11],user_data.task_id_vec[12]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[13] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_14 {
    pub task_id_vec: [TaskID; 14],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_14(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID,task_id_9: &TaskID,task_id_10: &TaskID,task_id_11: &TaskID,task_id_12: &TaskID,task_id_13: &TaskID,task_id_14: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_14 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8,*task_id_9,*task_id_10,*task_id_11,*task_id_12,*task_id_13,*task_id_14],
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
        cb_rtn: Some(edge_callback_chunk_14),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_14(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_14 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_14) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_14
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7],user_data.task_id_vec[8],user_data.task_id_vec[9],user_data.task_id_vec[10],user_data.task_id_vec[11],user_data.task_id_vec[12],user_data.task_id_vec[13]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[14] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_15 {
    pub task_id_vec: [TaskID; 15],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_15(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID,task_id_9: &TaskID,task_id_10: &TaskID,task_id_11: &TaskID,task_id_12: &TaskID,task_id_13: &TaskID,task_id_14: &TaskID,task_id_15: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_15 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8,*task_id_9,*task_id_10,*task_id_11,*task_id_12,*task_id_13,*task_id_14,*task_id_15],
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
        cb_rtn: Some(edge_callback_chunk_15),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_15(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_15 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_15) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_15
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7],user_data.task_id_vec[8],user_data.task_id_vec[9],user_data.task_id_vec[10],user_data.task_id_vec[11],user_data.task_id_vec[12],user_data.task_id_vec[13],user_data.task_id_vec[14]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[15] any_task_finished {:?}", user_data.task_id_vec);

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

struct EdgeCbDataChunk_16 {
    pub task_id_vec: [TaskID; 16],
    pub complex_handle_raw: ComplexHandleRaw,
    pub edge_type: EdgeType,
    pub callback_id: EdgeCallbackID,
    pub vpi_value: t_vpi_value,
    pub vpi_time: t_vpi_time,
}
#[inline(always)]
unsafe fn do_register_edge_callback_chunk_16(complex_handle_raw: &ComplexHandleRaw, task_id_1: &TaskID,task_id_2: &TaskID,task_id_3: &TaskID,task_id_4: &TaskID,task_id_5: &TaskID,task_id_6: &TaskID,task_id_7: &TaskID,task_id_8: &TaskID,task_id_9: &TaskID,task_id_10: &TaskID,task_id_11: &TaskID,task_id_12: &TaskID,task_id_13: &TaskID,task_id_14: &TaskID,task_id_15: &TaskID,task_id_16: &TaskID, edge_type: &EdgeType, edge_cb_id: &EdgeCallbackID) -> vpiHandle  {
    let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

    let user_data = Box::into_raw(Box::new(EdgeCbDataChunk_16 {
        task_id_vec: [*task_id_1,*task_id_2,*task_id_3,*task_id_4,*task_id_5,*task_id_6,*task_id_7,*task_id_8,*task_id_9,*task_id_10,*task_id_11,*task_id_12,*task_id_13,*task_id_14,*task_id_15,*task_id_16],
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
        cb_rtn: Some(edge_callback_chunk_16),
        time: unsafe { &mut (*user_data).vpi_time },
        obj: complex_handle.vpi_handle,
        user_data: user_data as *mut _,
        value: unsafe { &mut (*user_data).vpi_value },
        index: 0,
    };

    unsafe { vpi_register_cb(&mut cb_data) }
}
unsafe extern "C" fn edge_callback_chunk_16(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let cb_data = unsafe { cb_data.read() };
    let new_value = EdgeValue::try_from(unsafe { cb_data.value.read().value.integer } as u8).unwrap();
    let user_data: &EdgeCbDataChunk_16 = unsafe { &*(cb_data.user_data as *const EdgeCbDataChunk_16) };
    let expected_edge_value = edge_type_to_value(&user_data.edge_type);

    if new_value == expected_edge_value || expected_edge_value == EdgeValue::DontCare
    {
        let env = get_verilua_env();

        #[cfg(feature = "acc_time")]
        let s = std::time::Instant::now();

        if let Err(e) = env
            .lua_sim_event_chunk_16
            .as_ref()
            .unwrap()
            .call::<()>((user_data.task_id_vec[0],user_data.task_id_vec[1],user_data.task_id_vec[2],user_data.task_id_vec[3],user_data.task_id_vec[4],user_data.task_id_vec[5],user_data.task_id_vec[6],user_data.task_id_vec[7],user_data.task_id_vec[8],user_data.task_id_vec[9],user_data.task_id_vec[10],user_data.task_id_vec[11],user_data.task_id_vec[12],user_data.task_id_vec[13],user_data.task_id_vec[14],user_data.task_id_vec[15]))
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
            let mut finished_tasks: smallvec::SmallVec<[TaskID; 16]> = smallvec::SmallVec::new();

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
                // log::trace!("chunk_task[16] any_task_finished {:?}", user_data.task_id_vec);

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


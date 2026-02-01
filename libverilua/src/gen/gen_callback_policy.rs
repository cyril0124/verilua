{        for (complex_handle, task_id_vec) in &env.pending_posedge_cb_map {
            let mut idx = 0;
            let task_id_vec_size = task_id_vec.len();

            while idx < task_id_vec_size {
                let chunk_end = usize::min(idx + 16, task_id_vec_size);
                let chunk = &task_id_vec[idx..chunk_end];
                let edge_cb_id = env.edge_cb_idpool.alloc_id();

                let cb_hdl = unsafe {
                    match chunk.len() {
                    1 => do_register_edge_callback_chunk_1(complex_handle, &chunk[0], &EdgeType::Posedge, &edge_cb_id),
                    2 => do_register_edge_callback_chunk_2(complex_handle, &chunk[0],&chunk[1], &EdgeType::Posedge, &edge_cb_id),
                    3 => do_register_edge_callback_chunk_3(complex_handle, &chunk[0],&chunk[1],&chunk[2], &EdgeType::Posedge, &edge_cb_id),
                    4 => do_register_edge_callback_chunk_4(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3], &EdgeType::Posedge, &edge_cb_id),
                    5 => do_register_edge_callback_chunk_5(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4], &EdgeType::Posedge, &edge_cb_id),
                    6 => do_register_edge_callback_chunk_6(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5], &EdgeType::Posedge, &edge_cb_id),
                    7 => do_register_edge_callback_chunk_7(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6], &EdgeType::Posedge, &edge_cb_id),
                    8 => do_register_edge_callback_chunk_8(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7], &EdgeType::Posedge, &edge_cb_id),
                    9 => do_register_edge_callback_chunk_9(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8], &EdgeType::Posedge, &edge_cb_id),
                    10 => do_register_edge_callback_chunk_10(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9], &EdgeType::Posedge, &edge_cb_id),
                    11 => do_register_edge_callback_chunk_11(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10], &EdgeType::Posedge, &edge_cb_id),
                    12 => do_register_edge_callback_chunk_12(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11], &EdgeType::Posedge, &edge_cb_id),
                    13 => do_register_edge_callback_chunk_13(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12], &EdgeType::Posedge, &edge_cb_id),
                    14 => do_register_edge_callback_chunk_14(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13], &EdgeType::Posedge, &edge_cb_id),
                    15 => do_register_edge_callback_chunk_15(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13],&chunk[14], &EdgeType::Posedge, &edge_cb_id),
                    16 => do_register_edge_callback_chunk_16(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13],&chunk[14],&chunk[15], &EdgeType::Posedge, &edge_cb_id),
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

        for (complex_handle, task_id_vec) in &env.pending_negedge_cb_map {
            let mut idx = 0;
            let task_id_vec_size = task_id_vec.len();

            while idx < task_id_vec_size {
                let chunk_end = usize::min(idx + 16, task_id_vec_size);
                let chunk = &task_id_vec[idx..chunk_end];
                let edge_cb_id = env.edge_cb_idpool.alloc_id();

                let cb_hdl = unsafe {
                    match chunk.len() {
                    1 => do_register_edge_callback_chunk_1(complex_handle, &chunk[0], &EdgeType::Negedge, &edge_cb_id),
                    2 => do_register_edge_callback_chunk_2(complex_handle, &chunk[0],&chunk[1], &EdgeType::Negedge, &edge_cb_id),
                    3 => do_register_edge_callback_chunk_3(complex_handle, &chunk[0],&chunk[1],&chunk[2], &EdgeType::Negedge, &edge_cb_id),
                    4 => do_register_edge_callback_chunk_4(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3], &EdgeType::Negedge, &edge_cb_id),
                    5 => do_register_edge_callback_chunk_5(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4], &EdgeType::Negedge, &edge_cb_id),
                    6 => do_register_edge_callback_chunk_6(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5], &EdgeType::Negedge, &edge_cb_id),
                    7 => do_register_edge_callback_chunk_7(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6], &EdgeType::Negedge, &edge_cb_id),
                    8 => do_register_edge_callback_chunk_8(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7], &EdgeType::Negedge, &edge_cb_id),
                    9 => do_register_edge_callback_chunk_9(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8], &EdgeType::Negedge, &edge_cb_id),
                    10 => do_register_edge_callback_chunk_10(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9], &EdgeType::Negedge, &edge_cb_id),
                    11 => do_register_edge_callback_chunk_11(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10], &EdgeType::Negedge, &edge_cb_id),
                    12 => do_register_edge_callback_chunk_12(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11], &EdgeType::Negedge, &edge_cb_id),
                    13 => do_register_edge_callback_chunk_13(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12], &EdgeType::Negedge, &edge_cb_id),
                    14 => do_register_edge_callback_chunk_14(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13], &EdgeType::Negedge, &edge_cb_id),
                    15 => do_register_edge_callback_chunk_15(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13],&chunk[14], &EdgeType::Negedge, &edge_cb_id),
                    16 => do_register_edge_callback_chunk_16(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13],&chunk[14],&chunk[15], &EdgeType::Negedge, &edge_cb_id),
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

        for (complex_handle, task_id_vec) in &env.pending_edge_cb_map {
            let mut idx = 0;
            let task_id_vec_size = task_id_vec.len();

            while idx < task_id_vec_size {
                let chunk_end = usize::min(idx + 16, task_id_vec_size);
                let chunk = &task_id_vec[idx..chunk_end];
                let edge_cb_id = env.edge_cb_idpool.alloc_id();

                let cb_hdl = unsafe {
                    match chunk.len() {
                    1 => do_register_edge_callback_chunk_1(complex_handle, &chunk[0], &EdgeType::Edge, &edge_cb_id),
                    2 => do_register_edge_callback_chunk_2(complex_handle, &chunk[0],&chunk[1], &EdgeType::Edge, &edge_cb_id),
                    3 => do_register_edge_callback_chunk_3(complex_handle, &chunk[0],&chunk[1],&chunk[2], &EdgeType::Edge, &edge_cb_id),
                    4 => do_register_edge_callback_chunk_4(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3], &EdgeType::Edge, &edge_cb_id),
                    5 => do_register_edge_callback_chunk_5(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4], &EdgeType::Edge, &edge_cb_id),
                    6 => do_register_edge_callback_chunk_6(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5], &EdgeType::Edge, &edge_cb_id),
                    7 => do_register_edge_callback_chunk_7(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6], &EdgeType::Edge, &edge_cb_id),
                    8 => do_register_edge_callback_chunk_8(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7], &EdgeType::Edge, &edge_cb_id),
                    9 => do_register_edge_callback_chunk_9(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8], &EdgeType::Edge, &edge_cb_id),
                    10 => do_register_edge_callback_chunk_10(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9], &EdgeType::Edge, &edge_cb_id),
                    11 => do_register_edge_callback_chunk_11(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10], &EdgeType::Edge, &edge_cb_id),
                    12 => do_register_edge_callback_chunk_12(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11], &EdgeType::Edge, &edge_cb_id),
                    13 => do_register_edge_callback_chunk_13(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12], &EdgeType::Edge, &edge_cb_id),
                    14 => do_register_edge_callback_chunk_14(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13], &EdgeType::Edge, &edge_cb_id),
                    15 => do_register_edge_callback_chunk_15(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13],&chunk[14], &EdgeType::Edge, &edge_cb_id),
                    16 => do_register_edge_callback_chunk_16(complex_handle, &chunk[0],&chunk[1],&chunk[2],&chunk[3],&chunk[4],&chunk[5],&chunk[6],&chunk[7],&chunk[8],&chunk[9],&chunk[10],&chunk[11],&chunk[12],&chunk[13],&chunk[14],&chunk[15], &EdgeType::Edge, &edge_cb_id),
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

}
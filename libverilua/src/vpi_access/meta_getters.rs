use super::*;
use std::collections::HashSet;

type HierarchyItemCallback = unsafe extern "C" fn(*const c_char, *const c_char, PLI_INT32);

impl VeriluaEnv {
    pub fn vpiml_iterate_vpi_type(&mut self, module_name: *mut c_char, vpi_type: u32) {
        let ref_module_handle = self.complex_handle_by_name(module_name, std::ptr::null_mut());
        let chdl = ComplexHandle::from_raw(&ref_module_handle);
        let iter = unsafe { vpi_iterate(vpi_type as _, chdl.vpi_handle as vpiHandle) };

        println!(
            "[vpiml_iterate_vpi_type] start iterate on module_name => {} type => {}",
            unsafe { utils::c_char_to_str(module_name) },
            match vpi_type {
                vpiNet => "vpiNet",
                vpiReg => "vpiReg",
                vpiMemory => "vpiMemory",
                _ => "unknown",
            }
        );

        let mut hdl: vpiHandle;
        let mut count = 0;
        loop {
            hdl = unsafe { vpi_scan(iter) };
            if hdl.is_null() {
                break;
            }
            let name = unsafe { vpi_get_str(vpiName as _, hdl) };
            let typ = unsafe { vpi_get_str(vpiType as _, hdl) };

            println!(
                "[{count}] name => {} type => {}",
                unsafe { utils::c_char_to_str(name) },
                unsafe { utils::c_char_to_str(typ) }
            );
            count += 1;
        }

        if count == 0 {
            println!("[vpiml_iterate_vpi_type] No objects found")
        }
    }
}

fn vpiml_collect_hierarchy_recursive(
    module: vpiHandle,
    parent_path: &str,
    level: PLI_INT32,
    max_level: PLI_INT32,
    cb: HierarchyItemCallback,
) {
    if max_level != 0 && level > max_level {
        return;
    }

    let iter = unsafe { vpi_iterate(vpiModule as _, module) };
    if iter.is_null() {
        return;
    }

    loop {
        let child = unsafe { vpi_scan(iter) };
        if child.is_null() {
            break;
        }

        let name_ptr = unsafe { vpi_get_str(vpiName as _, child) } as *const c_char;
        let Some(name) = (unsafe { utils::c_char_to_str_opt(name_ptr) }) else {
            continue;
        };

        let full_path = if parent_path.is_empty() {
            name.to_string()
        } else {
            format!("{parent_path}.{name}")
        };

        let Ok(full_path_cstr) = CString::new(full_path.as_str()) else {
            continue;
        };
        unsafe { cb(full_path_cstr.as_ptr(), name_ptr, level) };

        // Collect leaf objects under this module node (e.g. nets/regs/memory).
        // Some backends may not support these iterate types; null iterators are skipped.
        if max_level == 0 || level < max_level {
            let mut visited_name_set = HashSet::new();
            for object_type in [vpiNet, vpiReg, vpiMemory] {
                let obj_iter = unsafe { vpi_iterate(object_type as _, child) };
                if obj_iter.is_null() {
                    continue;
                }

                loop {
                    let obj = unsafe { vpi_scan(obj_iter) };
                    if obj.is_null() {
                        break;
                    }

                    let obj_name_ptr = unsafe { vpi_get_str(vpiName as _, obj) } as *const c_char;
                    let Some(obj_name) = (unsafe { utils::c_char_to_str_opt(obj_name_ptr) }) else {
                        continue;
                    };
                    if !visited_name_set.insert(obj_name.to_string()) {
                        continue;
                    }

                    let obj_full_path = if obj_name.contains('.') {
                        obj_name.to_string()
                    } else {
                        format!("{full_path}.{obj_name}")
                    };
                    let Ok(obj_full_path_cstr) = CString::new(obj_full_path.as_str()) else {
                        continue;
                    };
                    unsafe { cb(obj_full_path_cstr.as_ptr(), obj_name_ptr, level + 1) };
                }
            }
        }

        vpiml_collect_hierarchy_recursive(child, full_path.as_str(), level + 1, max_level, cb);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_iterate_vpi_type(
    env: *mut c_void,
    module_name: *mut c_char,
    vpi_type: u32,
) {
    let env = VeriluaEnv::from_void_ptr(env);
    env.vpiml_iterate_vpi_type(module_name, vpi_type)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_signal_width(
    complex_handle_raw: ComplexHandleRaw,
) -> c_longlong {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    complex_handle.width as _
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_hdl_type(complex_handle_raw: ComplexHandleRaw) -> *const c_char {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    unsafe { vpi_get_str(vpiType as _, complex_handle.vpi_handle as vpiHandle) as _ }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_top_module() -> *const c_char {
    let iter: vpiHandle = unsafe { vpi_iterate(vpiModule as _, std::ptr::null_mut()) };
    assert!(!iter.is_null(), "No module exist...");

    let top_module: vpiHandle = unsafe { vpi_scan(iter) };
    assert!(!top_module.is_null(), "Canot find top module...");

    let top_module_name = unsafe { vpi_get_str(vpiName as _, top_module) };

    if std::env::var("DUT_TOP").is_err() {
        unsafe { std::env::set_var("DUT_TOP", utils::c_char_to_str(top_module_name)) };
    }

    top_module_name as _
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_collect_hierarchy(
    max_level: PLI_INT32,
    cb: Option<HierarchyItemCallback>,
) {
    let Some(cb) = cb else {
        return;
    };
    vpiml_collect_hierarchy_recursive(std::ptr::null_mut(), "", 0, max_level, cb);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_simulator_auto() -> *const c_char {
    utils::get_simulator_auto()
}

/// Get simulation time precision as power of 10 (e.g., -9 for ns, -12 for ps)
/// This value is cached during initialization for performance.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_time_precision() -> i32 {
    unsafe { vpi_get(vpiTimePrecision as _, std::ptr::null_mut()) }
}

/// Get current simulation time as 64-bit value
/// The time is in simulation steps (based on time precision)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_sim_time() -> u64 {
    let mut vpi_time = t_vpi_time {
        type_: vpiSimTime as _,
        high: 0,
        low: 0,
        real: 0.0,
    };

    unsafe { vpi_get_time(std::ptr::null_mut(), &mut vpi_time) };

    ((vpi_time.high as u64) << 32) | (vpi_time.low as u64)
}

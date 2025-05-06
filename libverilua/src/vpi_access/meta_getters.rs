use super::*;

impl VeriluaEnv {
    pub fn vpiml_iterate_vpi_type(&mut self, module_name: *mut c_char, vpi_type: u32) {
        let ref_module_handle =
            unsafe { self.complex_handle_by_name(module_name, std::ptr::null_mut()) };
        let chdl = ComplexHandle::from_raw(&ref_module_handle);
        let iter = unsafe { vpi_iterate(vpi_type as _, chdl.vpi_handle as vpiHandle) };

        println!(
            "[vpiml_iterate_vpi_type] start iterate on module_name => {} type => {}",
            unsafe { CStr::from_ptr(module_name).to_str().unwrap() },
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
                unsafe { CStr::from_ptr(name).to_str().unwrap() },
                unsafe { CStr::from_ptr(typ).to_str().unwrap() }
            );
            count += 1;
        }

        if count == 0 {
            println!("[vpiml_iterate_vpi_type] No objects found")
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_iterate_vpi_type(
    env: *mut libc::c_void,
    module_name: *mut c_char,
    vpi_type: u32,
) {
    let env = unsafe { VeriluaEnv::from_void_ptr(env) };
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
pub unsafe extern "C" fn vpiml_get_top_module() -> *const libc::c_char {
    let iter: vpiHandle = unsafe { vpi_iterate(vpiModule as _, std::ptr::null_mut()) };
    assert!(!iter.is_null(), "No module exist...");

    let top_module: vpiHandle = unsafe { vpi_scan(iter) };
    assert!(!top_module.is_null(), "Canot find top module...");

    let top_module_name = unsafe { vpi_get_str(vpiName as _, top_module) };

    if std::env::var("DUT_TOP").is_err() {
        unsafe { std::env::set_var("DUT_TOP", CStr::from_ptr(top_module_name).to_str().unwrap()) };
    }

    top_module_name as _
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_simulator_auto() -> *const libc::c_char {
    return utils::get_simulator_auto();
}

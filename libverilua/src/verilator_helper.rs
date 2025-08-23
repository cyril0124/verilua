use libc::{c_char, c_int, c_void};
use std::cell::UnsafeCell;
use std::ffi::CStr;

use crate::verilua_env::get_verilua_env;

type VerilatorFunc = Option<unsafe extern "C" fn(*mut c_void)>;

thread_local! {
    static VERILATOR_SIMULATION_INITIALIZE_TRACE: UnsafeCell<VerilatorFunc> = UnsafeCell::new(None);
    static VERILATOR_SIMULATION_ENABLE_TRACE: UnsafeCell<VerilatorFunc> = UnsafeCell::new(None);
    static VERILATOR_SIMULATION_DISABLE_TRACE: UnsafeCell<VerilatorFunc> = UnsafeCell::new(None);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_alloc_verilator_func(func: VerilatorFunc, name: *const c_char) {
    let name = unsafe { CStr::from_ptr(name) }
        .to_string_lossy()
        .into_owned();

    #[cfg(feature = "debug")]
    log::debug!("verilua_alloc_verilator_func: {}", name);

    match name.as_str() {
        "simulation_initializeTrace" => {
            VERILATOR_SIMULATION_INITIALIZE_TRACE.with(|f| unsafe { *f.get() = func })
        }
        "simulation_enableTrace" => {
            VERILATOR_SIMULATION_ENABLE_TRACE.with(|f| unsafe { *f.get() = func })
        }
        "simulation_disableTrace" => {
            VERILATOR_SIMULATION_DISABLE_TRACE.with(|f| unsafe { *f.get() = func })
        }
        _ => {}
    };
}

#[unsafe(no_mangle)]
pub extern "C" fn verilator_simulation_initializeTrace(trace_file_path: *const c_char) {
    #[cfg(feature = "debug")]
    log::debug!("verilator_simulation_initializeTrace: {}", unsafe {
        CStr::from_ptr(trace_file_path).to_str().unwrap()
    });

    VERILATOR_SIMULATION_INITIALIZE_TRACE
        .with(|f| unsafe { (*f.get()).unwrap()(trace_file_path as _) });
}

#[unsafe(no_mangle)]
pub extern "C" fn verilator_simulation_enableTrace() {
    #[cfg(feature = "debug")]
    log::debug!("verilator_simulation_enableTrace");

    VERILATOR_SIMULATION_ENABLE_TRACE
        .with(|f| unsafe { (*f.get()).unwrap()(std::ptr::null_mut()) });
}

#[unsafe(no_mangle)]
pub extern "C" fn verilator_simulation_disableTrace() {
    #[cfg(feature = "debug")]
    log::debug!("verilator_simulation_disableTrace");

    VERILATOR_SIMULATION_DISABLE_TRACE
        .with(|f| unsafe { (*f.get()).unwrap()(std::ptr::null_mut()) });
}


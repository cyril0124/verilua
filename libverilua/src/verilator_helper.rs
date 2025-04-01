use libc::{c_char, c_int, c_void};
use std::cell::UnsafeCell;
use std::ffi::CStr;

use crate::verilua_env::get_verilua_env;

type VerilatorFunc = Option<unsafe extern "C" fn(*mut c_void)>;

thread_local! {
    static VERILATOR_NEXT_SIM_STEP: UnsafeCell<VerilatorFunc> = UnsafeCell::new(None);
    static VERILATOR_GET_MODE: UnsafeCell<VerilatorFunc> = UnsafeCell::new(None);
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
        "next_sim_step" => VERILATOR_NEXT_SIM_STEP.with(|f| unsafe { *f.get() = func }),
        "get_mode" => VERILATOR_GET_MODE.with(|f| unsafe { *f.get() = func }),
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
pub unsafe extern "C" fn verilator_next_sim_step() {
    #[cfg(feature = "debug")]
    log::trace!("verilator_next_sim_step...");

    VERILATOR_NEXT_SIM_STEP.with(|f| {
        unsafe { (*f.get()).unwrap()(std::ptr::null_mut()) };
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilator_get_mode() -> c_int {
    let mut mode: c_int = 0;

    VERILATOR_GET_MODE.with(|f| unsafe { (*f.get()).unwrap()(&mut mode as *mut _ as *mut c_void) });

    #[cfg(feature = "debug")]
    log::debug!(
        "verilator_get_mode: {}",
        match mode {
            1 => "Normal",
            2 => "Step",
            3 => "Dominant",
            _ => panic!("Unknown mode: {mode}"),
        }
    );

    mode
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_schedule_loop() {
    #[cfg(feature = "debug")]
    log::debug!("enter verilua_schedule_loop()");

    let env = get_verilua_env();
    if let Err(e) = env
        .lua
        .globals()
        .get::<mlua::prelude::LuaFunction>("verilua_schedule_loop")
        .expect("Failed to load verilua_schedule_loop")
        .call::<()>(())
    {
        panic!("Error calling verilua_schedule_loop: {e}");
    };

    unreachable!()
}

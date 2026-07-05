use libc::{c_char, c_void};
use std::cell::UnsafeCell;

use crate::utils;

type VerilatorFunc = Option<unsafe extern "C" fn(*mut c_void)>;

thread_local! {
    static VERILATOR_SIMULATION_INITIALIZE_TRACE: UnsafeCell<VerilatorFunc> = UnsafeCell::new(None);
    static VERILATOR_SIMULATION_ENABLE_TRACE: UnsafeCell<VerilatorFunc> = UnsafeCell::new(None);
    static VERILATOR_SIMULATION_DISABLE_TRACE: UnsafeCell<VerilatorFunc> = UnsafeCell::new(None);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_alloc_verilator_func(func: VerilatorFunc, name: *const c_char) {
    let name = unsafe { utils::c_char_to_str(name) }.to_owned();

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
        utils::c_char_to_str(trace_file_path)
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

/// This function is called from `verilator_main.cpp` when `verilator_inner_step_callback` is enabled.
/// It is a performance optimization to save the time of registering the cbNextSimTime callback.
#[unsafe(no_mangle)]
pub extern "C" fn verilator_next_sim_time_callback() {
    if cfg!(feature = "verilator_inner_step_callback") {
        unsafe {
            crate::vpi_callback::libverilua_next_sim_time_cb(std::ptr::null_mut());
        }
    } else {
        panic!("`feature = \"verilator_inner_step_callback\"` is not enabled");
    }
}

/// Returns true while Lua-side posted writes (`set()`) queued during the
/// current ReadWrite phase are still pending.
///
/// Called from the `verilator_main.cpp` ReadWrite loop condition. Verilator's
/// loop only continues while `evalNeeded()` is set, i.e. while *the simulator*
/// has seen a vpi_put_value. Writes posted from a coroutine that was resumed
/// inside a cbReadWriteSynch callback live in libverilua's own queue and are
/// invisible to `evalNeeded()`, so without this bridge their flush (and any
/// await_rw() wakeup deferred behind it) would slip to the next timestep.
/// This mirrors what `doInertialPuts()` achieves for cocotb's inertial writes.
///
/// The `rw_phase_passed` guard restricts this to writes posted after the first
/// flush of the timestep: exactly those for which `do_push_hdl_put_value` has
/// re-registered a consuming cbReadWriteSynch callback. Writes queued in
/// earlier phases are consumed by the per-timestep flush callback as before,
/// keeping the loop free of livelock (pending here always implies a registered
/// callback that will drain the queue).
#[unsafe(no_mangle)]
pub extern "C" fn verilator_has_pending_put_values() -> bool {
    if cfg!(feature = "inertial_put") {
        false
    } else {
        let env = crate::verilua_env::get_verilua_env_no_init();
        env.rw_phase_passed && !env.hdl_put_value.is_empty()
    }
}

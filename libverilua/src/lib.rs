#![allow(non_upper_case_globals)]
mod complex_handle;
mod utils;
mod verilator_helper;
mod verilua_env;
mod vpi_access;
mod vpi_callback;
mod vpi_user;

pub type TaskID = u32;
pub type EdgeCallbackID = u32;

#[cfg(all(not(feature = "verilua_prebuild_bin"), not(feature = "dpi")))]
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

#[cfg(feature = "debug")]
#[static_init::constructor(0)]
extern "C" fn init_env_logger() {
    env_logger::try_init();
}

#[cfg(not(feature = "dpi"))]
#[unsafe(no_mangle)]
pub static vlog_startup_routines: [Option<unsafe extern "C" fn()>; 4] = [
    Some(vpi_callback::vpiml_register_next_sim_time_callback),
    Some(vpi_callback::vpiml_register_start_callback),
    Some(vpi_callback::vpiml_register_final_callback),
    None,
];

// In some cases you may need to call this function manually since the simulation environment may not call it automatically(e.g. Verilator).
// While in most cases you don't need to call this function manually.
#[cfg(not(feature = "dpi"))]
#[unsafe(no_mangle)]
pub extern "C" fn vlog_startup_routines_bootstrap() {
    for f in vlog_startup_routines.iter().flatten() {
        unsafe { f() };
    }
}

#[cfg(feature = "verilua_prebuild_bin")]
include!("bin/verilua_prebuild.rs");

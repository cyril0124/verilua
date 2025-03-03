#![allow(non_upper_case_globals)]

mod utils;
mod verilator_helper;
mod verilua_env;
mod vpi_access;
mod vpi_callback;
mod vpi_user;

use hashbrown::{HashMap, HashSet};
use libc::{c_char, c_longlong};
use mlua::prelude::*;
use std::ffi::CStr;
use vpi_user::*;

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

#[static_init::constructor(0)]
extern "C" fn init_env_logger() {
    #[cfg(feature = "debug")]
    env_logger::init();
}

#[unsafe(no_mangle)]
pub static vlog_startup_routines: [Option<unsafe extern "C" fn()>; 4] = [
    Some(vpi_callback::register_next_sim_time_callback),
    Some(vpi_callback::register_start_callback),
    Some(vpi_callback::register_final_callback),
    None,
];

// In some cases you may need to call this function manually since the simulation environment may not call it automatically(e.g. Verilator).
// While in most cases you don't need to call this function manually.
#[unsafe(no_mangle)]
pub extern "C" fn vlog_startup_routines_bootstrap() {
    for f in vlog_startup_routines.iter().flatten() {
        unsafe { f() };
    }
}

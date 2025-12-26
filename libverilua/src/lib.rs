//! # libverilua - VPI/VPIML Core Library for Verilua
//!
//! This library provides the core VPI (Verilog Procedural Interface) implementation
//! for Verilua, enabling Lua-based testbenches to interact with HDL simulators.
//!
//! ## Architecture Overview
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────────────┐
//! │                           Verilua Architecture                          │
//! ├─────────────────────────────────────────────────────────────────────────┤
//! │                                                                         │
//! │  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────────┐   │
//! │  │  Lua Script │────>│ libverilua   │────>│   HDL Simulator (VPI)   │   │
//! │  │ (Testbench) │<────│ (Rust/FFI)   │<────│ (Verilator/VCS/etc.)    │   │
//! │  └─────────────┘     └──────────────┘     └─────────────────────────┘   │
//! │                              │                                          │
//! │                              ▼                                          │
//! │                    ┌──────────────────┐                                 │
//! │                    │   VeriluaEnv     │                                 │
//! │                    │  (Global State)  │                                 │
//! │                    └──────────────────┘                                 │
//! │                              │                                          │
//! │         ┌────────────────────┼────────────────────┐                     │
//! │         ▼                    ▼                    ▼                     │
//! │  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐               │
//! │  │ VPI Access  │    │ VPI Callback │    │ Complex Handle│               │
//! │  │ (get/set)   │    │ (edge/time)  │    │   (caching)   │               │
//! │  └─────────────┘    └──────────────┘    └───────────────┘               │
//! │                                                                         │
//! └─────────────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Module Overview
//!
//! - `verilua_env`: Global environment management and Lua integration
//! - `vpi_access`: Signal value read/write operations
//! - `vpi_callback`: Event callback registration (edge, time, etc.)
//! - `complex_handle`: Enhanced VPI handle with caching and metadata
//! - `utils`: FFI utilities and helper functions
//! - `verilator_helper`: Verilator-specific workarounds and helpers
//!

#![allow(non_upper_case_globals)]
mod complex_handle;
mod utils;
mod verilator_helper;
mod verilua_env;
mod vpi_access;
mod vpi_callback;
mod vpi_user;

/// Task identifier type - used to uniquely identify scheduled Lua tasks
pub type TaskID = u32;

/// Edge callback identifier - used to manage VPI edge callbacks
pub type EdgeCallbackID = u32;

// Use mimalloc as global allocator for better performance (except in DPI mode)
#[cfg(all(not(feature = "dpi")))]
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

// Initialize env_logger at static construction time
#[static_init::constructor(0)]
extern "C" fn init_env_logger() {
    let _ = env_logger::try_init();
}

/// Promotes LuaJIT symbols (e.g., lua_checkstack) to the global namespace (RTLD_GLOBAL).
/// This ensures that dynamically loaded Lua C modules (like lsqlite3) can resolve
/// Lua API symbols, even if the host simulator loaded libverilua/libluajit with RTLD_LOCAL.
/// Note: This method is used by Xcelium simulator.
#[unsafe(no_mangle)]
pub extern "C" fn promote_luajit_symbols() {
    #[cfg(feature = "promote_luajit_global")]
    unsafe {
        // Possible filenames for the LuaJIT shared library.
        // Adjust if your specific environment uses a different name.
        let possible_names = [
            "libluajit-5.1.so", // Symlink often used during compilation
        ];

        let mut promoted = false;

        for lib_name in possible_names {
            let c_lib_name = std::ffi::CString::new(lib_name).expect("CString conversion failed");

            // RTLD_LAZY   (0x00001): Relocations are performed at an implementation-dependent time.
            // RTLD_GLOBAL (0x00100): The symbols defined by this library will be made available for symbol resolution of subsequently loaded libraries.
            // RTLD_NOLOAD (0x00004): Do not load the library. This can be used to test if the library is already resident and promote its flags.
            let flags_noload = libc::RTLD_LAZY | libc::RTLD_GLOBAL | libc::RTLD_NOLOAD;

            // Attempt 1: Try to modify the existing handle without reloading
            let handle = libc::dlopen(c_lib_name.as_ptr(), flags_noload);

            if !handle.is_null() {
                log::info!(
                    "Successfully promoted LuaJIT symbols ({}) to GLOBAL scope (via RTLD_NOLOAD).",
                    lib_name
                );
                promoted = true;
                break;
            }

            // Attempt 2: If the library wasn't found or NOLOAD failed, try a standard dlopen with GLOBAL.
            // This increments the refcount and applies the GLOBAL flag.
            let flags_force = libc::RTLD_LAZY | libc::RTLD_GLOBAL;
            let handle_force = libc::dlopen(c_lib_name.as_ptr(), flags_force);

            if !handle_force.is_null() {
                log::info!(
                    "Successfully loaded and promoted LuaJIT symbols ({}) to GLOBAL scope.",
                    lib_name
                );
                promoted = true;
                break;
            }
        }

        if !promoted {
            log::warn!(
                "Failed to promote LuaJIT symbols to GLOBAL scope. Modules like 'lsqlite3' may fail to load due to missing symbols."
            );
        }
    }
}

/// VPI startup routines registered with the simulator.
///
/// These callbacks are invoked by the simulator during initialization:
/// 1. `bootstrap_register_next_sim_time_callback`: Sets up time advancement callbacks
/// 2. `bootstrap_register_start_callback`: Initializes Verilua when simulation starts
/// 3. `bootstrap_register_final_callback`: Cleanup when simulation ends
#[cfg(not(feature = "dpi"))]
#[unsafe(no_mangle)]
pub static vlog_startup_routines: [Option<unsafe extern "C" fn()>; 5] = [
    Some(promote_luajit_symbols),
    Some(vpi_callback::bootstrap_register_next_sim_time_callback),
    Some(vpi_callback::bootstrap_register_start_callback),
    Some(vpi_callback::bootstrap_register_final_callback),
    None,
];

/// Manual bootstrap function for simulators that don't auto-invoke VPI startup routines.
///
/// Some simulators (e.g., Verilator) require explicit initialization. Call this function
/// at the beginning of simulation if the simulator doesn't automatically invoke
/// the VPI startup routines.
#[cfg(not(feature = "dpi"))]
#[unsafe(no_mangle)]
pub extern "C" fn vlog_startup_routines_bootstrap() {
    for f in vlog_startup_routines.iter().flatten() {
        unsafe { f() };
    }
}

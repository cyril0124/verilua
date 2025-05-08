use hashbrown::{HashMap, HashSet};
use mlua::prelude::*;
use std::cell::UnsafeCell;
use std::ffi::{CStr, CString};
use std::fmt::{self, Debug};
use std::time::{Duration, Instant};

use crate::complex_handle::{ComplexHandle, ComplexHandleRaw};
use crate::vpi_access;
use crate::vpi_callback::{self, CallbackInfo};
use crate::vpi_user::*;
use crate::{EdgeCallbackID, TaskID};

// Both `get_verilua_env()` and `get_verilua_env_no_init()` share the same `VERILUA_ENV`.
// `get_verilua_env()` will initialize the `VERILUA_ENV` if it is not initialized.
static mut VERILUA_ENV: Option<UnsafeCell<VeriluaEnv>> = None;

#[inline(always)]
pub fn get_verilua_env() -> &'static mut VeriluaEnv {
    unsafe {
        match VERILUA_ENV {
            Some(ref mut env_cell) => &mut *env_cell.get(),
            None => {
                VERILUA_ENV = Some(UnsafeCell::new(VeriluaEnv::default()));

                // In some case where user does not call `verilua_init()`, we call it here.
                // Initialize verilua_env here can ensure the thread safety of `get_verilua_env()`.
                get_verilua_env().initialize();

                get_verilua_env()
            }
        }
    }
}

#[inline(always)]
pub fn get_verilua_env_no_init() -> &'static mut VeriluaEnv {
    unsafe {
        match VERILUA_ENV {
            Some(ref mut env_cell) => &mut *env_cell.get(),
            None => {
                VERILUA_ENV = Some(UnsafeCell::new(VeriluaEnv::default()));
                get_verilua_env_no_init()
            }
        }
    }
}

pub struct IDPool {
    available_ids: HashSet<EdgeCallbackID>,
}

impl Debug for IDPool {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "IDPool(...)")
    }
}

impl IDPool {
    pub fn new(size: u64) -> Self {
        let available_ids = (0..size as EdgeCallbackID).collect::<HashSet<EdgeCallbackID>>();
        IDPool { available_ids }
    }

    #[inline(always)]
    pub fn alloc_id(&mut self) -> EdgeCallbackID {
        let id = *self
            .available_ids
            .iter()
            .next()
            .expect("No more IDs available");
        self.available_ids.remove(&id);

        id
    }

    #[inline(always)]
    pub fn release_id(&mut self, id: EdgeCallbackID) {
        assert_eq!(
            self.available_ids.insert(id),
            true,
            "id {} is already available",
            id
        );
    }
}

include!("./gen/gen_verilua_env_struct.rs");

impl Default for VeriluaEnv {
    fn default() -> Self {
        let lua = unsafe { Lua::unsafe_new() };
        let env = include!("./gen/gen_verilua_env_init.rs");

        env
    }
}

impl Drop for VeriluaEnv {
    fn drop(&mut self) {
        log::debug!("VeriluaEnv::drop()");
        self.finalize();
    }
}

impl VeriluaEnv {
    #[inline(always)]
    pub fn from_void_ptr(ptr: *mut libc::c_void) -> &'static mut Self {
        unsafe { &mut *(ptr as *mut Self) }
    }

    #[inline(always)]
    pub fn from_complex_handle_raw(complex_handle_raw: ComplexHandleRaw) -> &'static mut Self {
        let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
        unsafe { VeriluaEnv::from_void_ptr(complex_handle.env) }
    }

    #[inline(always)]
    pub fn as_void_ptr(&mut self) -> *mut libc::c_void {
        self as *mut _ as *mut libc::c_void
    }

    pub fn initialize(&mut self) {
        log::debug!("VeriluaEnv::initialize() start",);

        if self.initialized {
            return;
        } else {
            self.initialized = true;
        }

        if !self.has_final_cb {
            #[cfg(feature = "dpi")]
            unsafe {
                vpi_callback::vpiml_register_final_callback(self.as_void_ptr())
            };

            #[cfg(not(feature = "dpi"))]
            unsafe {
                vpi_callback::vpiml_register_final_callback()
            };
        }

        if !self.has_next_sim_time_cb {
            unsafe { vpi_callback::vpiml_register_next_sim_time_callback() };
        }

        let lua_dofile: LuaFunction = self.lua.globals().get("dofile").unwrap();

        let verilua_home = std::env::var("VERILUA_HOME").expect("VERILUA_HOME not set");

        if cfg!(feature = "iverilog") {
            self.resolve_x_as_zero =
                std::env::var("VL_RESOLVE_X_AS_ZERO").map_or(true, |v| v == "1" || v == "true");
        }

        // Make `verilua_env available in lua
        self.lua.globals().set(
            "GLOBAL_VERILUA_ENV",
            mlua::Value::LightUserData(mlua::LightUserData(self.as_void_ptr())),
        );

        let init_file = verilua_home + "/src/lua/verilua/init.lua";
        if let Err(e) = lua_dofile.call::<()>(init_file) {
            panic!("Failed to load init.lua: {e}");
        };

        if std::env::var("DUT_TOP").is_err() {
            unsafe {
                let dut_top = CStr::from_ptr(vpi_access::vpiml_get_top_module())
                    .to_str()
                    .unwrap();
                std::env::set_var("DUT_TOP", dut_top);
                log::debug!("DUT_TOP is not set, set it to `{dut_top}`");
            }
        }

        let lua_script = std::env::var("LUA_SCRIPT").expect("LUA_SCRIPT not set!");
        if let Err(e) = lua_dofile.call::<()>(lua_script) {
            panic!(
                "Failed to load {} => {e}",
                std::env::var("LUA_SCRIPT").unwrap()
            );
        };

        #[cfg(feature = "verilua_prebuild_bin")]
        {
            log::debug!("[verilua_env] VL_PREBUILD is set to `1`, skip initialize");
            return;
        }

        let verilua_init: LuaFunction = self
            .lua
            .globals()
            .get("verilua_init")
            .expect("Failed to load verilua_init");
        if let Err(e) = verilua_init.call::<()>(()) {
            panic!("Failed to call verilua_init: {e}");
        };

        self.lua_sim_event = Some(
            self.lua
                .globals()
                .get("sim_event")
                .expect("Failed to load sim_event"),
        );
        self.lua_main_step = Some(
            self.lua
                .globals()
                .get("lua_main_step")
                .expect("Failed to load main_step"),
        );
        self.lua_posedge_step = Some(
            self.lua
                .globals()
                .get("lua_posedge_step")
                .expect("Failed to load posedge_step"),
        );
        self.lua_negedge_step = Some(
            self.lua
                .globals()
                .get("lua_negedge_step")
                .expect("Failed to load negedge_step"),
        );

        include!("./gen/gen_sim_event_chunk_init.rs");

        self.start_time = Instant::now();

        log::debug!("VeriluaEnv::initialize() finish");
    }

    pub fn finalize(&mut self) {
        if !self.initialized {
            log::warn!("VeriluaEnv::finalize() called before VeriluaEnv::initialize()");
            return;
        } else if self.finalized {
            log::warn!("VeriluaEnv::finalize() called twice");
            return;
        } else {
            self.finalized = true;
        }

        #[cfg(feature = "verilua_prebuild_bin")]
        {
            log::debug!("[verilua_env] VL_PREBUILD is set to `1`, skip finalize");
            return;
        }

        let finish_callback: LuaFunction = self.lua.globals().get("finish_callback").unwrap();
        if let Err(err) = finish_callback.call::<()>(()) {
            panic!("Error calling finish_callback: {err}");
        }

        let total_time = self.start_time.elapsed();

        use tabled::{
            builder::Builder,
            settings::{Alignment, Color, Panel, Shadow, Style, Width, object::Rows},
        };

        let mut builder = Builder::new();
        builder.push_record(["total_time_taken", "lua_time_taken", "lua_overhead"]);

        let mut _overhead: f64 = 0.0;
        #[cfg(feature = "acc_time")]
        {
            _overhead = (self.lua_time.as_secs_f64() / total_time.as_secs_f64()) * 100.0;
            builder.push_record([
                format!("{:.2} sec", total_time.as_secs_f64()).as_str(),
                format!("{:.2} sec", self.lua_time.as_secs_f64()).as_str(),
                format!("{_overhead:.2}%").as_str(),
            ]);
        }

        #[cfg(not(feature = "acc_time"))]
        {
            builder.push_record([
                format!("{:.2} sec", total_time.as_secs_f64()).as_str(),
                "--",
                "--",
            ]);
        }

        let mut table = builder.build();
        table
            .with(Panel::header("VERILUA STATISTIC")) // TODO: Add verilua scenario(HVL/HSE/WAL)
            .with(Alignment::center())
            .with(Shadow::new(1))
            .with(Style::modern())
            .modify(Rows::new(0..), Width::increase(25));

        #[cfg(feature = "acc_time")]
        {
            if _overhead > 50.0 {
                table.modify((2, 2), Color::FG_RED);
            } else {
                table.modify((2, 2), Color::FG_GREEN);
            }
        }

        println!("{}", table);

        if log::log_enabled!(log::Level::Trace) {
            self.hdl_cache
                .iter()
                .enumerate()
                .for_each(|(idx, (_, complex_handle))| {
                    log::trace!("[{idx}] {:?}", ComplexHandle::from_raw(complex_handle));
                });
        }
    }

    #[inline(always)]
    pub fn apply_pending_put_values(&mut self) {
        self.hdl_put_value
            .iter_mut()
            .for_each(|complex_handle_raw| {
                let complex_handle = ComplexHandle::from_raw(complex_handle_raw);

                let mut v = match complex_handle.put_value_format {
                    vpiIntVal => s_vpi_value {
                        format: vpiIntVal as _,
                        value: t_vpi_value__bindgen_ty_1 {
                            integer: complex_handle.put_value_integer as _,
                        },
                    },
                    vpiVectorVal => s_vpi_value {
                        format: vpiVectorVal as _,
                        value: t_vpi_value__bindgen_ty_1 {
                            vector: complex_handle.put_value_vectors.as_mut_ptr(),
                        },
                    },
                    vpiHexStrVal | vpiDecStrVal | vpiOctStrVal | vpiBinStrVal => s_vpi_value {
                        format: complex_handle.put_value_format as _,
                        value: t_vpi_value__bindgen_ty_1 {
                            str_: CString::new(complex_handle.put_value_str.as_str())
                                .unwrap()
                                .into_raw() as _,
                        },
                    },
                    vpiSuppressVal => s_vpi_value {
                        format: vpiSuppressVal as _,
                        value: t_vpi_value__bindgen_ty_1 {
                            integer: complex_handle.put_value_integer as _,
                        },
                    },
                    vpiScalarVal => s_vpi_value {
                        format: vpiScalarVal as _,
                        value: t_vpi_value__bindgen_ty_1 {
                            scalar: complex_handle.put_value_integer as _,
                        },
                    },
                    _ => panic!(
                        "Unsupported value format: {}",
                        complex_handle.put_value_format
                    ),
                };

                unsafe {
                    vpi_put_value(
                        complex_handle.vpi_handle,
                        &mut v as *mut _,
                        std::ptr::null_mut(),
                        complex_handle.put_value_flag.take().unwrap() as _,
                    )
                };
            });

        self.hdl_put_value.clear();
    }
}

// This is a ensurance mechanism to make sure the finalize function is called when the program
// is exiting cause in some cases the finalize function may not be called successfully.
#[cfg(all(not(feature = "dpi"), feature = "vcs"))]
#[static_init::destructor(0)]
extern "C" fn automatically_finalize_verilua_env() {
    log::trace!("automatically_finalize_verilua_env");
    get_verilua_env().finalize();
}

// ----------------------------------------------------------------------------------------------------------
//  Export functions for embeding Verilua inside other simulation environments
//  Make sure to use verilua_init() at the beginning of the simulation and use verilua_final() at the end of the simulation.
//  The verilua_main_step() should be invoked at the beginning of each simulation step.
// ----------------------------------------------------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_init() {
    // Notice:
    //      Make sure that we call `verilua_init()` / `verilua_final()` / `verilua_main_step()` / `verilua_main_step_safe()` ... in the same thread! Or it will cause some issues in multithread environment(e.g. Verilator).
    //      As an alternative solution, you can always call `verilua_main_step()` / `verilua_main_step_safe()` without calling `verilua_init()` in advance. In this case, the `verilua_init()` will be called automatically and maintain thread safety.
    get_verilua_env().initialize();
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_final() {
    get_verilua_env().finalize();
}

macro_rules! gen_verilua_step {
    ($name:ident, $field:ident, $msg:expr) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name() {
            let env = get_verilua_env();
            assert!(
                env.initialized,
                concat!($msg, " called before verilua_init()")
            );

            #[cfg(feature = "acc_time")]
            let s = Instant::now();

            if let Err(e) = env.$field.as_ref().unwrap().call::<()>(()) {
                panic!("Error calling {}: {}", stringify!($field), e);
            };

            #[cfg(feature = "acc_time")]
            {
                env.lua_time += s.elapsed();
            }

            env.apply_pending_put_values();
        }
    };
}

macro_rules! gen_verilua_step_safe {
    ($name:ident, $field:ident, $msg:expr) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name() {
            thread_local! {
                static HAS_ERROR: UnsafeCell<bool> = const { UnsafeCell::new(false) };
            }

            if HAS_ERROR.with(|has_error| unsafe { *has_error.get() }) {
                let env = get_verilua_env();
                env.finalize();

                log::warn!(concat!("[", stringify!($name), "] `has_error` is `true`! Program should be terminated! Nothing will be done in `Verilua`..."));
                return;
            }

            let env = get_verilua_env();
            assert!(env.initialized, concat!("[", stringify!($name), "] ", $msg, " called before verilua_init()"));

            #[cfg(feature = "acc_time")]
            let s = Instant::now();

            if let Err(e) = env.$field.as_ref().unwrap().call::<()>(()) {
                HAS_ERROR.with(|has_error| unsafe { *has_error.get() = true; });
                println!(concat!("[", stringify!($name), "] Error calling ", stringify!($field), ": {}"), e);
            };

            #[cfg(feature = "acc_time")]
            {
                env.lua_time += s.elapsed();
            }

            env.apply_pending_put_values();
        }
    };
}

// Execute the main_step function in a way that is safe to be called.
// If the main_step function throws an error, the error will be caught
// and the Verilua environment will be finalized.
gen_verilua_step!(verilua_main_step, lua_main_step, "verilua_main_step()");
gen_verilua_step!(
    verilua_posedge_step,
    lua_posedge_step,
    "verilua_posedge_step()"
);
gen_verilua_step!(
    verilua_negedge_step,
    lua_negedge_step,
    "verilua_negedge_step()"
);

// Same as verilua_XXX_step_safe() while error will not cause the program to crash
gen_verilua_step_safe!(
    verilua_main_step_safe,
    lua_main_step,
    "verilua_main_step_safe()"
);
gen_verilua_step_safe!(
    verilua_posedge_step_safe,
    lua_posedge_step,
    "verilua_posedge_step()"
);
gen_verilua_step_safe!(
    verilua_negedge_step_safe,
    lua_negedge_step,
    "verilua_negedge_step()"
);

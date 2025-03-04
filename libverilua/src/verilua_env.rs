// use std::collections::VecDeque;
use std::cell::UnsafeCell;
use std::fmt::{self, Debug};
use std::time::{Duration, Instant};

use std::cell::Cell;

#[cfg(not(feature = "chunk_task"))]
use crate::vpi_callback::CallbackInfo;

use super::*;

thread_local! {
    pub static VERILUA_ENV: UnsafeCell<VeriluaEnv> = UnsafeCell::new(VeriluaEnv::default());
}

#[inline(always)]
pub fn get_verilua_env() -> &'static mut VeriluaEnv {
    unsafe { VERILUA_ENV.with(|env| &mut *env.get()) }
}

pub type TaskID = u32;
pub type EdgeCallbackID = u32;
pub type ComplexHandleRaw = c_longlong;

#[repr(C)]
pub struct ComplexHandle {
    pub vpi_handle: vpiHandle,
    pub name: *mut c_char,

    #[cfg(feature = "merge_cb")]
    pub posedge_cb_count: HashMap<TaskID, u32>,
    #[cfg(feature = "merge_cb")]
    pub negedge_cb_count: HashMap<TaskID, u32>,
    #[cfg(feature = "merge_cb")]
    pub edge_cb_count: HashMap<TaskID, u32>,
}

impl ComplexHandle {
    pub fn new(vpi_handle: vpiHandle, name: *mut c_char) -> Self {
        #[cfg(feature = "merge_cb")]
        {
            Self {
                vpi_handle,
                name,
                posedge_cb_count: HashMap::new(),
                negedge_cb_count: HashMap::new(),
                edge_cb_count: HashMap::new(),
            }
        }

        #[cfg(not(feature = "merge_cb"))]
        {
            Self { vpi_handle, name }
        }
    }

    #[inline(always)]
    pub fn from_raw(raw: &ComplexHandleRaw) -> &'static mut Self {
        unsafe { &mut *(*raw as *mut Self) }
    }

    #[inline(always)]
    pub fn into_raw(self) -> ComplexHandleRaw {
        Box::into_raw(Box::new(self)) as ComplexHandleRaw
    }
}

impl Debug for ComplexHandle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        #[cfg(feature = "merge_cb")]
        {
            write!(
                f,
                "ComplexHandle({}, name: {}, posedge_cb_count: {:?}, negedge_cb_count: {:?}, edge_cb_count: {:?})",
                self.vpi_handle as c_longlong,
                unsafe { CStr::from_ptr(self.name).to_string_lossy().into_owned() },
                self.posedge_cb_count,
                self.negedge_cb_count,
                self.edge_cb_count
            )
        }

        #[cfg(not(feature = "merge_cb"))]
        {
            write!(
                f,
                "ComplexHandle({}, name: {})",
                self.vpi_handle as c_longlong,
                unsafe { CStr::from_ptr(self.name).to_string_lossy().into_owned() }
            )
        }
    }
}

pub struct IDPool {
    // allocated_ids: HashSet<EdgeCallbackID>,
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
        IDPool {
            // allocated_ids: HashSet::new(),
            available_ids,
        }
    }

    pub fn alloc_id(&mut self) -> EdgeCallbackID {
        if self.available_ids.is_empty() {
            panic!("No more IDs available");
        }

        let id = *self.available_ids.iter().next().unwrap();
        self.available_ids.remove(&id);
        // self.allocated_ids.insert(id);

        id
    }

    pub fn release_id(&mut self, id: EdgeCallbackID) {
        // TODO: Safe Check
        // if !self.allocated_ids.remove(&id) {
        //     panic!("Invalid ID: {}", id);
        // }

        self.available_ids.insert(id);
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
        self.finalize();
    }
}

impl VeriluaEnv {
    pub fn initialize(&mut self) {
        log::debug!("VeriluaEnv::initialize()");

        if self.initialized {
            return;
        } else {
            self.initialized = true;
        }

        if !self.has_final_cb {
            unsafe { vpi_callback::register_final_callback() };
        }

        let lua_dofile: LuaFunction = self.lua.globals().get("dofile").unwrap();

        let verilua_home = std::env::var("VERILUA_HOME").expect("VERILUA_HOME not set");

        if cfg!(feature = "iverilog") {
            self.resolve_x_as_zero =
                std::env::var("VL_RESOLVE_X_AS_ZERO").map_or(true, |v| v == "1" || v == "true");
        }

        let init_file = verilua_home + "/src/lua/verilua/init.lua";
        if let Err(e) = lua_dofile.call::<()>(init_file) {
            panic!("Failed to load init.lua: {e}");
        };

        if std::env::var("DUT_TOP").is_err() {
            unsafe {
                let dut_top = CStr::from_ptr(utils::get_top_module()).to_str().unwrap();
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

        include!("./gen/gen_sim_event_chunk_init.rs");

        self.start_time = Instant::now();
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

        let finish_callback: LuaFunction = self.lua.globals().get("finish_callback").unwrap();
        finish_callback.call::<()>(()).unwrap();

        let total_time = self.start_time.elapsed();

        use prettytable::{Cell, Row, Table, row};
        let mut table = Table::new();

        let title = Cell::new("Verilua Statistic")
            .with_hspan(3)
            .with_style(prettytable::Attr::Bold)
            .style_spec("c");
        let title_row = Row::new(vec![title]);

        table.add_row(title_row);
        table.add_row(row!["total_time_taken", "lua_time_taken", "lua_overhead"]);

        #[cfg(feature = "acc_time")]
        table.add_row(row![
            format!("{:.2} sec", total_time.as_secs_f64()),
            format!("{:.2} sec", self.lua_time.as_secs_f64()),
            format!(
                "{:.2}%",
                (self.lua_time.as_secs_f64() / total_time.as_secs_f64()) * 100.0
            )
        ]);

        #[cfg(not(feature = "acc_time"))]
        table.add_row(row![
            format!("{:.2} sec", total_time.as_secs_f64()),
            "--",
            "--"
        ]);

        table.printstd();

        self.hdl_cache
            .iter()
            .enumerate()
            .for_each(|(idx, (_, complex_handle))| {
                log::trace!("[{idx}] {:?}", ComplexHandle::from_raw(complex_handle));
            });

        let standard_font = figlet_rs::FIGfont::standard().unwrap();
        println!("{}", standard_font.convert("VERILUA FINISH").unwrap());
    }
}

// ----------------------------------------------------------------------------------------------------------
//  Export functions for embeding Verilua inside other simulation environments
//  Make sure to use verilua_init() at the beginning of the simulation and use verilua_final() at the end of the simulation.
//  The verilua_main_step() should be invoked at the beginning of each simulation step.
// ----------------------------------------------------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_init() {
    get_verilua_env().initialize();
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_final() {
    get_verilua_env().finalize();
}

// Execute the main_step function in a way that is safe to be called.
// If the main_step function throws an error, the error will be caught
// and the Verilua environment will be finalized.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_main_step() {
    let env = get_verilua_env();
    assert!(
        env.initialized,
        "verilua_main_step() called before verilua_init()"
    );

    #[cfg(feature = "acc_time")]
    let s = Instant::now();

    if let Err(e) = env.lua_main_step.as_ref().unwrap().call::<()>(()) {
        panic!("Error calling lua_main_step: {e}");
    };

    #[cfg(feature = "acc_time")]
    {
        env.lua_time += s.elapsed();
    }
}

// Same as execute_main_step() while error will not cause the program to crash
#[unsafe(no_mangle)]
pub unsafe extern "C" fn verilua_main_step_safe() {
    thread_local! {
        static HAS_ERROR: Cell<bool> = const { Cell::new(false) };
    }

    if HAS_ERROR.with(|f| f.get()) {
        println!(
            "[verilua_main_step_safe] `has_error` is `true`! Program should be terminated! Nothing will be done in `Verilua`..."
        );
        return;
    }

    let env = get_verilua_env();
    assert!(
        env.initialized,
        "[verilua_main_step_safe] verilua_main_step_safe() called before verilua_init()"
    );

    #[cfg(feature = "acc_time")]
    let s = Instant::now();

    if let Err(e) = env.lua_main_step.as_ref().unwrap().call::<()>(()) {
        HAS_ERROR.with(|has_error| {
            has_error.set(true);
        });

        println!("[verilua_main_step_safe] Error calling lua_main_step: {e}");
    };

    #[cfg(feature = "acc_time")]
    {
        env.lua_time += s.elapsed();
    }
}

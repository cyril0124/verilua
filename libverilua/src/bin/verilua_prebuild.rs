
#[unsafe(no_mangle)]
pub extern "C" fn vpi_free_object(obj: vpiHandle) {}

#[unsafe(no_mangle)]
pub extern "C" fn vpi_register_cb(cb_data: *mut t_cb_data) -> vpiHandle {
    0 as vpiHandle
}

#[unsafe(no_mangle)]
pub extern "C" fn vpi_remove_cb(cb_obj: vpiHandle) {}

#[unsafe(no_mangle)]
pub extern "C" fn vpi_iterate(type_: PLI_INT32, refHandle: vpiHandle) -> vpiHandle {
    0 as vpiHandle
}

#[unsafe(no_mangle)]
pub extern "C" fn vpi_scan(iterator: vpiHandle) -> vpiHandle {
    0 as vpiHandle
}

#[unsafe(no_mangle)]
pub extern "C" fn vpi_get_str(property: PLI_INT32, object: vpiHandle) -> *mut PLI_BYTE8 {
    std::ptr::null_mut()
}

#[unsafe(no_mangle)]
pub extern "C" fn vpi_get(property: PLI_INT32, object: vpiHandle) -> PLI_INT32 {
    0
}

fn main() {
    use crate::verilua_env::*;
    use clap::Parser;

    #[derive(Parser, Debug)]
    #[command(version, about, long_about = None)]
    struct Args {
        #[arg(short, long, help = "Input filelist used by `SignalDB`")]
        filelist: Option<String>,

        #[arg(short, long, help = "Input top module")]
        top: Option<String>,

        #[arg(short, long, help = "Input lua script")]
        lua_script: Option<String>,

        #[arg(short, long, help = "Input config file(VERILUA_CFG)")]
        cfg: Option<String>,

        #[arg(short, long, action = clap::ArgAction::SetTrue)]
        verbose: Option<bool>,
    }

    let args = Args::parse();
    if args.verbose.unwrap_or(false) {
        println!("[verilua_prebuild] args: {:?}", args);
    }

    unsafe { 
        std::env::set_var("VL_PREBUILD", "1");

        if args.filelist.is_some() {
            std::env::set_var("VL_PREBUILD_FILELIST", args.filelist.unwrap());
        }

        if args.top.is_some() {
            std::env::set_var("DUT_TOP", args.top.unwrap());
        }

        if args.lua_script.is_some() {
            std::env::set_var("LUA_SCRIPT", args.lua_script.unwrap());
        }

        if args.cfg.is_some() {
            std::env::set_var("VERILUA_CFG", args.cfg.unwrap());
        }
        
        // TODO: replace with `prebuild`
        std::env::set_var("SIM", "wave_vpi");
    }

    let env = get_verilua_env();
    env.initialize();

    let run_prebuild_tasks: LuaFunction = env.lua.globals().get("run_prebuild_tasks").unwrap();
    if let Err(e) = run_prebuild_tasks.call::<()>(()) {
        panic!("Failed to call run_prebuild_tasks: {e}");
    };
}
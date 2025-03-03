pub mod idpool;

use goblin::elf::Elf;
use hashbrown::HashMap;
use libc::{PATH_MAX, c_char, readlink};
use once_cell::sync::OnceCell;
use std::ffi::{CStr, CString};
use std::io::Read;
use std::{fs::File, sync::Mutex};

use super::vpi_user::*;

use lazy_static::*;

#[unsafe(no_mangle)]
pub extern "C" fn get_executable_name() -> *const libc::c_char {
    let mut path = [0; PATH_MAX as usize];
    let len = unsafe {
        readlink(
            "/proc/self/exe\0".as_ptr() as *const _,
            path.as_mut_ptr() as *mut _,
            path.len(),
        )
    };

    if len != -1 {
        let len = len as usize;
        path[len] = 0; // Null-terminate the string

        let executable_name = CString::new(&path[..len]).expect("CString::new failed");
        (executable_name.into_raw()) as _
    } else {
        panic!("Failed to get executable name");
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn get_self_cmdline() -> *mut libc::c_char {
    let mut file = match File::open("/proc/self/cmdline") {
        Ok(file) => file,
        Err(_) => {
            panic!("Failed to open /proc/self/cmdline");
        }
    };

    let mut buffer = Vec::new();
    if file.read_to_end(&mut buffer).is_err() {
        panic!("Failed to read /proc/self/cmdline");
    }

    for i in 0..buffer.len() {
        if buffer[i] == b'\0' {
            buffer[i] = b' ';
        }
    }

    let cmdline_content = match String::from_utf8(buffer) {
        Ok(content) => content,
        Err(_) => {
            panic!("Invalid UTF-8 in /proc/self/cmdline");
        }
    };

    let cstring = match CString::new(cmdline_content) {
        Ok(cstr) => cstr,
        Err(_) => {
            panic!("Failed to create CString");
        }
    };

    cstring.into_raw()
}

lazy_static! {
    static ref SYMBOL_ADDRESS_MAP: Mutex<HashMap<String, u64>> = Mutex::new(HashMap::new());
}

#[unsafe(no_mangle)]
pub extern "C" fn get_symbol_address(filename: *const c_char, symbol_name: *const c_char) -> u64 {
    let filename = unsafe { CStr::from_ptr(filename).to_string_lossy().into_owned() };
    let symbol_name = unsafe { CStr::from_ptr(symbol_name).to_string_lossy().into_owned() };

    let offset: u64 = 0; // Placeholder for actual offset retrieval logic

    let mut map = SYMBOL_ADDRESS_MAP.lock().unwrap();
    if let Some(&address) = map.get(&symbol_name) {
        return address;
    }

    let mut file = File::open(&filename).expect("Failed to load ELF file");
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)
        .expect("Failed to read ELF file");

    let elf = Elf::parse(&buffer).expect("Failed to parse ELF file");
    let symtab = elf
        .syms
        .iter()
        .find(|symbol| {
            if let Some(name) = elf.strtab.get_at(symbol.st_name) {
                name == symbol_name
            } else {
                false
            }
        })
        .expect("Symbol not found");
    let final_address = symtab.st_value + offset;
    map.insert(symbol_name, final_address);

    final_address
}

static CACHE_RESULT: Mutex<Option<String>> = Mutex::new(None);
static EXECUTABLE_NAME: OnceCell<String> = OnceCell::new();

#[unsafe(no_mangle)]
pub extern "C" fn get_simulator_auto() -> *const std::ffi::c_char {
    let mut cached_result = CACHE_RESULT.lock().unwrap();
    if let Some(ref result) = *cached_result {
        return CString::new(result.clone()).unwrap().into_raw();
    }

    let executable_name = EXECUTABLE_NAME.get_or_init(|| {
        let ptr = get_executable_name();
        let cstr = unsafe { CStr::from_ptr(ptr) };
        cstr.to_string_lossy().into_owned()
    });

    let mut file = File::open(executable_name).expect("Failed to open ELF file");
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)
        .expect("Failed to read ELF file");
    let elf = Elf::parse(&buffer).expect("Failed to parse ELF file");

    // TODO: Optimize, read only the needed sections
    for string in elf.libraries {
        log::debug!("[get_simulator_auto] Found library: {string}");
        if string.contains("libverilua_verilator.so") {
            *cached_result = Some("verilator".to_string());
            return CString::new("verilator").unwrap().into_raw();
        } else if string.contains("libverilua_vcs.so") {
            *cached_result = Some("vcs".to_string());
            return CString::new("vcs").unwrap().into_raw();
        } else if string.contains("liverilua_iverilog.so") {
            *cached_result = Some("iverilog".to_string());
            return CString::new("iverilog").unwrap().into_raw();
        }
    }

    *cached_result = Some("unknown".to_string());
    CString::new("unknown").unwrap().into_raw()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn c_simulator_control(cmd: libc::c_longlong) {
    #[cfg(feature = "debug")]
    log::debug!("c_simulator_control => {}", {
        match cmd {
            66 => "vpiStop",
            67 => "vpiFinish",
            68 => "vpiReset",
            69 => "vpiSetInterativeScope",
            _ => panic!("Invalid command => {}", cmd),
        }
    });

    unsafe { vpi_control(cmd as i32) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn get_top_module() -> *const libc::c_char {
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

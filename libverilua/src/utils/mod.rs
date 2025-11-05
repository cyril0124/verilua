use fslock::LockFile;
use goblin::elf::Elf;
use hashbrown::HashMap;
use lazy_static::*;
use libc::{PATH_MAX, c_char, c_int, c_longlong, c_void, readlink};
use once_cell::sync::OnceCell;
use std::ffi::{CStr, CString};
use std::io::Read;
use std::process::Command;
use std::ptr;
use std::{fs::File, sync::Mutex};

use crate::vpi_user::*;

#[unsafe(no_mangle)]
pub extern "C" fn get_executable_name() -> *const c_char {
    let mut path = [0; PATH_MAX as usize];
    let len = unsafe {
        readlink(
            c"/proc/self/exe".as_ptr() as *const _,
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
pub extern "C" fn get_self_cmdline() -> *mut c_char {
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

    for buf in &mut buffer {
        if *buf == b'\0' {
            *buf = b' ';
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

cpp::cpp! {{
    #include <cassert>
    #include <dlfcn.h>
    #include <link.h>
}}

#[unsafe(no_mangle)]
pub extern "C" fn get_symbol_address(filename: *const c_char, symbol_name: *const c_char) -> u64 {
    let filename = unsafe { CStr::from_ptr(filename).to_string_lossy().into_owned() };
    let symbol_name = unsafe { CStr::from_ptr(symbol_name).to_string_lossy().into_owned() };

    let offset = unsafe {
        cpp::cpp!([] -> u64 as "uint64_t" {
            static uint64_t offset = 0;
            static bool get_offset = false;
            if (!get_offset) {
                get_offset = true;

                void *handle = dlopen(NULL, RTLD_LAZY);
                assert((handle != NULL) && "handle is NULL!");

                struct link_map *map;
                assert((dlinfo(handle, RTLD_DI_LINKMAP, &map) == 0) && "dlinfo failed!");

                offset = (uint64_t)map->l_addr;
            }
            return offset;
        })
    };

    let mut map = SYMBOL_ADDRESS_MAP.lock().unwrap();
    if let Some(&address) = map.get(&symbol_name) {
        return address;
    }

    let mut file = File::open(&filename).expect("Failed to load ELF file");
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)
        .expect("Failed to read ELF file");

    let elf = Elf::parse(&buffer).expect("Failed to parse ELF file");
    let symtab_opt = elf.syms.iter().find(|symbol| {
        if let Some(name) = elf.strtab.get_at(symbol.st_name) {
            name == symbol_name
        } else {
            false
        }
    });

    if let Some(symtab) = symtab_opt {
        let final_address = symtab.st_value + offset;
        map.insert(symbol_name, final_address);
        final_address
    } else {
        // Symbol not found
        0
    }
}

static CACHE_RESULT: Mutex<Option<String>> = Mutex::new(None);
static EXECUTABLE_NAME: OnceCell<String> = OnceCell::new();

#[unsafe(no_mangle)]
pub extern "C" fn get_simulator_auto() -> *const c_char {
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
        log::info!("[get_simulator_auto] Found library: {string}");
        if string.contains("libverilua_verilator.so")
            || string.contains("libverilua_verilator_dpi.so")
        {
            *cached_result = Some("verilator".to_string());
            return CString::new("verilator").unwrap().into_raw();
        } else if string.contains("libverilua_vcs.so") || string.contains("libverilua_vcs_dpi.so") {
            *cached_result = Some("vcs".to_string());
            return CString::new("vcs").unwrap().into_raw();
        } else if string.contains("liverilua_iverilog.so") {
            *cached_result = Some("iverilog".to_string());
            return CString::new("iverilog").unwrap().into_raw();
        } else if string.contains("libverilua_wave_vpi.so") {
            *cached_result = Some("wave_vpi".to_string());
            return CString::new("wave_vpi").unwrap().into_raw();
        } else if string.contains("libverilua_nosim.so") {
            *cached_result = Some("nosim".to_string());
            return CString::new("nosim").unwrap().into_raw();
        }
    }

    *cached_result = Some("unknown".to_string());
    CString::new("unknown").unwrap().into_raw()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn c_simulator_control(cmd: c_longlong) {
    log::info!("c_simulator_control => {}", {
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
pub unsafe extern "C" fn wildmatch(pattern: *const c_char, string: *const c_char) -> c_int {
    let pattern = unsafe { CStr::from_ptr(pattern) };
    let string = unsafe { CStr::from_ptr(string) };
    wildmatch::WildMatch::new(pattern.to_str().unwrap()).matches(string.to_str().unwrap()) as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn acquire_lock(path: *const c_char) -> *mut c_void {
    if path.is_null() {
        println!("[acquire_lock] Path is null");
        return ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let mut lockfile = match LockFile::open(path_str) {
        Ok(f) => f,
        Err(_) => {
            println!(
                "[acquire_lock] Failed to open lock file, path: {}",
                path_str
            );
            return ptr::null_mut();
        }
    };

    if let Err(err) = lockfile.lock() {
        println!(
            "[acquire_lock] Failed to lock, path: {}, err: {:?}",
            path_str, err
        );
        return ptr::null_mut();
    }

    Box::into_raw(Box::new(lockfile)) as *mut c_void
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn release_lock(lock_handle: *mut c_void) {
    if lock_handle.is_null() {
        panic!("Lock handle is null");
    }

    let lock_ptr = lock_handle as *mut LockFile;

    let _lockfile_box = unsafe { Box::from_raw(lock_ptr) };
}

#[unsafe(no_mangle)]
pub extern "C" fn iorun(cmd: *const c_char) -> *const c_char {
    if cmd.is_null() {
        log::debug!("ERROR: iorun received a NULL command pointer");
        return std::ptr::null();
    }

    let cmd_str = match unsafe { CStr::from_ptr(cmd) }.to_str() {
        Ok(s) => s,
        Err(e) => {
            log::debug!("ERROR: Failed to convert C string to UTF-8: {}", e);
            return std::ptr::null();
        }
    };

    let output = if cfg!(target_os = "windows") {
        Command::new("cmd").args(&["/C", cmd_str]).output()
    } else {
        Command::new("sh").arg("-c").arg(cmd_str).output()
    };

    match output {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();

            // Use stdout if available, otherwise use stderr
            let result = if !stdout.is_empty() {
                stdout
            } else if !stderr.is_empty() {
                log::debug!("No stdout, using stderr as result");
                stderr
            } else {
                log::debug!("Both stdout and stderr are empty");
                String::new()
            };

            match CString::new(result.clone()) {
                Ok(c_string) => c_string.into_raw(),
                Err(e) => {
                    log::debug!("ERROR: Failed to create CString from result: {}", e);
                    std::ptr::null()
                }
            }
        }
        Err(e) => {
            log::debug!("ERROR: Failed to execute command '{}': {}", cmd_str, e);
            std::ptr::null()
        }
    }
}

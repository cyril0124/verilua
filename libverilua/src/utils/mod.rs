//! # Verilua Utility Functions
//!
//! This module provides FFI utilities, system interaction functions, and
//! helper routines used throughout the Verilua codebase.

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

// ────────────────────────────────────────────────────────────────────────────────
// FFI String Conversion Functions
// ────────────────────────────────────────────────────────────────────────────────
//
// Naming Convention:
//   c_char_to_*    - Convert from C string to Rust type
//   *_to_c_char    - Convert from Rust type to C string
//   *_owned        - Caller is responsible for freeing the memory
//
// Memory Rules:
//   - Functions returning *mut c_char allocate memory
//   - Use c_char_free() to release Rust-allocated C strings
//   - Functions taking *const c_char borrow from C (don't free)

/// Converts a C string to an owned Rust String.
///
/// Invalid UTF-8 sequences are replaced with U+FFFD (replacement character).
/// This is safe for display purposes but may lose information.
#[inline(always)]
pub fn c_char_to_string(c_char: *const c_char) -> String {
    debug_assert!(!c_char.is_null(), "c_char_to_string: null pointer");
    unsafe { CStr::from_ptr(c_char).to_string_lossy().into_owned() }
}

/// Converts a C string to a borrowed &str reference.
///
/// # Safety
/// - `c_char` must be a valid, null-terminated C string
/// - The string must be valid UTF-8 (panics otherwise)
/// - The returned reference is valid only while the C string is alive
#[inline(always)]
pub unsafe fn c_char_to_str<'a>(c_char: *const c_char) -> &'a str {
    debug_assert!(!c_char.is_null(), "c_char_to_str: null pointer");
    unsafe { CStr::from_ptr(c_char).to_str().unwrap() }
}

/// Converts a C string to Option<&str>, returning None on null or invalid UTF-8.
///
/// This is the safest conversion function for potentially invalid input.
#[inline(always)]
pub unsafe fn c_char_to_str_opt<'a>(c_char: *const c_char) -> Option<&'a str> {
    if c_char.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(c_char).to_str().ok() }
}

/// Converts a &str to an owned C string pointer.
///
/// # Memory
/// The caller must free the returned pointer using `c_char_free()`.
///
/// # Panics
/// Panics if the string contains embedded null bytes.
#[inline(always)]
pub fn string_to_c_char_owned(string: &str) -> *mut c_char {
    CString::new(string)
        .expect("string_to_c_char_owned: string contains null byte")
        .into_raw()
}

/// Converts an owned String to a C string pointer.
///
/// # Memory
/// The caller must free the returned pointer using `c_char_free()`.
#[inline(always)]
pub fn owned_string_to_c_char(string: String) -> *mut c_char {
    CString::new(string)
        .expect("owned_string_to_c_char: string contains null byte")
        .into_raw()
}

/// Frees a C string that was allocated by Rust FFI functions.
///
/// # Safety
/// - The pointer must have been allocated by Rust (via CString::into_raw)
/// - The pointer must not have been freed already
/// - Safe to call with null pointer (no-op)
#[inline(always)]
#[allow(dead_code)]
pub unsafe fn c_char_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = unsafe { CString::from_raw(ptr) };
    }
}

/// Converts a C string pointer to a &CStr reference.
///
/// Useful when you need to work with CStr methods directly.
#[inline(always)]
pub unsafe fn c_char_to_cstr<'a>(c_char: *const c_char) -> &'a CStr {
    debug_assert!(!c_char.is_null(), "c_char_to_cstr: null pointer");
    unsafe { CStr::from_ptr(c_char) }
}

// ────────────────────────────────────────────────────────────────────────────────
// System Introspection Functions
// ────────────────────────────────────────────────────────────────────────────────

/// Returns the full path of the current executable.
///
/// Uses /proc/self/exe on Linux to get the actual executable path,
/// resolving any symlinks.
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

/// Returns the command line used to start this process.
///
/// Reads from /proc/self/cmdline and converts null separators to spaces.
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

// ────────────────────────────────────────────────────────────────────────────────
// ELF Symbol Resolution
// ────────────────────────────────────────────────────────────────────────────────

lazy_static! {
    /// Cache for resolved symbol addresses to avoid repeated ELF parsing.
    static ref SYMBOL_ADDRESS_MAP: Mutex<HashMap<String, u64>> = Mutex::new(HashMap::new());
}

cpp::cpp! {{
    #include <cassert>
    #include <dlfcn.h>
    #include <link.h>
}}

/// Looks up a symbol's runtime address in an ELF file.
///
/// Uses dlinfo to get the base address offset and then parses the ELF
/// symbol table to find the symbol's address. Results are cached.
#[unsafe(no_mangle)]
pub extern "C" fn get_symbol_address(filename: *const c_char, symbol_name: *const c_char) -> u64 {
    let filename = c_char_to_string(filename);
    let symbol_name = c_char_to_string(symbol_name);

    // Get the ASLR offset for the current process
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

    // Check cache first
    let mut map = SYMBOL_ADDRESS_MAP.lock().unwrap();
    if let Some(&address) = map.get(&symbol_name) {
        return address;
    }

    // Parse ELF and find symbol
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

// ────────────────────────────────────────────────────────────────────────────────
// Simulator Auto-Detection
// ────────────────────────────────────────────────────────────────────────────────

static CACHE_RESULT: Mutex<Option<String>> = Mutex::new(None);
static EXECUTABLE_NAME: OnceCell<String> = OnceCell::new();

/// Auto-detects which simulator is running by examining linked libraries.
///
/// Inspects the ELF dynamic section to find which libverilua variant is loaded:
/// - libverilua_verilator.so → "verilator"
/// - libverilua_vcs.so → "vcs"
/// - libverilua_iverilog.so → "iverilog"
/// - libverilua_wave_vpi.so → "wave_vpi"
/// - libverilua_nosim.so → "nosim"
#[unsafe(no_mangle)]
pub extern "C" fn get_simulator_auto() -> *const c_char {
    let mut cached_result = CACHE_RESULT.lock().unwrap();
    if let Some(ref result) = *cached_result {
        return string_to_c_char_owned(result);
    }

    let executable_name = EXECUTABLE_NAME.get_or_init(|| {
        let ptr = get_executable_name();
        c_char_to_string(ptr)
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
            return string_to_c_char_owned("verilator");
        } else if string.contains("libverilua_vcs.so") || string.contains("libverilua_vcs_dpi.so") {
            *cached_result = Some("vcs".to_string());
            return string_to_c_char_owned("vcs");
        } else if string.contains("libverilua_xcelium.so")
            || string.contains("libverilua_xcelium_dpi.so")
        {
            *cached_result = Some("xcelium".to_string());
            return string_to_c_char_owned("xcelium");
        } else if string.contains("liverilua_iverilog.so") {
            *cached_result = Some("iverilog".to_string());
            return string_to_c_char_owned("iverilog");
        } else if string.contains("libverilua_wave_vpi.so") {
            *cached_result = Some("wave_vpi".to_string());
            return string_to_c_char_owned("wave_vpi");
        } else if string.contains("libverilua_nosim.so") {
            *cached_result = Some("nosim".to_string());
            return string_to_c_char_owned("nosim");
        }
    }

    *cached_result = Some("unknown".to_string());
    string_to_c_char_owned("unknown")
}

// ────────────────────────────────────────────────────────────────────────────────
// Simulation Control
// ────────────────────────────────────────────────────────────────────────────────

/// Controls the simulator state (stop, finish, reset).
///
/// Wraps vpi_control with human-readable logging.
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

// ────────────────────────────────────────────────────────────────────────────────
// Pattern Matching & I/O Utilities
// ────────────────────────────────────────────────────────────────────────────────

/// Performs glob-style wildcard pattern matching.
///
/// Supports * and ? wildcards as in shell glob patterns.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wildmatch(pattern: *const c_char, string: *const c_char) -> c_int {
    let pattern = unsafe { c_char_to_cstr(pattern) }.to_str().unwrap();
    let string = unsafe { c_char_to_cstr(string) }.to_str().unwrap();
    wildmatch::WildMatch::new(pattern).matches(string) as c_int
}

/// Acquires a file-based lock for inter-process synchronization.
///
/// Returns an opaque handle that must be passed to `release_lock()`.
/// Returns null on failure.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn acquire_lock(path: *const c_char) -> *mut c_void {
    if path.is_null() {
        println!("[acquire_lock] Path is null");
        return ptr::null_mut();
    }

    let path_str = match unsafe { c_char_to_str_opt(path) } {
        Some(s) => s,
        None => return ptr::null_mut(),
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

/// Releases a file lock acquired by `acquire_lock()`.
///
/// # Panics
/// Panics if the handle is null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn release_lock(lock_handle: *mut c_void) {
    if lock_handle.is_null() {
        panic!("Lock handle is null");
    }

    let lock_ptr = lock_handle as *mut LockFile;

    let _lockfile_box = unsafe { Box::from_raw(lock_ptr) };
}

/// Executes a shell command and returns its output.
///
/// Returns stdout if available, otherwise stderr. Returns null on error.
/// The returned string must be freed by the caller.
#[unsafe(no_mangle)]
pub extern "C" fn iorun(cmd: *const c_char) -> *const c_char {
    if cmd.is_null() {
        log::debug!("ERROR: iorun received a NULL command pointer");
        return std::ptr::null();
    }

    let cmd_str = match unsafe { c_char_to_str_opt(cmd) } {
        Some(s) => s,
        None => {
            log::debug!("ERROR: Failed to convert C string to UTF-8");
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

            // Note: CString::new can fail if result contains null bytes
            // Using owned_string_to_c_char which panics in that case
            // For safety in FFI, we catch this case
            if result.contains('\0') {
                log::debug!("ERROR: Result contains null byte");
                return std::ptr::null();
            }
            owned_string_to_c_char(result)
        }
        Err(e) => {
            log::debug!("ERROR: Failed to execute command '{}': {}", cmd_str, e);
            std::ptr::null()
        }
    }
}

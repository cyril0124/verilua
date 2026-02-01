#![allow(non_upper_case_globals)]
#![allow(non_snake_case)]

use byteorder::{BigEndian, ByteOrder};
use bytesize::ByteSize;
use serde::{Deserialize, Serialize};
use std::borrow::Borrow;
use std::cell::UnsafeCell;
use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString};
use std::fs;
use std::fs::File;
use std::io::{BufReader, BufWriter};
use std::os::raw::{c_char, c_void};
use std::os::unix::fs::MetadataExt;
use std::time::UNIX_EPOCH;
use wellen::*;

mod vpi_user;
use vpi_user::*;

#[allow(non_camel_case_types)]
type vpiHandle = SignalRef;

#[derive(Debug, Serialize, Deserialize)]
struct FileModifiedInfo {
    size: u64,
    time: u64,
}

#[derive(Debug, Serialize, Deserialize)]
struct SignalInfo {
    pub signal: Signal,
    pub var_type: VarType,
}

const LOAD_OPTS: LoadOptions = LoadOptions {
    multi_thread: true,
    remove_scopes_with_empty_name: false,
};

// If the cached signal ref count is greater than this, we will not use the cached data.
const SIGNAL_REF_COUNT_THRESHOLD: usize = 15;

const LAST_MODIFIED_TIME_FILE: &str = "last_modified_time.wave_vpi.yaml";
const SIGNAL_REF_COUNT_FILE: &str = "signal_ref_count.wave_vpi.yaml";
const SIGNAL_REF_CACHE_FILE: &str = "signal_ref_cache.wave_vpi.yaml";
const SIGNAL_REF_CACHE_NULL_FILE: &str = "signal_ref_cache_null.wave_vpi.yaml";
const SIGNAL_CACHE_FILE: &str = "signal_cache.wave_vpi.yaml";

static mut TIME_TABLE: Option<UnsafeCell<Vec<u64>>> = None;
static mut HIERARCHY: Option<UnsafeCell<Hierarchy>> = None;
static mut WAVE_SOURCE: Option<UnsafeCell<SignalSource>> = None;

static mut SIGNAL_REF_CACHE: Option<UnsafeCell<HashMap<String, SignalRef>>> = None;
static mut SIGNAL_REF_CACHE_NULL: Option<UnsafeCell<HashSet<String>>> = None;
static mut SIGNAL_CACHE: Option<UnsafeCell<HashMap<SignalRef, SignalInfo>>> = None;
static mut HAS_NEWLY_ADD_SIGNAL_REF: bool = false;

#[static_init::constructor(0)]
extern "C" fn init_env_logger() {
    let _ = env_logger::try_init();
}

#[inline(always)]
fn get_time_table() -> &'static mut Vec<u64> {
    unsafe {
        match TIME_TABLE {
            Some(ref mut time_table) => &mut *time_table.get(),
            None => {
                panic!(
                    "TIME_TABLE is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn get_hierarchy() -> &'static Hierarchy {
    unsafe {
        match HIERARCHY {
            Some(ref hierarchy) => &*hierarchy.get(),
            None => {
                panic!(
                    "HIERARCHY is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn get_signal_ref_cache() -> &'static mut HashMap<String, SignalRef> {
    unsafe {
        match SIGNAL_REF_CACHE {
            Some(ref mut signal_ref_cache) => &mut *signal_ref_cache.get(),
            None => {
                panic!(
                    "SIGNAL_REF_CACHE is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn get_signal_ref_cache_null() -> &'static mut HashSet<String> {
    unsafe {
        match SIGNAL_REF_CACHE_NULL {
            Some(ref mut signal_ref_cache_null) => &mut *signal_ref_cache_null.get(),
            None => {
                panic!(
                    "SIGNAL_REF_CACHE_NULL is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn try_get_signal_ref_cache() -> Option<&'static mut HashMap<String, SignalRef>> {
    unsafe {
        match SIGNAL_REF_CACHE {
            Some(_) => Some(get_signal_ref_cache()),
            None => None,
        }
    }
}

#[inline(always)]
fn get_signal_cache() -> &'static mut HashMap<SignalRef, SignalInfo> {
    unsafe {
        match SIGNAL_CACHE {
            Some(ref mut signal_cache) => &mut *signal_cache.get(),
            None => {
                panic!(
                    "SIGNAL_CACHE is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn try_get_signal_cache() -> Option<&'static mut HashMap<SignalRef, SignalInfo>> {
    unsafe {
        match SIGNAL_CACHE {
            Some(_) => Some(get_signal_cache()),
            None => None,
        }
    }
}

#[inline(always)]
fn get_wave_source() -> &'static mut SignalSource {
    unsafe {
        match WAVE_SOURCE {
            Some(ref mut signal_source) => &mut *signal_source.get(),
            None => {
                panic!(
                    "SIGNAL_CACHE is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline]
fn lest_score(target: &str, candidate: &str) -> usize {
    target
        .split('.')
        .zip(candidate.split('.'))
        .take_while(|(a, b)| a == b)
        .count()
}

/// Get the most likely signal names from the hierarchy
/// Returns top N candidates sorted by best match
fn get_most_likely_signal_name(name: &str, n: usize) -> Vec<String> {
    let hierarchy = get_hierarchy();
    let mut match_vec: Vec<(usize, String)> = hierarchy
        .iter_vars()
        .map(|var| {
            let full_name = var.full_name(hierarchy);
            let score = lest_score(name, full_name.as_str());
            (score, full_name)
        })
        .collect();

    // Sort by score (descending) and name (for stability)
    match_vec.sort_unstable_by(|(score_a, name_a), (score_b, name_b)| {
        score_b.cmp(score_a).then_with(|| name_a.cmp(name_b))
    });

    match_vec.into_iter().take(n).map(|(_, s)| s).collect()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_initialize(filename: *const c_char) {
    let c_str = unsafe {
        assert!(!filename.is_null());
        CStr::from_ptr(filename)
    };

    let r_str = c_str.to_str().unwrap();
    let filename = r_str;

    let header =
        viewers::read_header_from_file(filename, &LOAD_OPTS).expect("Failed to load file!");
    let hierarchy = header.hierarchy;

    let body = viewers::read_body(header.body, &hierarchy, None).expect("Failed to load body!");
    let wave_source = body.source;
    wave_source.print_statistics();
    log::info!(
        "[wave_vpi::wellen_initialize] The hierarchy takes up at least {} of memory.",
        ByteSize::b(hierarchy.size_in_memory() as u64)
    );

    unsafe {
        let time_table_len = body.time_table.len();
        TIME_TABLE = Some(UnsafeCell::new(body.time_table));
        HIERARCHY = Some(UnsafeCell::new(hierarchy));
        WAVE_SOURCE = Some(UnsafeCell::new(wave_source));

        log::info!(
            "[wave_vpi::wellen_initialize] Time table size: {}",
            time_table_len
        );
    }

    // If the wave file has not been modified, we can use the cached data to speed up the simulation.
    let mut use_cached_data = false;
    if let Ok(file) = File::open(LAST_MODIFIED_TIME_FILE) {
        let reader = BufReader::new(file);
        let modified_time: FileModifiedInfo = serde_yaml::from_reader(reader)
            .unwrap_or_else(|_| panic!("Failed to parse {}", LAST_MODIFIED_TIME_FILE));
        let last_modified_timestamp = modified_time.time;
        let last_file_size = modified_time.size;

        let metadata = fs::metadata(filename).expect("Failed to get file metadata");
        let file_size = metadata.size();
        let modified = metadata.modified().expect("Failed to get modified time");
        let duration_since_epoch = modified.duration_since(UNIX_EPOCH).unwrap();
        let modified_timestamp = duration_since_epoch.as_secs();

        // Update the timestamp if the file has been modified.
        if last_modified_timestamp != modified_timestamp || last_file_size != file_size {
            let file = File::create(LAST_MODIFIED_TIME_FILE).unwrap();
            let writer = BufWriter::new(file);

            let modified_time = FileModifiedInfo {
                size: file_size,
                time: modified_timestamp,
            };

            log::info!(
                "[wave_vpi::wellen_initialize] modified_timestamp: last({}) curr({})  file_size: last({}) curr({})",
                last_modified_timestamp,
                modified_timestamp,
                last_file_size,
                file_size
            );

            serde_yaml::to_writer(writer, &modified_time).unwrap();
        } else if let Ok(file) = File::open(SIGNAL_REF_COUNT_FILE) {
            let reader: BufReader<File> = BufReader::new(file);
            let signal_ref_count: usize = serde_yaml::from_reader(reader)
                .unwrap_or_else(|_| panic!("Failed to parse {}", SIGNAL_REF_COUNT_FILE));

            let signal_ref_count_threshold = SIGNAL_REF_COUNT_THRESHOLD;
            log::info!(
                "[wave_vpi::wellen_initialize] signal_ref_count: {} signal_ref_count_threshold: {}",
                signal_ref_count,
                signal_ref_count_threshold
            );

            if signal_ref_count >= signal_ref_count_threshold {
                use_cached_data = true;
            }
        } else {
            use_cached_data = true;
        }
    } else {
        // Create new file if it does not exist.
        let metadata = fs::metadata(filename).expect("Failed to get file metadata");
        let file_size = metadata.size();
        let modified = metadata.modified().expect("Failed to get modified time");
        let duration_since_epoch = modified.duration_since(UNIX_EPOCH).unwrap();
        let modified_timestamp = duration_since_epoch.as_secs();

        let file = File::create(LAST_MODIFIED_TIME_FILE).unwrap();
        let writer = BufWriter::new(file);

        let modified_time = FileModifiedInfo {
            size: file_size,
            time: modified_timestamp,
        };

        log::info!(
            "[wave_vpi::wellen_initialize] modified_timestamp(new): {}  file_size(new): {}",
            modified_timestamp,
            file_size
        );

        serde_yaml::to_writer(writer, &modified_time).unwrap();
    }
    log::info!(
        "[wave_vpi::wellen_initialize] use_cached_data => {} {}",
        use_cached_data,
        if use_cached_data { "✅" } else { "❌" }
    );

    unsafe {
        if try_get_signal_ref_cache().is_none() {
            if use_cached_data {
                log::info!(
                    "[wave_vpi::wellen_initialize] start read {}",
                    SIGNAL_REF_CACHE_FILE
                );
                let _file = File::open(SIGNAL_REF_CACHE_FILE);
                if let Ok(file) = _file {
                    let reader = BufReader::new(file);
                    SIGNAL_REF_CACHE =
                        Some(UnsafeCell::new(serde_yaml::from_reader(reader).unwrap()));
                } else {
                    log::warn!(
                        "[wave_vpi::wellen_initialize] Failed to open {}",
                        SIGNAL_REF_CACHE_FILE
                    );
                    SIGNAL_REF_CACHE = Some(UnsafeCell::new(HashMap::new()));
                }

                log::info!(
                    "[wave_vpi::wellen_initialize] start read {}",
                    SIGNAL_REF_CACHE_NULL_FILE
                );
                let _file = File::open(SIGNAL_REF_CACHE_NULL_FILE);
                if let Ok(file) = _file {
                    let reader = BufReader::new(file);
                    SIGNAL_REF_CACHE_NULL =
                        Some(UnsafeCell::new(serde_yaml::from_reader(reader).unwrap()));
                } else {
                    log::warn!(
                        "[wave_vpi::wellen_initialize] Failed to open {}",
                        SIGNAL_REF_CACHE_NULL_FILE
                    );
                    SIGNAL_REF_CACHE_NULL = Some(UnsafeCell::new(HashSet::new()));
                }
            } else {
                SIGNAL_REF_CACHE = Some(UnsafeCell::new(HashMap::new()));
                SIGNAL_REF_CACHE_NULL = Some(UnsafeCell::new(HashSet::new()));
            }
        }

        if try_get_signal_cache().is_none() {
            if use_cached_data {
                log::info!(
                    "[wave_vpi::wellen_initialize] start read {}",
                    SIGNAL_CACHE_FILE
                );
                let _file = File::open(SIGNAL_CACHE_FILE);
                if let Ok(file) = _file {
                    let reader = BufReader::new(file);
                    SIGNAL_CACHE = Some(UnsafeCell::new(serde_yaml::from_reader(reader).unwrap()));
                } else {
                    log::warn!(
                        "[wave_vpi::wellen_initialize] Failed to open signal cache file: {}",
                        SIGNAL_CACHE_FILE
                    );
                    SIGNAL_CACHE = Some(UnsafeCell::new(HashMap::new()));
                }
            } else {
                SIGNAL_CACHE = Some(UnsafeCell::new(HashMap::new()));
            }
        }
    }

    log::info!("[wave_vpi::wellen_initialize] init finish...");
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_finalize() {
    log::info!("[wave_vpi::wellen_finalize] ... ");

    let signal_ref_cache = get_signal_ref_cache();
    if signal_ref_cache.len() >= SIGNAL_REF_COUNT_THRESHOLD {
        unsafe {
            if HAS_NEWLY_ADD_SIGNAL_REF {
                log::info!("[wave_vpi::wellen_finalize] save signal ref into cache file");

                if let Some(ref cache) = SIGNAL_REF_CACHE {
                    let c = &*cache.get();
                    let file: File = File::create(SIGNAL_REF_COUNT_FILE).unwrap();
                    serde_yaml::to_writer(file, &c.len()).unwrap();
                }

                if let Some(ref cache) = SIGNAL_REF_CACHE {
                    let c = &*cache.get();
                    let file = File::create(SIGNAL_REF_CACHE_FILE).unwrap();
                    serde_yaml::to_writer(file, c).unwrap();
                }

                if let Some(ref cache) = SIGNAL_REF_CACHE_NULL {
                    let c = &*cache.get();
                    let file = File::create(SIGNAL_REF_CACHE_NULL_FILE).unwrap();
                    serde_yaml::to_writer(file, c).unwrap();
                }

                if let Some(ref cache) = SIGNAL_CACHE {
                    let c = &*cache.get();
                    let file = File::create(SIGNAL_CACHE_FILE).unwrap();
                    serde_yaml::to_writer(file, c).unwrap();
                }
            } else {
                log::info!("[wave_vpi::wellen_finalize] no newly added signal ref")
            }
        }
    } else {
        log::info!(
            "[wave_vpi::wellen_finalize] signal ref count is too small, not save cache file! signal_ref_count: {} < threshold: {}",
            signal_ref_cache.len(),
            SIGNAL_REF_COUNT_THRESHOLD
        );
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_handle_by_name(name: *const c_char) -> *mut c_void {
    let name = unsafe {
        assert!(!name.is_null());
        CStr::from_ptr(name)
    }
    .to_str()
    .unwrap();

    let id_opt = get_signal_ref_cache().get(&name.to_string());
    if let Some(id) = id_opt {
        log::debug!("find vpiHandle in cache => name: {} id: {:?}", name, id);
        let value = Box::new(*id as vpiHandle);
        return Box::into_raw(value) as *mut c_void;
    }

    if get_signal_ref_cache_null().get(&name.to_string()).is_some() {
        log::debug!("find vpiHandle in cache null => name: {}", name);
        return std::ptr::null_mut();
    }

    let id = if let Some((path_str, signal_name)) = name.rsplit_once(".") {
        let path_vec: Vec<&str> = path_str.split(".").collect();
        let path_slice: &[&str] = &path_vec;

        let hierarchy = get_hierarchy();
        let var_ref_opt = &hierarchy.lookup_var(path_slice, &signal_name);
        if var_ref_opt.is_none() {
            let v = get_most_likely_signal_name(name, 5);
            log::debug!(
                "Failed to lookup var, name: {}, path: {}, siangl: {}\nMost likely signal names: {:#?}",
                name,
                path_str,
                signal_name,
                v
            );
            // panic!(
            //     "Failed to lookup var, name: {}, path: {}, siangl: {}\nMost likely signal names: {:#?}",
            //     name, path_str, signal_name, v
            // );

            // If the signal is not found, we add it to the null cache to avoid looking it up again.
            get_signal_ref_cache_null().insert(String::from(name));
            unsafe {
                HAS_NEWLY_ADD_SIGNAL_REF = true;
            }

            // Return null if the signal is not found.
            return std::ptr::null_mut();
        }
        let var_ref = &var_ref_opt.unwrap();

        let var = &hierarchy[*var_ref];
        let ids = [var.signal_ref(); 1];
        let loaded = get_wave_source().load_signals(&ids, &hierarchy, LOAD_OPTS.multi_thread);
        let (loaded_id, loaded_signal) = loaded.into_iter().next().unwrap();
        assert_eq!(loaded_id, ids[0], "Failed to load signal, name: {}", name);

        get_signal_cache().insert(
            loaded_id,
            SignalInfo {
                signal: loaded_signal,
                var_type: var.var_type(),
            },
        );

        Some(loaded_id as vpiHandle)
    } else {
        panic!("[wellen_vpi_handle_by_name] not a valid name: {}", name);
    };

    assert!(
        id.is_some(),
        "[wellen_vpi_handle_by_name] cannot find vpiHandle => name:{}",
        name
    );

    log::debug!("find vpiHandle => name:{} id:{:?}", name, id);

    get_signal_ref_cache().insert(name.to_string(), id.unwrap());
    unsafe {
        HAS_NEWLY_ADD_SIGNAL_REF = true;
    }

    let value = Box::new(id.unwrap() as vpiHandle);
    Box::into_raw(value) as *mut c_void
}

#[inline]
fn bytes_to_u32s_be(bytes: &[u8]) -> Vec<u32> {
    let len = bytes.len();
    let capacity = (len + 3) / 4;
    let mut u32s = Vec::with_capacity(capacity);

    // Handle padding for non-aligned bytes
    let padding = (4 - (len % 4)) % 4;

    if padding > 0 {
        // First word with padding
        let mut first_word = 0u32;
        for (i, &byte) in bytes.iter().take(4 - padding).enumerate() {
            first_word |= (byte as u32) << ((4 - padding - 1 - i) * 8);
        }
        u32s.push(first_word);

        // Process remaining aligned chunks
        for chunk in bytes[(4 - padding)..].chunks_exact(4) {
            u32s.push(BigEndian::read_u32(chunk));
        }
    } else {
        // All chunks are aligned
        for chunk in bytes.chunks_exact(4) {
            u32s.push(BigEndian::read_u32(chunk));
        }
    }

    u32s
}

pub const fn cover_with_32(size: usize) -> usize {
    // (size + 31) / 32
    size.div_ceil(32)
}

#[inline]
fn find_nearest_time_index(time_table: &[u64], time: u64) -> usize {
    match time_table.binary_search(&time) {
        Ok(index) => index,
        Err(index) => index
            .saturating_sub(1)
            .min(time_table.len().saturating_sub(1)),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_get_int_value(handle: *mut c_void, time_table_idx: u64) -> u32 {
    let handle = unsafe { *{ handle as *mut vpiHandle } };
    let loaded_signal = get_signal_cache()
        .get(&(handle as vpiHandle))
        .unwrap()
        .signal
        .borrow();

    if let Some(off) = loaded_signal.get_offset(time_table_idx as u32) {
        let signal_v = loaded_signal.get_value_at(&off, 0);
        match signal_v {
            SignalValue::Binary(data, _bits) => {
                let words = bytes_to_u32s_be(data);
                let value = words[words.len() - 1] as i32;
                value as _
            }
            // If the value is a 4-value, which means it contains X or Z, we return 0 since X
            // state is not supported in wave_vpi.
            // TODO: consider support X state in wave_vpi?
            SignalValue::FourValue(_data, _bits) => 0,
            _ => todo!("{:#?}", signal_v),
        }
    } else {
        // No value found at time index 0, use default value: 0
        0
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_get_value_from_index(
    handle: *mut c_void,
    time_table_idx: u64,
    value_p: p_vpi_value,
) {
    let handle = unsafe { *{ handle as *mut vpiHandle } };
    let v_format = unsafe { value_p.read().format };

    let loaded_signal = get_signal_cache()
        .get(&(handle as vpiHandle))
        .unwrap()
        .signal
        .borrow();

    if let Some(off) = loaded_signal.get_offset(time_table_idx as u32) {
        let signal_v = loaded_signal.get_value_at(&off, 0);

        // TODO: improve performance?
        match signal_v {
            SignalValue::Binary(data, _bits) => {
                let words = bytes_to_u32s_be(data);
                // println!("data => {:?} ww => {:?}   {}", data, words, words[words.len() - 1]);

                match v_format as u32 {
                    vpiVectorVal => {
                        let mut vecvals = Vec::new();
                        for i in 0..words.len() {
                            vecvals.insert(
                                0,
                                t_vpi_vecval {
                                    aval: words[i] as i32,
                                    bval: 0,
                                },
                            );
                        }
                        let vecvals_box = vecvals.into_boxed_slice();
                        let vecvals_ptr = vecvals_box.as_ptr() as *mut t_vpi_vecval;
                        let _ = Box::into_raw(vecvals_box);
                        unsafe {
                            (*value_p).value.vector = vecvals_ptr;
                        }
                    }
                    vpiIntVal => {
                        let value = words[words.len() - 1] as i32;
                        unsafe {
                            (*value_p).value.integer = value;
                        }
                    }
                    vpiHexStrVal => {
                        let signal_bit_string =
                            loaded_signal.get_value_at(&off, 0).to_bit_string().unwrap();

                        let len = signal_bit_string.len();
                        let padding = (4 - (len % 4)) % 4;
                        let hex_len = (len + padding + 3) / 4;

                        let mut hex_chars = Vec::with_capacity(hex_len);
                        let bytes = signal_bit_string.as_bytes();

                        // Process with padding if needed
                        let mut idx = 0;
                        if padding > 0 {
                            let mut nibble = 0u8;
                            for i in 0..(4 - padding) {
                                nibble = (nibble << 1) | (bytes[i] - b'0');
                            }
                            hex_chars.push(if nibble < 10 {
                                b'0' + nibble
                            } else {
                                b'a' + nibble - 10
                            });
                            idx = 4 - padding;
                        }

                        // Process remaining 4-bit chunks
                        while idx < len {
                            let mut nibble = 0u8;
                            for i in 0..4 {
                                if idx + i < len {
                                    nibble = (nibble << 1) | (bytes[idx + i] - b'0');
                                }
                            }
                            hex_chars.push(if nibble < 10 {
                                b'0' + nibble
                            } else {
                                b'a' + nibble - 10
                            });
                            idx += 4;
                        }

                        let hex_string = unsafe { String::from_utf8_unchecked(hex_chars) };
                        let c_string = CString::new(hex_string).expect("CString::new failed");
                        let c_str_ptr = c_string.into_raw();
                        unsafe {
                            (*value_p).value.str_ = c_str_ptr as *mut PLI_BYTE8;
                        }
                    }
                    vpiBinStrVal => {
                        let signal_bit_string =
                            loaded_signal.get_value_at(&off, 0).to_bit_string().unwrap();
                        let c_string =
                            CString::new(signal_bit_string).expect("CString::new failed");
                        let c_str_ptr = c_string.into_raw();

                        unsafe {
                            (*value_p).value.str_ = c_str_ptr as *mut PLI_BYTE8;
                        }
                    }
                    _ => {
                        todo!("v_format => {}", v_format)
                    }
                };
            }
            SignalValue::FourValue(_data, bits) => {
                match v_format as u32 {
                    vpiVectorVal => {
                        let vec_len = cover_with_32(bits as usize);
                        let mut vecvals = Vec::new();
                        for _i in 0..vec_len {
                            vecvals.push(t_vpi_vecval { aval: 0, bval: 0 });
                        }
                        let vecvals_box = vecvals.into_boxed_slice();
                        let vecvals_ptr = vecvals_box.as_ptr() as *mut t_vpi_vecval;
                        let _ = Box::into_raw(vecvals_box);
                        unsafe {
                            (*value_p).value.vector = vecvals_ptr;
                        }
                    }
                    vpiIntVal => unsafe {
                        (*value_p).value.integer = 0;
                    },
                    vpiBinStrVal => {
                        let signal_bit_string =
                            loaded_signal.get_value_at(&off, 0).to_bit_string().unwrap();
                        let c_string =
                            CString::new(signal_bit_string).expect("CString::new failed");
                        let c_str_ptr = c_string.into_raw();

                        unsafe {
                            (*value_p).value.str_ = c_str_ptr as *mut PLI_BYTE8;
                        }
                    }
                    _ => {
                        todo!("v_format => {}", v_format)
                    }
                };
            }
            _ => panic!("{:#?}", signal_v),
        }
    } else {
        // No value found at time index 0, use default value: 0
        assert!(time_table_idx == 0);
        assert!(!loaded_signal.time_indices().is_empty());

        match v_format as u32 {
            vpiVectorVal => {
                let mut vecvals = Vec::new();
                vecvals.insert(0, t_vpi_vecval { aval: 0, bval: 0 });
                let vecvals_box = vecvals.into_boxed_slice();
                let vecvals_ptr = vecvals_box.as_ptr() as *mut t_vpi_vecval;
                let _ = Box::into_raw(vecvals_box);
                unsafe {
                    (*value_p).value.vector = vecvals_ptr;
                }
            }
            vpiIntVal => unsafe {
                (*value_p).value.integer = 0;
            },
            vpiHexStrVal => {
                let hex_string = String::from("0");
                let c_string = CString::new(hex_string).expect("CString::new failed");
                let c_str_ptr = c_string.into_raw();
                unsafe {
                    (*value_p).value.str_ = c_str_ptr as *mut PLI_BYTE8;
                }
            }
            vpiBinStrVal => {
                let bin_string = String::from("0");
                let c_string = CString::new(bin_string).expect("CString::new failed");
                let c_str_ptr = c_string.into_raw();
                unsafe {
                    (*value_p).value.str_ = c_str_ptr as *mut PLI_BYTE8;
                }
            }
            _ => {
                todo!("v_format => {}", v_format)
            }
        }
    }

    // println!("[wellen_vpi_get_value] handle is {:?} format is {:?} value is {:?} signal_v is {:?}", handle, v_format, signal_bit_string, signal_v);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_get_value(
    handle: *mut c_void,
    time: u64,
    value_p: p_vpi_value,
) {
    let time_table_idx = find_nearest_time_index(get_time_table(), time);
    unsafe {
        wellen_vpi_get_value_from_index(handle, time_table_idx as u64, value_p);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_get_value_str(
    handle: *mut c_void,
    time_table_idx: u64,
) -> *mut c_char {
    let handle = unsafe { *{ handle as *mut vpiHandle } };
    let loaded_signal = get_signal_cache()
        .get(&(handle as vpiHandle))
        .unwrap()
        .signal
        .borrow();
    let off = loaded_signal.get_offset(time_table_idx as u32);

    if let Some(off) = off {
        let signal_bit_string = loaded_signal.get_value_at(&off, 0).to_bit_string().unwrap();
        let c_string = CString::new(signal_bit_string).expect("CString::new failed");
        c_string.into_raw()
    } else {
        // No value found at time index 0, use default value: 0
        assert!(time_table_idx == 0);

        let c_string = CString::new("0").expect("CString::new failed");
        c_string.into_raw()
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_get(property: PLI_INT32, handle: *mut c_void) -> PLI_INT32 {
    let handle = unsafe { *{ handle as *mut vpiHandle } };
    let loaded_signal = get_signal_cache()
        .get(&(handle as vpiHandle))
        .unwrap()
        .signal
        .borrow();
    let first_indx = loaded_signal.get_first_time_idx().unwrap();
    let off = loaded_signal
        .get_offset(first_indx)
        .unwrap_or_else(|| panic!("failed to get offset, signal => {:?}", loaded_signal));
    let signal_v = loaded_signal.get_value_at(&off, 0);

    match property as u32 {
        vpiSize => signal_v.bits().unwrap() as PLI_INT32,
        _ => {
            todo!("property => {}", property)
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_get_str(
    property: PLI_INT32,
    handle: *mut c_void,
) -> *mut c_void {
    let handle = unsafe { *{ handle as *mut vpiHandle } };
    let var_type = get_signal_cache()
        .get(&(handle as vpiHandle))
        .unwrap()
        .var_type
        .borrow();

    let c_string = match property as u32 {
        vpiType => {
            match var_type {
                VarType::Reg => CString::new("vpiReg").unwrap(),
                VarType::Wire => CString::new("vpiNet").unwrap(),
                _ => {
                    todo!("{:#?}", var_type)
                } // TODO: vpiRegArray vpiNetArray vpiMemory
            }
        }
        _ => {
            todo!("property => {}", property)
        }
    };

    c_string.into_raw() as *mut c_void
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_iterate(
    _type: PLI_INT32,
    refHandle: *mut c_void,
) -> *mut c_void {
    let hier = get_hierarchy();
    let scopes = hier.scopes();

    if refHandle.is_null() {
        match _type as u32 {
            vpiModule => {
                let r = scopes.into_iter().find_map(|scope_ref| {
                    let scope = &hier[scope_ref];
                    let full_name = scope.full_name(hier);
                    if scope.scope_type() == ScopeType::Module {
                        let scope_name = scope.name(hier);
                        if scope_name.starts_with("$") || scope_name.ends_with("_pkg") {
                            None
                        } else {
                            log::debug!(
                                "{:#?} scope_ref => {:?} name => {} full_name => {}",
                                scope,
                                scope_ref,
                                scope_name,
                                full_name
                            );
                            Some(scope_name)
                        }
                    } else {
                        None
                    }
                });
                log::debug!("iterate name => {}", r.unwrap());
            }
            _ => {
                panic!("type => {}", _type)
            }
        }

        panic!()
    } else {
        todo!()
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn wellen_get_time_from_index(index: u64) -> u64 {
    let time_table = get_time_table();
    time_table[index as usize]
}

#[unsafe(no_mangle)]
pub extern "C" fn wellen_get_index_from_time(time: u64) -> u64 {
    let time_table = get_time_table();
    find_nearest_time_index(time_table, time) as u64
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_get_max_index() -> u64 {
    let time_table = get_time_table();
    (time_table.len() - 1) as u64
}

/// Get time precision from waveform file
/// Returns the exponent (e.g., -9 for ns, -12 for ps)
#[unsafe(no_mangle)]
pub extern "C" fn wellen_get_time_precision() -> i32 {
    let hierarchy = get_hierarchy();
    if let Some(timescale) = hierarchy.timescale() {
        let base_exp = timescale.unit.to_exponent().unwrap_or(-9) as i32;
        // Adjust for factor: 1 -> 0, 10 -> 1, 100 -> 2
        let factor_adj: i32 = match timescale.factor {
            1 => 0,
            10 => 1,
            100 => 2,
            _ => 0,
        };
        base_exp + factor_adj
    } else {
        log::warn!("[wave_vpi] Wave file has no timescale info, defaulting to ns (-9)");
        -9
    }
}

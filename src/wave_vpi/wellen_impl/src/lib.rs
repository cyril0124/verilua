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
use std::ptr::addr_of;
use std::time::{Instant, UNIX_EPOCH};
use wellen::*;

mod vpi_user;
use vpi_user::*;

#[allow(non_camel_case_types)]
type vpiHandle = SignalRef;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FileModifiedInfo {
    size: u64,
    time: u64,
}

/// Lightweight metadata aggregating small caches into a single file.
#[derive(Debug, Serialize, Deserialize)]
struct WaveVpiMeta {
    modified: FileModifiedInfo,
    sigref_count: usize,
    sigref: HashMap<String, SignalRef>,
    sigref_null: HashSet<String>,
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

const META_FILE: &str = ".wave_vpi.meta.yaml";
const SIGNAL_CACHE_FILE: &str = ".wave_vpi.signal.bin";

static mut TIME_TABLE: Option<UnsafeCell<Vec<u64>>> = None;
static mut HIERARCHY: Option<UnsafeCell<Hierarchy>> = None;
static mut WAVE_SOURCE: Option<UnsafeCell<SignalSource>> = None;
static mut WAVE_FILE_MODIFIED: Option<FileModifiedInfo> = None;

static mut SIGNAL_REF_CACHE: Option<UnsafeCell<HashMap<String, SignalRef>>> = None;
static mut SIGNAL_REF_CACHE_NULL: Option<UnsafeCell<HashSet<String>>> = None;
static mut SIGNAL_CACHE: Option<UnsafeCell<HashMap<SignalRef, SignalInfo>>> = None;
static mut SIGNAL_NAME_CACHE: Option<UnsafeCell<HashMap<SignalRef, CString>>> = None;
static mut HAS_NEWLY_ADD_SIGNAL_REF: bool = false;
// ScopeRef -> stable C handle storage.
// We keep module handles stable across scans to avoid returning dangling pointers.
static mut MODULE_HANDLE_CACHE: Option<UnsafeCell<HashMap<ScopeRef, *mut WellenModuleHandle>>> = None;
// Raw handle address -> ScopeRef reverse lookup for iterate(ref) / get_str(ref).
static mut MODULE_HANDLE_PTR_MAP: Option<UnsafeCell<HashMap<usize, ScopeRef>>> = None;
// Live iterator addresses returned to C++. Used to validate and reclaim iterators.
static mut ITERATOR_HANDLE_PTR_SET: Option<UnsafeCell<HashSet<usize>>> = None;

struct WellenModuleHandle {
    name: CString,
}

#[derive(Clone, Copy)]
enum WellenIteratorItem {
    Module(ScopeRef),
    Signal(*mut c_void),
}

struct WellenModuleIterator {
    items: Vec<WellenIteratorItem>,
    index: usize,
}

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
fn get_signal_name_cache() -> &'static mut HashMap<SignalRef, CString> {
    unsafe {
        match SIGNAL_NAME_CACHE {
            Some(ref mut signal_name_cache) => &mut *signal_name_cache.get(),
            None => {
                panic!(
                    "SIGNAL_NAME_CACHE is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn try_get_signal_name_cache() -> Option<&'static mut HashMap<SignalRef, CString>> {
    unsafe {
        match SIGNAL_NAME_CACHE {
            Some(_) => Some(get_signal_name_cache()),
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

#[inline(always)]
fn get_module_handle_cache() -> &'static mut HashMap<ScopeRef, *mut WellenModuleHandle> {
    unsafe {
        match MODULE_HANDLE_CACHE {
            Some(ref mut module_handle_cache) => &mut *module_handle_cache.get(),
            None => {
                panic!(
                    "MODULE_HANDLE_CACHE is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn try_get_module_handle_cache() -> Option<&'static mut HashMap<ScopeRef, *mut WellenModuleHandle>>
{
    unsafe {
        match MODULE_HANDLE_CACHE {
            Some(_) => Some(get_module_handle_cache()),
            None => None,
        }
    }
}

#[inline(always)]
fn get_module_handle_ptr_map() -> &'static mut HashMap<usize, ScopeRef> {
    unsafe {
        match MODULE_HANDLE_PTR_MAP {
            Some(ref mut module_handle_ptr_map) => &mut *module_handle_ptr_map.get(),
            None => {
                panic!(
                    "MODULE_HANDLE_PTR_MAP is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn try_get_module_handle_ptr_map() -> Option<&'static mut HashMap<usize, ScopeRef>> {
    unsafe {
        match MODULE_HANDLE_PTR_MAP {
            Some(_) => Some(get_module_handle_ptr_map()),
            None => None,
        }
    }
}

#[inline(always)]
fn get_iterator_handle_ptr_set() -> &'static mut HashSet<usize> {
    unsafe {
        match ITERATOR_HANDLE_PTR_SET {
            Some(ref mut iterator_handle_ptr_set) => &mut *iterator_handle_ptr_set.get(),
            None => {
                panic!(
                    "ITERATOR_HANDLE_PTR_SET is not initialized! Please call `wave_vpi::wellen_initialize` first."
                )
            }
        }
    }
}

#[inline(always)]
fn try_get_iterator_handle_ptr_set() -> Option<&'static mut HashSet<usize>> {
    unsafe {
        match ITERATOR_HANDLE_PTR_SET {
            Some(_) => Some(get_iterator_handle_ptr_set()),
            None => None,
        }
    }
}

#[inline(always)]
fn get_or_create_module_handle(scope_ref: ScopeRef) -> *mut WellenModuleHandle {
    if let Some(cached) = get_module_handle_cache().get(&scope_ref) {
        return *cached;
    }

    // Materialize a C-stable module object once, then reuse it by scope id.
    let hierarchy = get_hierarchy();
    let scope = &hierarchy[scope_ref];
    let handle = Box::new(WellenModuleHandle {
        name: CString::new(scope.name(hierarchy)).expect("scope name contains NUL"),
    });
    let handle_ptr = Box::into_raw(handle);
    get_module_handle_cache().insert(scope_ref, handle_ptr);
    get_module_handle_ptr_map().insert(handle_ptr as usize, scope_ref);
    handle_ptr
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

/// # Safety
/// `filename` must be a valid, non-null, null-terminated C string.
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

    // Load meta file and check wave file freshness.
    let mut use_cached_data = false;
    let metadata = fs::metadata(filename).expect("Failed to get file metadata");
    let file_size = metadata.size();
    let modified_timestamp = metadata
        .modified()
        .expect("Failed to get modified time")
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    // Store for finalize to write back.
    unsafe {
        WAVE_FILE_MODIFIED = Some(FileModifiedInfo {
            size: file_size,
            time: modified_timestamp,
        });
    }

    let t0 = Instant::now();
    let cached_meta: Option<WaveVpiMeta> = File::open(META_FILE).ok().and_then(|f| {
        let reader = BufReader::new(f);
        serde_yaml::from_reader(reader).ok()
    });
    if cached_meta.is_some() {
        log::info!(
            "[wave_vpi::wellen_initialize] read {} in {:.3}s",
            META_FILE,
            t0.elapsed().as_secs_f64()
        );
    }

    if let Some(ref meta) = cached_meta {
        if meta.modified.time == modified_timestamp && meta.modified.size == file_size {
            // Wave file unchanged — check sigref count threshold.
            log::info!(
                "[wave_vpi::wellen_initialize] sigref_count: {} threshold: {}",
                meta.sigref_count,
                SIGNAL_REF_COUNT_THRESHOLD
            );
            if meta.sigref_count >= SIGNAL_REF_COUNT_THRESHOLD {
                use_cached_data = true;
            }
        } else {
            log::info!(
                "[wave_vpi::wellen_initialize] modified_timestamp: last({}) curr({})  file_size: last({}) curr({})",
                meta.modified.time,
                modified_timestamp,
                meta.modified.size,
                file_size
            );
        }
    } else {
        log::info!(
            "[wave_vpi::wellen_initialize] modified_timestamp(new): {}  file_size(new): {}",
            modified_timestamp,
            file_size
        );
    }

    log::info!(
        "[wave_vpi::wellen_initialize] use_cached_data => {} {}",
        use_cached_data,
        if use_cached_data { "✅" } else { "❌" }
    );

    unsafe {
        if try_get_signal_ref_cache().is_none() {
            if use_cached_data {
                let meta = cached_meta.as_ref().unwrap();
                log::info!(
                    "[wave_vpi::wellen_initialize] loading sigref cache from meta ({} entries, {} null)",
                    meta.sigref.len(),
                    meta.sigref_null.len()
                );
                SIGNAL_REF_CACHE = Some(UnsafeCell::new(meta.sigref.clone()));
                SIGNAL_REF_CACHE_NULL = Some(UnsafeCell::new(meta.sigref_null.clone()));
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
                let t0 = Instant::now();
                let _file = File::open(SIGNAL_CACHE_FILE);
                if let Ok(file) = _file {
                    // Use mmap for zero-copy reading, then deserialize from the mapped bytes.
                    let mmap = memmap2::Mmap::map(&file);
                    match mmap {
                        Ok(mmap) => match rmp_serde::from_slice::<HashMap<SignalRef, SignalInfo>>(
                            &mmap,
                        ) {
                            Ok(cache) => {
                                SIGNAL_CACHE = Some(UnsafeCell::new(cache));
                                log::info!(
                                    "[wave_vpi::wellen_initialize] read {} in {:.3}s (mmap)",
                                    SIGNAL_CACHE_FILE,
                                    t0.elapsed().as_secs_f64()
                                );
                            }
                            Err(e) => {
                                log::warn!(
                                    "[wave_vpi::wellen_initialize] Failed to deserialize {}: {} (cache may be stale, rebuilding)",
                                    SIGNAL_CACHE_FILE,
                                    e
                                );
                                SIGNAL_CACHE = Some(UnsafeCell::new(HashMap::new()));
                            }
                        },
                        Err(e) => {
                            log::warn!(
                                "[wave_vpi::wellen_initialize] Failed to mmap {}: {}",
                                SIGNAL_CACHE_FILE,
                                e
                            );
                            SIGNAL_CACHE = Some(UnsafeCell::new(HashMap::new()));
                        }
                    }
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

        if try_get_signal_name_cache().is_none() {
            SIGNAL_NAME_CACHE = Some(UnsafeCell::new(HashMap::new()));
        }

        if try_get_module_handle_cache().is_none() {
            MODULE_HANDLE_CACHE = Some(UnsafeCell::new(HashMap::new()));
        }
        if try_get_module_handle_ptr_map().is_none() {
            MODULE_HANDLE_PTR_MAP = Some(UnsafeCell::new(HashMap::new()));
        }
        if try_get_iterator_handle_ptr_set().is_none() {
            ITERATOR_HANDLE_PTR_SET = Some(UnsafeCell::new(HashSet::new()));
        }
    }

    log::info!("[wave_vpi::wellen_initialize] init finish...");
}

/// # Safety
/// Must be called after `wellen_initialize` and only once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_finalize() {
    log::info!("[wave_vpi::wellen_finalize] ... ");

    let signal_ref_cache = get_signal_ref_cache();
    if signal_ref_cache.len() >= SIGNAL_REF_COUNT_THRESHOLD {
        unsafe {
            if HAS_NEWLY_ADD_SIGNAL_REF {
                log::info!("[wave_vpi::wellen_finalize] saving cache files");

                // Save meta file (lightweight: mtime + sigref + sigref_null).
                if let Some(modified) = (*addr_of!(WAVE_FILE_MODIFIED)).clone() {
                    let t0 = Instant::now();
                    let sigref = get_signal_ref_cache();
                    let sigref_null = get_signal_ref_cache_null();
                    let meta = WaveVpiMeta {
                        modified,
                        sigref_count: sigref.len(),
                        sigref: sigref.clone(),
                        sigref_null: sigref_null.clone(),
                    };
                    let file = File::create(META_FILE).unwrap();
                    let writer = BufWriter::new(file);
                    serde_yaml::to_writer(writer, &meta).unwrap();
                    log::info!(
                        "[wave_vpi::wellen_finalize] wrote {} in {:.3}s",
                        META_FILE,
                        t0.elapsed().as_secs_f64()
                    );
                }

                // Save signal cache (large binary format via rmp-serde + BufWriter).
                let t0 = Instant::now();
                let signal_cache = get_signal_cache();
                let file = File::create(SIGNAL_CACHE_FILE).unwrap();
                let mut writer = BufWriter::new(file);
                rmp_serde::encode::write(&mut writer, signal_cache).unwrap();
                log::info!(
                    "[wave_vpi::wellen_finalize] wrote {} in {:.3}s",
                    SIGNAL_CACHE_FILE,
                    t0.elapsed().as_secs_f64()
                );
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

    unsafe {
        if let Some(ref cache_cell) = SIGNAL_NAME_CACHE {
            (&mut *cache_cell.get()).clear();
        }

        if let Some(ref cache_cell) = ITERATOR_HANDLE_PTR_SET {
            // Reclaim any iterator not fully exhausted by caller.
            let iterator_ptrs: Vec<usize> = (&*cache_cell.get()).iter().copied().collect();
            for ptr in iterator_ptrs {
                let _ = Box::from_raw(ptr as *mut WellenModuleIterator);
            }
            (&mut *cache_cell.get()).clear();
        }

        if let Some(ref cache_cell) = MODULE_HANDLE_CACHE {
            // Reclaim module handles cached for C-side pointer stability.
            let module_ptrs: Vec<*mut WellenModuleHandle> = (&*cache_cell.get()).values().copied().collect();
            for ptr in module_ptrs {
                let _ = Box::from_raw(ptr);
            }
            (&mut *cache_cell.get()).clear();
        }

        if let Some(ref cache_cell) = MODULE_HANDLE_PTR_MAP {
            (&mut *cache_cell.get()).clear();
        }
    }
}

/// # Safety
/// `name` must be a valid, non-null, null-terminated C string.
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
        // SignalRef may be shared by aliased names (e.g. parent net vs child port).
        // Always refresh to the currently queried full path so hierarchy wildcard/path
        // matching remains stable for the active traversal context.
        get_signal_name_cache().insert(*id, CString::new(name).expect("signal name contains NUL"));
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
        let var_ref_opt = &hierarchy.lookup_var(path_slice, signal_name);
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
        let loaded = get_wave_source().load_signals(&ids, hierarchy, LOAD_OPTS.multi_thread);
        let (loaded_id, loaded_signal) = loaded.into_iter().next().unwrap();
        assert_eq!(loaded_id, ids[0], "Failed to load signal, name: {}", name);

        get_signal_cache().insert(
            loaded_id,
            SignalInfo {
                signal: loaded_signal,
                var_type: var.var_type(),
            },
        );
        get_signal_name_cache().insert(
            loaded_id,
            CString::new(name).expect("signal name contains NUL"),
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
    let capacity = len.div_ceil(4);
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

/// Convert a bit string (may contain 'x'/'z') to a hex string.
/// If any bit in a 4-bit nibble is 'x', the nibble becomes 'x'.
/// If any bit is 'z' (and none is 'x'), the nibble becomes 'z'.
fn bit_string_to_hex_with_xz(bit_str: &str) -> String {
    let len = bit_str.len();
    if len == 0 {
        return String::from("0");
    }
    let padding = (4 - (len % 4)) % 4;
    let padded: String = "0".repeat(padding) + bit_str;
    let mut hex = String::with_capacity(padded.len() / 4);

    for chunk in padded.as_bytes().chunks(4) {
        let has_x = chunk.contains(&b'x');
        let has_z = chunk.contains(&b'z');
        if has_x {
            hex.push('x');
        } else if has_z {
            hex.push('z');
        } else {
            let mut nibble = 0u8;
            for &b in chunk {
                nibble = (nibble << 1) | (b - b'0');
            }
            hex.push(if nibble < 10 {
                (b'0' + nibble) as char
            } else {
                (b'a' + nibble - 10) as char
            });
        }
    }
    hex
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

/// # Safety
/// `handle` must be a valid pointer obtained from `wellen_vpi_handle_by_name`.
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

/// # Safety
/// `handle` must be a valid pointer. `value_p` must point to a valid `t_vpi_value`.
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
                        for word in &words {
                            vecvals.insert(
                                0,
                                t_vpi_vecval {
                                    aval: *word as i32,
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
                        let hex_len = (len + padding).div_ceil(4);

                        let mut hex_chars = Vec::with_capacity(hex_len);
                        let bytes = signal_bit_string.as_bytes();

                        // Process with padding if needed
                        let mut idx = 0;
                        if padding > 0 {
                            let mut nibble = 0u8;
                            for byte in bytes.iter().take(4 - padding) {
                                nibble = (nibble << 1) | (byte - b'0');
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
                    vpiDecStrVal => {
                        // Binary (2-state): no X/Z possible, convert integer to decimal
                        let value = words[words.len() - 1] as u64;
                        let dec_string = value.to_string();
                        let c_string =
                            CString::new(dec_string).expect("CString::new failed");
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
                    vpiHexStrVal => {
                        let signal_bit_string =
                            loaded_signal.get_value_at(&off, 0).to_bit_string().unwrap();
                        let hex_string = bit_string_to_hex_with_xz(&signal_bit_string);
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
                    vpiDecStrVal => {
                        // FourValue (4-state): check for X/Z in hex representation
                        let signal_bit_string =
                            loaded_signal.get_value_at(&off, 0).to_bit_string().unwrap();
                        let hex_string = bit_string_to_hex_with_xz(&signal_bit_string);
                        let dec_string = if hex_string.contains('x') || hex_string.contains('z') {
                            "x".to_string()
                        } else {
                            match u128::from_str_radix(&hex_string, 16) {
                                Ok(value) => value.to_string(),
                                Err(_) => "x".to_string(),
                            }
                        };
                        let c_string =
                            CString::new(dec_string).expect("CString::new failed");
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
            vpiDecStrVal => {
                let dec_string = String::from("0");
                let c_string = CString::new(dec_string).expect("CString::new failed");
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

/// # Safety
/// `handle` must be a valid pointer. `value_p` must point to a valid `t_vpi_value`.
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

/// # Safety
/// `handle` must be a valid pointer obtained from `wellen_vpi_handle_by_name`.
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

/// # Safety
/// `handle` must be a valid pointer obtained from `wellen_vpi_handle_by_name`.
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

/// # Safety
/// `handle` must be a valid pointer obtained from `wellen_vpi_handle_by_name`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_get_str(
    property: PLI_INT32,
    handle: *mut c_void,
) -> *mut c_void {
    let handle_addr = handle as usize;
    // First check module handle registry. Signal handles and module handles are both opaque pointers.
    if get_module_handle_ptr_map().contains_key(&handle_addr) {
        let module_handle = unsafe { &*(handle as *const WellenModuleHandle) };
        match property as u32 {
            vpiName => module_handle.name.as_ptr() as *mut c_void,
            // Def-name is intentionally FSDB-only in current policy.
            vpiDefName => std::ptr::null_mut(),
            vpiType => c"vpiModule".as_ptr() as *mut c_void,
            _ => std::ptr::null_mut(),
        }
    } else {
        let handle = unsafe { *{ handle as *mut vpiHandle } };
        match property as u32 {
            vpiName => get_signal_name_cache()
                .get(&(handle as vpiHandle))
                .map(|name| name.as_ptr() as *mut c_void)
                .unwrap_or(std::ptr::null_mut()),
            vpiType => {
                let var_type = get_signal_cache()
                    .get(&(handle as vpiHandle))
                    .unwrap()
                    .var_type
                    .borrow();
                match var_type {
                    VarType::Wire => c"vpiNet".as_ptr() as *mut c_void,
                    VarType::Reg | VarType::Logic => c"vpiReg".as_ptr() as *mut c_void,
                    _ => c"vpiReg".as_ptr() as *mut c_void,
                }
            }
            _ => std::ptr::null_mut(),
        }
    }
}

#[inline]
fn is_valid_top_module_scope(hierarchy: &Hierarchy, scope_ref: ScopeRef) -> bool {
    let scope = &hierarchy[scope_ref];
    if scope.scope_type() != ScopeType::Module {
        return false;
    }

    let scope_name = scope.name(hierarchy);
    !(scope_name.starts_with('$') || scope_name.ends_with("_pkg"))
}

#[inline]
fn collect_module_scopes(_type: PLI_INT32, refHandle: *mut c_void) -> Vec<ScopeRef> {
    if _type as u32 != vpiModule {
        return Vec::new();
    }

    let hierarchy = get_hierarchy();
    if refHandle.is_null() {
        // vpi_iterate(vpiModule, NULL): top-level modules only.
        hierarchy
            .scopes()
            .filter(|scope_ref| is_valid_top_module_scope(hierarchy, *scope_ref))
            .collect()
    } else {
        // vpi_iterate(vpiModule, module_handle): direct module children.
        let handle_addr = refHandle as usize;
        let scope_ref = match get_module_handle_ptr_map().get(&handle_addr).copied() {
            Some(scope_ref) => scope_ref,
            None => return Vec::new(),
        };

        hierarchy[scope_ref]
            .scopes(hierarchy)
            .filter(|child_scope_ref| hierarchy[*child_scope_ref].scope_type() == ScopeType::Module)
            .collect()
    }
}

#[inline]
fn map_var_type_to_vpi_iter_type(var_type: VarType) -> PLI_INT32 {
    match var_type {
        VarType::Wire => vpiNet as PLI_INT32,
        VarType::SparseArray => vpiMemory as PLI_INT32,
        _ => vpiReg as PLI_INT32,
    }
}

#[inline]
fn collect_signal_handles(_type: PLI_INT32, refHandle: *mut c_void) -> Vec<*mut c_void> {
    if _type as u32 != vpiNet && _type as u32 != vpiReg && _type as u32 != vpiMemory {
        return Vec::new();
    }
    if refHandle.is_null() {
        return Vec::new();
    }

    let handle_addr = refHandle as usize;
    let scope_ref = match get_module_handle_ptr_map().get(&handle_addr).copied() {
        Some(scope_ref) => scope_ref,
        None => return Vec::new(),
    };

    let hierarchy = get_hierarchy();
    let mut signal_handles = Vec::new();
    let mut visited_signal_refs = HashSet::new();
    for var_ref in hierarchy[scope_ref].vars(hierarchy) {
        let var = &hierarchy[var_ref];
        if map_var_type_to_vpi_iter_type(var.var_type()) != _type {
            continue;
        }

        let signal_ref = var.signal_ref();
        if !visited_signal_refs.insert(signal_ref) {
            continue;
        }

        let full_name = var.full_name(hierarchy);
        let full_name_cstr = CString::new(full_name.as_str()).expect("signal name contains NUL");
        let signal_handle = unsafe { wellen_vpi_handle_by_name(full_name_cstr.as_ptr()) };
        if signal_handle.is_null() {
            continue;
        }
        signal_handles.push(signal_handle);
    }
    signal_handles
}

/// # Safety
/// `refHandle` must be a valid pointer or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_iterate(
    _type: PLI_INT32,
    refHandle: *mut c_void,
) -> *mut c_void {
    let items = if _type as u32 == vpiModule {
        collect_module_scopes(_type, refHandle)
            .into_iter()
            .map(WellenIteratorItem::Module)
            .collect::<Vec<_>>()
    } else if _type as u32 == vpiNet || _type as u32 == vpiReg || _type as u32 == vpiMemory {
        collect_signal_handles(_type, refHandle)
            .into_iter()
            .map(WellenIteratorItem::Signal)
            .collect::<Vec<_>>()
    } else {
        Vec::new()
    };

    if items.is_empty() {
        return std::ptr::null_mut();
    }

    let iterator = Box::new(WellenModuleIterator { items, index: 0 });
    let iterator_ptr = Box::into_raw(iterator);
    // Track iterator ownership so invalid pointers can be rejected in wellen_vpi_scan.
    get_iterator_handle_ptr_set().insert(iterator_ptr as usize);
    iterator_ptr as *mut c_void
}

/// # Safety
/// `iterator` must be a valid pointer returned by `wellen_vpi_iterate`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wellen_vpi_scan(iterator: *mut c_void) -> *mut c_void {
    if iterator.is_null() {
        return std::ptr::null_mut();
    }

    let iterator_addr = iterator as usize;
    if !get_iterator_handle_ptr_set().contains(&iterator_addr) {
        return std::ptr::null_mut();
    }

    let iter = unsafe { &mut *(iterator as *mut WellenModuleIterator) };
    if iter.index >= iter.items.len() {
        // Match VPI behavior: once exhausted, iterator is consumed and released.
        get_iterator_handle_ptr_set().remove(&iterator_addr);
        let _ = unsafe { Box::from_raw(iterator as *mut WellenModuleIterator) };
        return std::ptr::null_mut();
    }

    let item = iter.items[iter.index];
    iter.index += 1;

    match item {
        WellenIteratorItem::Module(scope_ref) => get_or_create_module_handle(scope_ref) as *mut c_void,
        WellenIteratorItem::Signal(handle) => handle,
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

/// # Safety
/// Must be called after `wellen_initialize`.
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

use super::*;
use std::collections::HashSet;

#[cfg(feature = "hierarchy_cache")]
use std::sync::{Arc, RwLock};

#[cfg(feature = "hierarchy_cache")]
use once_cell::sync::Lazy;

type HierarchyItemCallback = unsafe extern "C" fn(
    *const c_char,
    *const c_char,
    *const c_char,
    *const c_char,
    PLI_INT32,
    PLI_INT32,
);

const HIER_ERR_MODULE_NAME_ONLY_FSDB: &[u8] =
    b"[get_hierarchy] `module_name` is only supported for FSDB waveform in wave_vpi backend.\0";
const HIER_ERR_SHOW_DEF_NAME_ONLY_FSDB: &[u8] =
    b"[print_hierarchy] `show_def_name` is only supported for FSDB waveform in wave_vpi backend.\0";
const HIER_ERR_INTERNAL_NULL_CB: &[u8] =
    b"[print_hierarchy/get_hierarchy] vpiml_collect_hierarchy failed: callback is null.\0";
const HIER_ERR_UNSUPPORTED_DPI: &[u8] =
    b"[print_hierarchy/get_hierarchy] hierarchy collection is not supported in DPI mode.\0";

#[cfg(feature = "hierarchy_cache")]
const HIERARCHY_CACHE_DEFAULT_PATH: &str = ".verilua_hierarchy_cache";
#[cfg(feature = "hierarchy_cache")]
const HIERARCHY_CACHE_MAGIC: u32 = 0x56484932; // "VHI2" (Verilua HIErarchy v2, with bitwidth)
#[cfg(feature = "hierarchy_cache")]
const HIERARCHY_CACHE_FIXED_HEADER_SIZE: usize = 16; // magic(4) + mtime(8) + count(4)

#[cfg(feature = "hierarchy_cache")]
static HIERARCHY_CACHE: Lazy<RwLock<Option<Arc<Vec<HierarchyEntry>>>>> =
    Lazy::new(|| RwLock::new(None));

#[inline]
fn err_ptr(msg: &'static [u8]) -> *const c_char {
    msg.as_ptr() as *const c_char
}

// Flattened hierarchy item shared with Lua-side rendering.
#[derive(Clone)]
struct HierarchyEntry {
    full_path: String,
    module_name: Option<String>,
    sig_type: Option<String>,
    level: PLI_INT32,
    /// Signal bit width. -1 for module scopes, >=1 for leaf signals (net/reg/memory).
    bitwidth: PLI_INT32,
}

// ────────────────────────────────────────────────────────────────────────────────
// Hierarchy cache: mtime detection + file persistence
// ────────────────────────────────────────────────────────────────────────────────

#[cfg(feature = "hierarchy_cache")]
fn get_file_mtime(path: &str) -> Option<u64> {
    let metadata = std::fs::metadata(path).ok()?;
    let modified = metadata.modified().ok()?;
    Some(
        modified
            .duration_since(std::time::UNIX_EPOCH)
            .ok()?
            .as_secs(),
    )
}

#[cfg(feature = "hierarchy_cache")]
fn get_source_path() -> Option<String> {
    if cfg!(feature = "wave_vpi") {
        std::env::var("VERILUA_WAVEFORM_FILE").ok()
    } else {
        let exe_path = std::fs::read_link("/proc/self/exe").ok()?;
        Some(exe_path.to_string_lossy().into_owned())
    }
}

#[cfg(feature = "hierarchy_cache")]
fn get_cache_file_path() -> String {
    std::env::var("VERILUA_HIERARCHY_CACHE_FILE")
        .unwrap_or_else(|_| HIERARCHY_CACHE_DEFAULT_PATH.to_string())
}

#[cfg(feature = "hierarchy_cache")]
fn save_cache(
    path: &str,
    entries: &[HierarchyEntry],
    source_mtime: Option<u64>,
    source_path: Option<&str>,
) -> std::io::Result<()> {
    use std::io::Write;
    let file = std::fs::File::create(path)?;
    let mut w = std::io::BufWriter::new(file);

    // Fixed header: magic(4) + mtime(8) + count(4)
    w.write_all(&HIERARCHY_CACHE_MAGIC.to_le_bytes())?;
    let mtime_val = source_mtime.unwrap_or(u64::MAX);
    w.write_all(&mtime_val.to_le_bytes())?;
    w.write_all(&(entries.len() as u32).to_le_bytes())?;

    // Source path (length-prefixed, allows cache identity validation)
    write_len_prefixed_str(&mut w, source_path.unwrap_or(""))?;

    for entry in entries {
        write_len_prefixed_str(&mut w, &entry.full_path)?;
        write_len_prefixed_opt_str(&mut w, entry.module_name.as_deref())?;
        write_len_prefixed_opt_str(&mut w, entry.sig_type.as_deref())?;
        w.write_all(&entry.level.to_le_bytes())?;
        w.write_all(&entry.bitwidth.to_le_bytes())?;
    }
    w.flush()
}

#[cfg(feature = "hierarchy_cache")]
fn write_len_prefixed_str(w: &mut impl std::io::Write, s: &str) -> std::io::Result<()> {
    if s.len() > u16::MAX as usize {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "hierarchy cache: string too long for u16 length prefix",
        ));
    }
    w.write_all(&(s.len() as u16).to_le_bytes())?;
    w.write_all(s.as_bytes())
}

#[cfg(feature = "hierarchy_cache")]
fn write_len_prefixed_opt_str(w: &mut impl std::io::Write, s: Option<&str>) -> std::io::Result<()> {
    match s {
        Some(v) => write_len_prefixed_str(w, v),
        None => w.write_all(&0u16.to_le_bytes()),
    }
}

#[cfg(feature = "hierarchy_cache")]
fn try_load_cache(
    path: &str,
    current_mtime: Option<u64>,
    current_source_path: Option<&str>,
) -> Option<Vec<HierarchyEntry>> {
    use memmap2::MmapOptions;

    let file = std::fs::File::open(path).ok()?;
    let mmap = unsafe { MmapOptions::new().map(&file).ok()? };
    let data: &[u8] = &mmap;

    if data.len() < HIERARCHY_CACHE_FIXED_HEADER_SIZE {
        return None;
    }

    // Parse fixed header: magic(4) + mtime(8) + count(4)
    let magic = u32::from_le_bytes(data[0..4].try_into().ok()?);
    if magic != HIERARCHY_CACHE_MAGIC {
        log::info!("[hierarchy_cache] Invalid magic in cache file, ignoring");
        return None;
    }
    let cached_mtime = u64::from_le_bytes(data[4..12].try_into().ok()?);
    let entry_count = u32::from_le_bytes(data[12..16].try_into().ok()?) as usize;

    // Parse source path from cache
    let mut pos = HIERARCHY_CACHE_FIXED_HEADER_SIZE;
    let cached_source_path = read_len_prefixed_string(data, &mut pos)?;

    // Source path identity check: reject cache if it was created for a different source.
    if !cached_source_path.is_empty()
        && let Some(current) = current_source_path
        && !current.is_empty()
        && cached_source_path != current
    {
        log::info!(
            "[hierarchy_cache] Cache source mismatch: cached='{}' current='{}'",
            cached_source_path,
            current
        );
        return None;
    }

    // Mtime staleness check
    if cached_mtime != u64::MAX
        && let Some(current) = current_mtime
        && cached_mtime != current
    {
        log::info!(
            "[hierarchy_cache] Cache stale: cached_mtime={} current_mtime={}",
            cached_mtime,
            current
        );
        return None;
    }

    // Parse entries from mmap'd bytes
    let mut entries = Vec::with_capacity(entry_count);
    for _ in 0..entry_count {
        let full_path = read_len_prefixed_string(data, &mut pos)?;

        let module_name_len = read_u16_le(data, &mut pos)? as usize;
        let module_name = if module_name_len > 0 {
            Some(read_string_at(data, &mut pos, module_name_len)?)
        } else {
            None
        };

        let sig_type_len = read_u16_le(data, &mut pos)? as usize;
        let sig_type = if sig_type_len > 0 {
            Some(read_string_at(data, &mut pos, sig_type_len)?)
        } else {
            None
        };

        let level = read_i32_le(data, &mut pos)?;
        let bitwidth = read_i32_le(data, &mut pos)?;
        entries.push(HierarchyEntry {
            full_path,
            module_name,
            sig_type,
            level,
            bitwidth,
        });
    }

    log::info!(
        "[hierarchy_cache] Loaded {} entries from file: {}",
        entries.len(),
        path
    );
    Some(entries)
}

#[cfg(feature = "hierarchy_cache")]
fn read_u16_le(data: &[u8], pos: &mut usize) -> Option<u16> {
    let v = u16::from_le_bytes(data.get(*pos..*pos + 2)?.try_into().ok()?);
    *pos += 2;
    Some(v)
}

#[cfg(feature = "hierarchy_cache")]
fn read_i32_le(data: &[u8], pos: &mut usize) -> Option<PLI_INT32> {
    let v = PLI_INT32::from_le_bytes(data.get(*pos..*pos + 4)?.try_into().ok()?);
    *pos += 4;
    Some(v)
}

#[cfg(feature = "hierarchy_cache")]
fn read_string_at(data: &[u8], pos: &mut usize, len: usize) -> Option<String> {
    let s = std::str::from_utf8(data.get(*pos..*pos + len)?)
        .ok()?
        .to_string();
    *pos += len;
    Some(s)
}

#[cfg(feature = "hierarchy_cache")]
fn read_len_prefixed_string(data: &[u8], pos: &mut usize) -> Option<String> {
    let len = read_u16_le(data, pos)? as usize;
    read_string_at(data, pos, len)
}

#[cfg(feature = "hierarchy_cache")]
fn get_or_init_hierarchy_cache() -> Arc<Vec<HierarchyEntry>> {
    // Fast path: already cached in memory.
    if let Some(entries) = HIERARCHY_CACHE.read().unwrap().as_ref() {
        return Arc::clone(entries);
    }

    let cache_path = get_cache_file_path();
    let source_path = get_source_path();
    let current_mtime = source_path.as_deref().and_then(get_file_mtime);

    // Try loading from file (if not stale).
    if let Some(entries) = try_load_cache(&cache_path, current_mtime, source_path.as_deref()) {
        let arc = Arc::new(entries);
        *HIERARCHY_CACHE.write().unwrap() = Some(Arc::clone(&arc));
        return arc;
    }

    // File missing/stale/corrupt: perform full VPI traversal.
    let collected = Arc::new(collect_hierarchy_entries(0));
    let mut guard = HIERARCHY_CACHE.write().unwrap();
    // Double-check after acquiring write lock.
    if let Some(entries) = guard.as_ref() {
        return Arc::clone(entries);
    }
    *guard = Some(Arc::clone(&collected));

    // Persist to file for next run.
    if let Err(e) = save_cache(&cache_path, &collected, current_mtime, source_path.as_deref()) {
        log::warn!("[hierarchy_cache] Failed to save cache file: {}", e);
    } else {
        log::info!(
            "[hierarchy_cache] Saved {} entries to file: {}",
            collected.len(),
            cache_path
        );
    }

    collected
}

fn push_hierarchy_entry(
    entries: &mut Vec<HierarchyEntry>,
    seen_paths: &mut HashSet<String>,
    full_path: String,
    module_name: Option<String>,
    sig_type: Option<String>,
    level: PLI_INT32,
    bitwidth: PLI_INT32,
) {
    // Merge module-scan + leaf-scan output into a unique full-path set.
    if !seen_paths.insert(full_path.clone()) {
        // Some backends may expose the same logical path via multiple aliases.
        // Keep the stronger signal type when a duplicate arrives later.
        if sig_type.as_deref() == Some("reg")
            && let Some(existing) = entries
                .iter_mut()
                .find(|entry| entry.full_path == full_path)
        {
            existing.sig_type = Some("reg".to_string());
        }
        return;
    }
    entries.push(HierarchyEntry {
        full_path,
        module_name,
        sig_type,
        level,
        bitwidth,
    });
}

fn vpiml_collect_hierarchy_recursive(
    module: vpiHandle,
    parent_path: &str,
    level: PLI_INT32,
    max_level: PLI_INT32,
    entries: &mut Vec<HierarchyEntry>,
    seen_paths: &mut HashSet<String>,
) {
    // max_level == 0 keeps legacy "no depth limit" behavior.
    if max_level != 0 && level > max_level {
        return;
    }

    let iter = unsafe { vpi_iterate(vpiModule as _, module) };
    if iter.is_null() {
        return;
    }

    loop {
        let child = unsafe { vpi_scan(iter) };
        if child.is_null() {
            break;
        }

        let child_name_ptr = unsafe { vpi_get_str(vpiName as _, child) } as *const c_char;
        let Some(child_name) = (unsafe { utils::c_char_to_str_opt(child_name_ptr) }) else {
            continue;
        };

        let full_path = if parent_path.is_empty() {
            child_name.to_string()
        } else {
            format!("{parent_path}.{child_name}")
        };
        let module_name_ptr = unsafe { vpi_get_str(vpiDefName as _, child) } as *const c_char;
        let module_name = unsafe { utils::c_char_to_str_opt(module_name_ptr) }
            .filter(|name| !name.is_empty())
            .map(ToString::to_string);
        push_hierarchy_entry(
            entries,
            seen_paths,
            full_path.clone(),
            module_name,
            None,
            level,
            -1, // module scopes have no bitwidth
        );

        // Collect leaf objects under this module node (e.g. nets/regs/memory).
        // Some backends may not support these iterate types; null iterators are skipped.
        if max_level == 0 || level < max_level {
            let mut visited_name_set = HashSet::new();
            for object_type in [vpiNet, vpiReg, vpiMemory] {
                let obj_iter = unsafe { vpi_iterate(object_type as _, child) };
                if obj_iter.is_null() {
                    continue;
                }

                loop {
                    let obj = unsafe { vpi_scan(obj_iter) };
                    if obj.is_null() {
                        break;
                    }

                    let obj_name_ptr = unsafe { vpi_get_str(vpiName as _, obj) } as *const c_char;
                    let Some(obj_name) = (unsafe { utils::c_char_to_str_opt(obj_name_ptr) }) else {
                        continue;
                    };
                    if !visited_name_set.insert(obj_name.to_string()) {
                        continue;
                    }

                    let obj_full_path = if obj_name.contains('.') {
                        obj_name.to_string()
                    } else {
                        format!("{full_path}.{obj_name}")
                    };
                    let obj_bitwidth = unsafe { vpi_get(vpiSize as _, obj) };
                    push_hierarchy_entry(
                        entries,
                        seen_paths,
                        obj_full_path,
                        // Leaf objects have no module def-name metadata.
                        None,
                        Some(
                            match object_type {
                                vpiNet => "wire",
                                // Keep hierarchy sig-type output minimal/stable as {wire, reg}.
                                // `vpiMemory` is folded into `reg` by policy.
                                // NOTE: In wave_vpi (especially FST), waveform metadata may classify
                                // some `output reg` ports as net-like objects; this semantic
                                // difference should
                                // be documented rather than surfaced as extra sig-type variants.
                                vpiReg | vpiMemory => "reg",
                                _ => "reg",
                            }
                            .to_string(),
                        ),
                        level + 1,
                        obj_bitwidth,
                    );
                }
            }
        }

        vpiml_collect_hierarchy_recursive(
            child,
            full_path.as_str(),
            level + 1,
            max_level,
            entries,
            seen_paths,
        );
    }
}

fn collect_hierarchy_entries(max_level: PLI_INT32) -> Vec<HierarchyEntry> {
    // Build one Rust snapshot so Lua can focus on policy checks and output formatting.
    let mut entries = Vec::new();
    let mut seen_paths = HashSet::new();
    vpiml_collect_hierarchy_recursive(
        std::ptr::null_mut(),
        "",
        0,
        max_level,
        &mut entries,
        &mut seen_paths,
    );
    entries.sort_by(|a, b| {
        a.full_path
            .cmp(&b.full_path)
            .then_with(|| a.level.cmp(&b.level))
    });
    entries
}

fn entry_matches(
    entry: &HierarchyEntry,
    wildcard_matchers: &[wildmatch::WildMatch],
    module_name_filter: Option<&str>,
) -> bool {
    let wildcard_match = wildcard_matchers.is_empty()
        || wildcard_matchers
            .iter()
            .any(|matcher| matcher.matches(entry.full_path.as_str()));
    let module_name_match =
        module_name_filter.is_none_or(|filter| entry.module_name.as_deref() == Some(filter));
    wildcard_match && module_name_match
}

fn parse_wildcard_matchers(wildcard: *const c_char) -> Vec<wildmatch::WildMatch> {
    let Some(raw_pattern) = (unsafe { utils::c_char_to_str_opt(wildcard) }) else {
        return Vec::new();
    };

    raw_pattern
        .split(',')
        .map(str::trim)
        .filter(|pattern| !pattern.is_empty())
        .map(wildmatch::WildMatch::new)
        .collect()
}

fn emit_hierarchy_entry(entry: &HierarchyEntry, cb: HierarchyItemCallback) {
    let Ok(full_path_cstr) = CString::new(entry.full_path.as_str()) else {
        return;
    };
    let name = entry
        .full_path
        .rsplit('.')
        .next()
        .unwrap_or(entry.full_path.as_str());
    let Ok(name_cstr) = CString::new(name) else {
        return;
    };
    let module_name_cstr = entry
        .module_name
        .as_ref()
        .and_then(|name| CString::new(name.as_str()).ok());
    let module_name_ptr = module_name_cstr
        .as_ref()
        .map_or(std::ptr::null(), |name| name.as_ptr());
    let sig_type_cstr = entry
        .sig_type
        .as_ref()
        .and_then(|sig_type| CString::new(sig_type.as_str()).ok());
    let sig_type_ptr = sig_type_cstr
        .as_ref()
        .map_or(std::ptr::null(), |sig_type| sig_type.as_ptr());
    // CStrings stay alive for the duration of cb call.
    unsafe {
        cb(
            full_path_cstr.as_ptr(),
            name_cstr.as_ptr(),
            module_name_ptr,
            sig_type_ptr,
            entry.level,
            entry.bitwidth,
        )
    };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_collect_hierarchy(
    max_level: PLI_INT32,
    wildcard: *const c_char,
    module_name: *const c_char,
    include_tree_prefixes: PLI_INT32,
    require_module_name_data: PLI_INT32,
    cb: Option<HierarchyItemCallback>,
) -> *const c_char {
    // Return contract for Lua FFI:
    // - NULL => success
    // - non-NULL => static error message owned by Rust side
    if cfg!(feature = "dpi") {
        return err_ptr(HIER_ERR_UNSUPPORTED_DPI);
    }

    let Some(cb) = cb else {
        return err_ptr(HIER_ERR_INTERNAL_NULL_CB);
    };
    let wildcard_matchers = parse_wildcard_matchers(wildcard);
    let module_name_filter =
        unsafe { utils::c_char_to_str_opt(module_name) }.filter(|name| !name.is_empty());

    #[cfg(feature = "hierarchy_cache")]
    let all_entries = get_or_init_hierarchy_cache();
    #[cfg(not(feature = "hierarchy_cache"))]
    let all_entries = collect_hierarchy_entries(max_level);

    // Apply max_level filter on the full set.
    // When hierarchy_cache is enabled, the cache always stores all levels (max_level=0),
    // so we filter here. When cache is disabled, collect_hierarchy_entries already
    // prunes by max_level during VPI traversal, but we still filter for consistency.
    let entries: Vec<&HierarchyEntry> = if max_level == 0 {
        all_entries.iter().collect()
    } else {
        all_entries
            .iter()
            .filter(|entry| entry.level <= max_level)
            .collect()
    };

    let has_module_name_data = entries.iter().any(|entry| entry.module_name.is_some());
    let need_module_name_data = module_name_filter.is_some() || require_module_name_data != 0;
    if need_module_name_data && !has_module_name_data {
        return if module_name_filter.is_some() {
            err_ptr(HIER_ERR_MODULE_NAME_ONLY_FSDB)
        } else {
            err_ptr(HIER_ERR_SHOW_DEF_NAME_ONLY_FSDB)
        };
    }

    if include_tree_prefixes != 0 && !wildcard_matchers.is_empty() {
        // Tree mode wildcard keeps ancestor prefixes so output remains readable.
        let mut visible_paths = HashSet::new();
        for entry in entries.iter() {
            if !entry_matches(entry, wildcard_matchers.as_slice(), module_name_filter) {
                continue;
            }

            let mut prefix = String::new();
            for seg in entry.full_path.split('.') {
                prefix = if prefix.is_empty() {
                    seg.to_string()
                } else {
                    format!("{prefix}.{seg}")
                };
                visible_paths.insert(prefix.clone());
            }
        }

        for entry in entries.iter() {
            if visible_paths.contains(entry.full_path.as_str()) {
                emit_hierarchy_entry(entry, cb);
            }
        }
    } else {
        for entry in entries.iter() {
            if entry_matches(entry, wildcard_matchers.as_slice(), module_name_filter) {
                emit_hierarchy_entry(entry, cb);
            }
        }
    }

    std::ptr::null()
}

#[cfg(all(test, feature = "hierarchy_cache"))]
mod tests {
    use super::*;

    fn make_entries() -> Vec<HierarchyEntry> {
        vec![
            HierarchyEntry {
                full_path: "tb_top".to_string(),
                module_name: None,
                sig_type: None,
                level: 0,
                bitwidth: -1,
            },
            HierarchyEntry {
                full_path: "tb_top.u_top".to_string(),
                module_name: Some("TopMod".to_string()),
                sig_type: None,
                level: 1,
                bitwidth: -1,
            },
            HierarchyEntry {
                full_path: "tb_top.u_top.clk".to_string(),
                module_name: None,
                sig_type: Some("wire".to_string()),
                level: 2,
                bitwidth: 1,
            },
            HierarchyEntry {
                full_path: "tb_top.u_top.data".to_string(),
                module_name: None,
                sig_type: Some("reg".to_string()),
                level: 2,
                bitwidth: 32,
            },
        ]
    }

    #[test]
    fn test_binary_save_load_roundtrip() {
        let entries = make_entries();
        let tmp = std::env::temp_dir().join("verilua_test_bin_cache_roundtrip");
        let path = tmp.to_str().unwrap();

        save_cache(path, &entries, Some(1710000000), Some("/test/sim.fst")).unwrap();
        let loaded = try_load_cache(path, Some(1710000000), Some("/test/sim.fst")).unwrap();

        assert_eq!(entries.len(), loaded.len());
        for (a, b) in entries.iter().zip(loaded.iter()) {
            assert_eq!(a.full_path, b.full_path);
            assert_eq!(a.module_name, b.module_name);
            assert_eq!(a.sig_type, b.sig_type);
            assert_eq!(a.level, b.level);
            assert_eq!(a.bitwidth, b.bitwidth);
        }

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn test_binary_cache_stale_mtime() {
        let entries = make_entries();
        let tmp = std::env::temp_dir().join("verilua_test_bin_cache_stale");
        let path = tmp.to_str().unwrap();

        save_cache(path, &entries, Some(1710000000), Some("/test/sim.fst")).unwrap();
        let loaded = try_load_cache(path, Some(1710099999), Some("/test/sim.fst"));
        assert!(loaded.is_none());

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn test_binary_cache_missing_file() {
        let loaded =
            try_load_cache("/tmp/verilua_nonexistent_bin_cache_xyz", Some(123), Some("/a"));
        assert!(loaded.is_none());
    }

    #[test]
    fn test_binary_cache_unknown_mtime() {
        let entries = make_entries();
        let tmp = std::env::temp_dir().join("verilua_test_bin_cache_unknown_mtime");
        let path = tmp.to_str().unwrap();

        // Save with None mtime (stores u64::MAX)
        save_cache(path, &entries, None, Some("/test/sim.fst")).unwrap();
        // Should still load even with a current mtime
        let loaded = try_load_cache(path, Some(1710000000), Some("/test/sim.fst")).unwrap();
        assert_eq!(entries.len(), loaded.len());

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn test_binary_cache_invalid_magic() {
        let tmp = std::env::temp_dir().join("verilua_test_bin_cache_bad_magic");
        let path = tmp.to_str().unwrap();

        // Write garbage with wrong magic
        let mut data = vec![0u8; HIERARCHY_CACHE_FIXED_HEADER_SIZE];
        data[0..4].copy_from_slice(&0xDEADBEEFu32.to_le_bytes());
        data[4..12].copy_from_slice(&42u64.to_le_bytes());
        data[12..16].copy_from_slice(&0u32.to_le_bytes());
        std::fs::write(path, &data).unwrap();

        let loaded = try_load_cache(path, Some(42), None);
        assert!(loaded.is_none());

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn test_binary_cache_truncated_file() {
        let tmp = std::env::temp_dir().join("verilua_test_bin_cache_truncated");
        let path = tmp.to_str().unwrap();

        // File too short for header
        std::fs::write(path, &[0u8; 8]).unwrap();
        let loaded = try_load_cache(path, Some(42), None);
        assert!(loaded.is_none());

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn test_binary_cache_empty_entries() {
        let entries: Vec<HierarchyEntry> = vec![];
        let tmp = std::env::temp_dir().join("verilua_test_bin_cache_empty");
        let path = tmp.to_str().unwrap();

        save_cache(path, &entries, Some(999), None).unwrap();
        let loaded = try_load_cache(path, Some(999), None).unwrap();
        assert!(loaded.is_empty());

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn test_binary_cache_old_tsv_format_rejected() {
        let tmp = std::env::temp_dir().join("verilua_test_bin_cache_old_tsv");
        let path = tmp.to_str().unwrap();

        // Write old TSV format content
        std::fs::write(path, "# source_mtime:1710000000\ntb_top\t\t\t0\n").unwrap();
        let loaded = try_load_cache(path, Some(1710000000), None);
        assert!(loaded.is_none());

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn test_binary_cache_source_path_mismatch() {
        let entries = make_entries();
        let tmp = std::env::temp_dir().join("verilua_test_bin_cache_src_mismatch");
        let path = tmp.to_str().unwrap();

        // Save with FST source path
        save_cache(path, &entries, Some(1710000000), Some("/test/sim.fst")).unwrap();
        // Try loading with VCD source path (same mtime!) → should reject
        let loaded = try_load_cache(path, Some(1710000000), Some("/test/sim.vcd"));
        assert!(loaded.is_none());

        // Same source path → should accept
        let loaded = try_load_cache(path, Some(1710000000), Some("/test/sim.fst"));
        assert!(loaded.is_some());

        std::fs::remove_file(path).ok();
    }
}

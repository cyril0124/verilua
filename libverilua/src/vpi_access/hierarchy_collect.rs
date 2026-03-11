use super::*;
use std::collections::HashSet;

type HierarchyItemCallback =
    unsafe extern "C" fn(*const c_char, *const c_char, *const c_char, *const c_char, PLI_INT32);

const HIER_ERR_MODULE_NAME_ONLY_FSDB: &[u8] =
    b"[get_hierarchy] `module_name` is only supported for FSDB waveform in wave_vpi backend.\0";
const HIER_ERR_SHOW_DEF_NAME_ONLY_FSDB: &[u8] =
    b"[print_hierarchy] `show_def_name` is only supported for FSDB waveform in wave_vpi backend.\0";
const HIER_ERR_INTERNAL_NULL_CB: &[u8] =
    b"[print_hierarchy/get_hierarchy] vpiml_collect_hierarchy failed: callback is null.\0";
const HIER_ERR_UNSUPPORTED_DPI: &[u8] =
    b"[print_hierarchy/get_hierarchy] hierarchy collection is not supported in DPI mode.\0";

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
}

fn push_hierarchy_entry(
    entries: &mut Vec<HierarchyEntry>,
    seen_paths: &mut HashSet<String>,
    full_path: String,
    module_name: Option<String>,
    sig_type: Option<String>,
    level: PLI_INT32,
) {
    // Merge module-scan + leaf-scan output into a unique full-path set.
    if !seen_paths.insert(full_path.clone()) {
        // Some backends may expose the same logical path via multiple aliases.
        // Keep the stronger signal type when a duplicate arrives later.
        if sig_type.as_deref() == Some("reg")
            && let Some(existing) = entries.iter_mut().find(|entry| entry.full_path == full_path)
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
    entries.sort_by(|a, b| a.full_path.cmp(&b.full_path).then_with(|| a.level.cmp(&b.level)));
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
    let module_name_match = module_name_filter
        .is_none_or(|filter| entry.module_name.as_deref() == Some(filter));
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

    let entries = collect_hierarchy_entries(max_level);
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

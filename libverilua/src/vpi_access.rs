#![allow(non_upper_case_globals)]
use std::cell::UnsafeCell;

use super::*;

use verilua_env::{ComplexHandle, ComplexHandleRaw, get_verilua_env};
use vpi_user::*;

const MAX_VECTOR_SIZE: usize = 32;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_top_module() -> *const libc::c_char {
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_simulator_auto() -> *const libc::c_char {
    return utils::get_simulator_auto();
}

#[inline(always)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn complex_handle_by_name(
    name: *mut PLI_BYTE8,
    scope: vpiHandle,
) -> ComplexHandleRaw {
    let hdl = {
        let env = get_verilua_env();
        {
            let name_str = unsafe { CStr::from_ptr(name).to_string_lossy().into_owned() };
            if let Some(hdl) = env.hdl_cache.get(&name_str) {
                #[cfg(feature = "debug")]
                log::debug!("[complex_handle_by_name] hit cache => {}", name_str);

                *hdl
            } else {
                #[cfg(feature = "debug")]
                log::debug!("[complex_handle_by_name] miss cache => {}", name_str);

                let vpi_handle = unsafe { vpi_handle_by_name(name, scope) };
                let width = unsafe { vpi_get(vpiSize as _, vpi_handle) };
                let chdl = ComplexHandle::new(vpi_handle, name, width as _);
                let chdl_ptr = chdl.into_raw();
                env.hdl_cache.insert(name_str, chdl_ptr);

                chdl_ptr
            }
        }
    };

    hdl
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_handle_by_name(name: *mut c_char) -> ComplexHandleRaw {
    let handle = unsafe { complex_handle_by_name(name, std::ptr::null_mut()) };
    let chdl = ComplexHandle::from_raw(&handle);
    assert!(
        !(chdl.vpi_handle as vpiHandle).is_null(),
        "[vpiml_handle_by_name] No handle found: {}",
        unsafe { CStr::from_ptr(name).to_str().unwrap() }
    );
    handle
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_handle_by_name_safe(name: *mut c_char) -> ComplexHandleRaw {
    let handle = unsafe { complex_handle_by_name(name, std::ptr::null_mut()) };
    let chdl = ComplexHandle::from_raw(&handle);
    if (chdl.vpi_handle as vpiHandle).is_null() {
        #[cfg(feature = "debug")]
        log::debug!(
            "[vpiml_handle_by_name_safe] get null handle => {}",
            unsafe { CStr::from_ptr(name).to_string_lossy().into_owned() }
        );

        -1
    } else {
        handle
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_handle_by_index(
    complex_handle_raw: ComplexHandleRaw,
    idx: u32,
) -> ComplexHandleRaw {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    let final_name = format!("{}[{}]", complex_handle.get_name(), idx);
    if let Some(hdl) = get_verilua_env().hdl_cache.get(&final_name) {
        *hdl
    } else {
        let ret_vpi_handle = unsafe { vpi_handle_by_index(complex_handle.vpi_handle, idx as _) };
        assert!(
            !ret_vpi_handle.is_null(),
            "No handle found, parent_name => {}, index => {}",
            complex_handle.get_name(),
            idx
        );

        let width = unsafe { vpi_get(vpiSize as _, ret_vpi_handle) };

        let final_name_cstr = std::ffi::CString::new(final_name).unwrap();
        let ret_complex_handle =
            ComplexHandle::new(ret_vpi_handle, final_name_cstr.into_raw(), width as _);

        ret_complex_handle.into_raw()
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_iterate_vpi_type(module_name: *mut c_char, vpi_type: u32) {
    let ref_module_handle = unsafe { complex_handle_by_name(module_name, std::ptr::null_mut()) };
    let chdl = ComplexHandle::from_raw(&ref_module_handle);
    let iter = unsafe { vpi_iterate(vpi_type as _, chdl.vpi_handle as vpiHandle) };

    println!(
        "[vpiml_iterate_vpi_type] start iterate on module_name => {} type => {}",
        unsafe { CStr::from_ptr(module_name).to_str().unwrap() },
        match vpi_type {
            vpiNet => "vpiNet",
            vpiReg => "vpiReg",
            vpiMemory => "vpiMemory",
            _ => "unknown",
        }
    );

    let mut hdl: vpiHandle;
    let mut count = 0;
    loop {
        hdl = unsafe { vpi_scan(iter) };
        if hdl.is_null() {
            break;
        }
        let name = unsafe { vpi_get_str(vpiName as _, hdl) };
        let typ = unsafe { vpi_get_str(vpiType as _, hdl) };

        println!(
            "[{count}] name => {} type => {}",
            unsafe { CStr::from_ptr(name).to_str().unwrap() },
            unsafe { CStr::from_ptr(typ).to_str().unwrap() }
        );
        count += 1;
    }

    if count == 0 {
        println!("[vpiml_iterate_vpi_type] No objects found")
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_signal_width(
    complex_handle_raw: ComplexHandleRaw,
) -> c_longlong {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    complex_handle.width as _
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_hdl_type(complex_handle_raw: ComplexHandleRaw) -> *const c_char {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    unsafe { vpi_get_str(vpiType as _, complex_handle.vpi_handle as vpiHandle) as _ }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_value_by_name(path: *mut c_char) -> c_longlong {
    let chdl =
        ComplexHandle::from_raw(&unsafe { complex_handle_by_name(path, std::ptr::null_mut()) });
    assert!(
        !chdl.vpi_handle.is_null(),
        "[vpiml_get_value_by_name] handle is null: {}",
        unsafe { CStr::from_ptr(path).to_string_lossy().into_owned() }
    );

    let mut v = s_vpi_value {
        format: vpiVectorVal as _,
        value: t_vpi_value__bindgen_ty_1 { integer: 0 },
    };

    unsafe { vpi_get_value(chdl.vpi_handle, &mut v) };

    if cfg!(not(feature = "iverilog")) {
        unsafe { v.value.vector.read().aval as _ }
    } else {
        let env = get_verilua_env();
        if env.resolve_x_as_zero && unsafe { v.value.vector.read().bval } != 0 {
            0 as _
        } else {
            unsafe { v.value.vector.read().aval as _ }
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_value(complex_handle_raw: ComplexHandleRaw) -> u32 {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    let mut v = s_vpi_value {
        format: vpiVectorVal as _,
        value: t_vpi_value__bindgen_ty_1 { integer: 0 },
    };

    unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

    if cfg!(not(feature = "iverilog")) {
        unsafe { v.value.vector.read().aval as _ }
    } else {
        let env = get_verilua_env();
        if env.resolve_x_as_zero && unsafe { v.value.vector.read().bval } != 0 {
            0 as _
        } else {
            unsafe { v.value.vector.read().aval as _ }
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_value64(complex_handle_raw: ComplexHandleRaw) -> u64 {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    let mut v = s_vpi_value {
        format: vpiVectorVal as _,
        value: t_vpi_value__bindgen_ty_1 { integer: 0 },
    };

    unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

    if cfg!(not(feature = "iverilog")) {
        let lo: u32 = unsafe { v.value.vector.read().aval } as _;
        let hi: u32 = unsafe { v.value.vector.add(1).read().aval } as _;
        ((hi as u64) << 32) | lo as u64
    } else {
        let env = get_verilua_env();
        if env.resolve_x_as_zero
            && (unsafe { v.value.vector.read().bval } != 0
                || unsafe { v.value.vector.add(1).read().bval } != 0)
        {
            0
        } else {
            let lo: u32 = unsafe { v.value.vector.read().aval } as _;
            let hi: u32 = unsafe { v.value.vector.add(1).read().aval } as _;
            ((hi as u64) << 32) | lo as u64
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vpiml_get_value_multi(
    complex_handle_raw: ComplexHandleRaw,
    ret: *mut u32,
    len: u32,
) {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    let mut v = s_vpi_value {
        format: vpiVectorVal as _,
        value: t_vpi_value__bindgen_ty_1 { integer: 0 },
    };

    unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v as *mut _) };

    if cfg!(feature = "iverilog") {
        let resolve_x_as_zero = get_verilua_env().resolve_x_as_zero;
        for i in 1..(len + 1) {
            if resolve_x_as_zero && unsafe { v.value.vector.read().bval } != 0 {
                unsafe { ret.add(i as _).write(0) };
            } else {
                unsafe {
                    ret.add(i as _)
                        .write(v.value.vector.add((i - 1) as _).read().aval as _)
                };
            }
        }
    } else {
        for i in 1..(len + 1) {
            unsafe {
                ret.add(i as _)
                    .write(v.value.vector.add((i - 1) as _).read().aval as _)
            };
        }
    }

    unsafe { ret.add(0).write(len) }; // Number of the returned values
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_value_str(
    complex_handle_raw: ComplexHandleRaw,
    fmt: u32,
) -> *const c_char {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    let mut v = s_vpi_value {
        format: match fmt {
            vpiBinStrVal => vpiBinStrVal as _,
            vpiHexStrVal => vpiHexStrVal as _,
            vpiOctStrVal => vpiOctStrVal as _,
            vpiDecStrVal => vpiDecStrVal as _,
            _ => panic!("Invalid format => {}", fmt),
        },
        value: t_vpi_value__bindgen_ty_1 { integer: 0 },
    };

    unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

    #[cfg(feature = "vcs")]
    {
        // Remove leading `space`
        let raw_str = unsafe { CStr::from_ptr(v.value.str_) };
        let trimmed_str = raw_str.to_string_lossy().trim_start().to_string();
        let trimmed_c_str = std::ffi::CString::new(trimmed_str).unwrap();
        trimmed_c_str.into_raw()
    }

    #[cfg(not(feature = "vcs"))]
    {
        if cfg!(feature = "iverilog") {
            let env = get_verilua_env();
            let raw_str = unsafe { CStr::from_ptr(v.value.str_) };
            let value_str = raw_str.to_string_lossy().trim_start().to_string();

            if env.resolve_x_as_zero {
                std::ffi::CString::new(value_str.replace("x", "0"))
                    .unwrap()
                    .into_raw()
            } else {
                unsafe { v.value.str_ }
            }
        } else {
            unsafe { v.value.str_ }
        }
    }
}

macro_rules! gen_get_value_str {
    ($name:ident, $format:ident) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(complex_handle_raw: ComplexHandleRaw) -> *const c_char {
            let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
            let mut v = s_vpi_value {
                format: $format as _,
                value: t_vpi_value__bindgen_ty_1 { integer: 0 },
            };

            unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

            #[cfg(feature = "vcs")]
            {
                // Remove leading `space`
                let raw_str = unsafe { CStr::from_ptr(v.value.str_) };
                let trimmed_str = raw_str.to_string_lossy().trim_start().to_string();
                let trimmed_c_str = std::ffi::CString::new(trimmed_str).unwrap();
                trimmed_c_str.into_raw()
            }

            #[cfg(not(feature = "vcs"))]
            {
                if cfg!(feature = "iverilog") {
                    let env = get_verilua_env();
                    let raw_str = unsafe { CStr::from_ptr(v.value.str_) };
                    let value_str = raw_str.to_string_lossy().trim_start().to_string();

                    if env.resolve_x_as_zero {
                        std::ffi::CString::new(value_str.replace("x", "0"))
                            .unwrap()
                            .into_raw()
                    } else {
                        unsafe { v.value.str_ }
                    }
                } else {
                    unsafe { v.value.str_ }
                }
            }
        }
    };
}

gen_get_value_str!(vpiml_get_value_hex_str, vpiHexStrVal);
gen_get_value_str!(vpiml_get_value_bin_str, vpiBinStrVal);
gen_get_value_str!(vpiml_get_value_dec_str, vpiDecStrVal);

macro_rules! gen_set_force_value {
    ($action:ident, $flag:ty) => {
        // Generate:
        //      vpiml_<set/force>_value and vpiml_<set/force>_value_by_name
        //      vpiml_<set/force>_value64 and vpiml_<set/force>_value64_by_name
        //      vpiml_<set/force>_value64_force_single and vpiml_<set/force>_value64_force_single_by_name
        paste::paste!{
            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value>](complex_handle_raw: ComplexHandleRaw, value: u32) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let env = get_verilua_env();
                if complex_handle.try_put_value(env, &$flag, &vpiVectorVal) {
                    complex_handle.put_value_vectors[0].aval = value as _;
                    env.hdl_put_value.push(complex_handle_raw);
                }
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value>](complex_handle_raw: ComplexHandleRaw, value: u32) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);

                let mut vec_v = t_vpi_vecval {
                    aval: value as _,
                    bval: 0,
                };
                let mut v = if $flag == vpiForceFlag {
                    s_vpi_value {
                        format: vpiIntVal as _,
                        value: t_vpi_value__bindgen_ty_1 {
                            integer: value as _,
                        },
                    }
                } else {
                    s_vpi_value {
                        format: vpiVectorVal as _,
                        value: t_vpi_value__bindgen_ty_1 {
                            vector: &mut vec_v as *mut _,
                        },
                    }
                };

                unsafe {
                    vpi_put_value(
                        complex_handle.vpi_handle,
                        &mut v as *mut _,
                        std::ptr::null_mut(),
                        $flag as _,
                    )
                };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value_by_name>](path: *mut c_char, value: u32) {
                let complex_handle_raw = unsafe { vpiml_handle_by_name(path) };
                unsafe { [<vpiml_ $action _value>](complex_handle_raw as _, value) };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value_by_name>](path: *mut c_char, value: u32) {
                let complex_handle_raw = unsafe { vpiml_handle_by_name(path) };
                unsafe { [<vpiml_ $action _imm_value>](complex_handle_raw as _, value) };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value64>](complex_handle_raw: ComplexHandleRaw, value: u64) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let env = get_verilua_env();
                if complex_handle.try_put_value(env, &$flag, &vpiVectorVal) {
                    let vectors = &mut complex_handle.put_value_vectors;
                    vectors[1].aval = (value >> 32) as _;
                    vectors[1].bval = 0;
                    vectors[0].aval = (value & 0xFFFFFFFF) as _;
                    vectors[0].bval = 0;
                    env.hdl_put_value.push(complex_handle_raw);
                }
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value64>](complex_handle_raw: ComplexHandleRaw, value: u64) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let vectors = &mut complex_handle.put_value_vectors;
                vectors[1].aval = (value >> 32) as _;
                vectors[1].bval = 0;
                vectors[0].aval = ((value << 32) >> 32) as _;
                vectors[0].bval = 0;

                let mut v = s_vpi_value {
                    format: vpiVectorVal as _,
                    value: t_vpi_value__bindgen_ty_1 {
                        vector: vectors.as_mut_ptr(),
                    },
                };

                unsafe {
                    vpi_put_value(
                        complex_handle.vpi_handle,
                        &mut v as *mut _,
                        std::ptr::null_mut(),
                        $flag as _,
                    )
                };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value64_by_name>](path: *mut c_char, value: u64) {
                let complex_handle_raw = unsafe { vpiml_handle_by_name(path) };
                unsafe { [<vpiml_ $action _value64>](complex_handle_raw as _, value) };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value64_by_name>](path: *mut c_char, value: u64) {
                let complex_handle_raw = unsafe { vpiml_handle_by_name(path) };
                unsafe { [<vpiml_ $action _imm_value64>](complex_handle_raw as _, value) };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value64_force_single>](complex_handle_raw: ComplexHandleRaw, value: u64) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let env = get_verilua_env();
                if complex_handle.try_put_value(env, &$flag, &vpiVectorVal) {
                    let vectors = &mut complex_handle.put_value_vectors;
                    for vector in vectors.iter_mut().take(complex_handle.beat_num as usize) {
                        vector.aval = 0;
                        vector.bval = 0;
                    }

                    vectors[1].aval = (value >> 32) as _;
                    vectors[0].aval = ((value << 32) >> 32) as _;

                    env.hdl_put_value.push(complex_handle_raw);
                }
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value64_force_single>](complex_handle_raw: ComplexHandleRaw, value: u64) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let vectors = &mut complex_handle.put_value_vectors;
                for vector in vectors.iter_mut().take(complex_handle.beat_num as usize) {
                    vector.aval = 0;
                    vector.bval = 0;
                }

                vectors[1].aval = (value >> 32) as _;
                vectors[0].aval = ((value << 32) >> 32) as _;

                let mut v = s_vpi_value {
                    format: vpiVectorVal as _,
                    value: t_vpi_value__bindgen_ty_1 {
                        vector: vectors.as_mut_ptr(),
                    },
                };

                unsafe {
                    vpi_put_value(
                        complex_handle.vpi_handle,
                        &mut v as *mut _,
                        std::ptr::null_mut(),
                        $flag as _,
                    )
                };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value_multi>](complex_handle_raw: ComplexHandleRaw, value: *const u32) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let env = get_verilua_env();
                if complex_handle.try_put_value(env, &$flag, &vpiVectorVal) {
                    let vectors = &mut complex_handle.put_value_vectors;
                    for (i, vector) in vectors.iter_mut().enumerate().take(complex_handle.beat_num as usize) {
                        vector.aval = unsafe { *value.add(i) } as _;
                        vector.bval = 0;
                    }

                    env.hdl_put_value.push(complex_handle_raw);
                }
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value_multi>](complex_handle_raw: ComplexHandleRaw, value: *const u32) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let vectors = &mut complex_handle.put_value_vectors;
                for (i, vector) in vectors.iter_mut().enumerate().take(complex_handle.beat_num as usize) {
                    vector.aval = unsafe { *value.add(i) } as _;
                    vector.bval = 0;
                }

                let mut v = s_vpi_value {
                    format: vpiVectorVal as _,
                    value: t_vpi_value__bindgen_ty_1 {
                        vector: vectors.as_mut_ptr(),
                    },
                };

                unsafe {
                    vpi_put_value(
                        complex_handle.vpi_handle,
                        &mut v as *mut _,
                        std::ptr::null_mut(),
                        $flag as _,
                    )
                };
            }
        }
    }
}

gen_set_force_value!(set, vpiNoDelay);
gen_set_force_value!(force, vpiForceFlag);

macro_rules! gen_set_force_value_multi_beat {
    ($action:ident, $count:literal, $flag:ident, $($i:literal),*) => {
        paste::paste! {
            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value_multi_beat_ $count>](complex_handle_raw: ComplexHandleRaw $(, paste::paste!{[<v $i>]}: u32)*) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let env = get_verilua_env();
                if complex_handle.try_put_value(env, &$flag, &vpiVectorVal) {
                    paste::paste! {
                        $( complex_handle.put_value_vectors[$i].aval = [<v $i>] as _ );*
                    }

                    env.hdl_put_value.push(complex_handle_raw);
                }
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value_multi_beat_ $count>](complex_handle_raw: ComplexHandleRaw $(, paste::paste!{[<v $i>]}: u32)*) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                paste::paste! {
                    let mut vector = [
                        $( t_vpi_vecval { aval: [<v $i>] as _, bval: 0 } ),*
                    ];
                }

                let mut v = s_vpi_value {
                    format: vpiVectorVal as _,
                    value: t_vpi_value__bindgen_ty_1 {
                        vector: &mut vector as *mut _
                    }
                };

                unsafe {
                    vpi_put_value(
                        complex_handle.vpi_handle,
                        &mut v as *mut _,
                        std::ptr::null_mut(),
                        $flag as _
                    )
                };
            }
        }
    };
}

gen_set_force_value_multi_beat!(set, 2, vpiNoDelay, 0, 1);
gen_set_force_value_multi_beat!(set, 3, vpiNoDelay, 0, 1, 2);
gen_set_force_value_multi_beat!(set, 4, vpiNoDelay, 0, 1, 2, 3);
gen_set_force_value_multi_beat!(set, 5, vpiNoDelay, 0, 1, 2, 3, 4);
gen_set_force_value_multi_beat!(set, 6, vpiNoDelay, 0, 1, 2, 3, 4, 5);
gen_set_force_value_multi_beat!(set, 7, vpiNoDelay, 0, 1, 2, 3, 4, 5, 6);
gen_set_force_value_multi_beat!(set, 8, vpiNoDelay, 0, 1, 2, 3, 4, 5, 6, 7);

gen_set_force_value_multi_beat!(force, 2, vpiForceFlag, 0, 1);
gen_set_force_value_multi_beat!(force, 3, vpiForceFlag, 0, 1, 2);
gen_set_force_value_multi_beat!(force, 4, vpiForceFlag, 0, 1, 2, 3);
gen_set_force_value_multi_beat!(force, 5, vpiForceFlag, 0, 1, 2, 3, 4);
gen_set_force_value_multi_beat!(force, 6, vpiForceFlag, 0, 1, 2, 3, 4, 5);
gen_set_force_value_multi_beat!(force, 7, vpiForceFlag, 0, 1, 2, 3, 4, 5, 6);
gen_set_force_value_multi_beat!(force, 8, vpiForceFlag, 0, 1, 2, 3, 4, 5, 6, 7);

macro_rules! gen_set_force_value_str {
    ($action:ident, $flag:ty) => {
        paste::paste! {
            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value_str>](complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);

                let cstr = unsafe { CStr::from_ptr(value_str) };
                let str_bytes = cstr.to_bytes();
                let (final_value_str, format) = if str_bytes.starts_with(b"0b") {
                    (unsafe { value_str.add(2) }, vpiBinStrVal)
                } else if str_bytes.starts_with(b"0x") {
                    (unsafe { value_str.add(2) }, vpiHexStrVal)
                } else {
                    (value_str, vpiDecStrVal)
                };

                let env = get_verilua_env();
                if complex_handle.try_put_value(env, &$flag, &format as _) {
                    complex_handle.put_value_str = unsafe { CStr::from_ptr(final_value_str).to_str().unwrap().to_string() };
                    env.hdl_put_value.push(complex_handle_raw);
                }
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value_str>](complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                    panic!("force value is not supported in verilator!");
                }

                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);

                let cstr = unsafe { CStr::from_ptr(value_str) };
                let str_bytes = cstr.to_bytes();
                let (final_value_str, format) = if str_bytes.starts_with(b"0b") {
                    (unsafe { value_str.add(2) }, vpiBinStrVal)
                } else if str_bytes.starts_with(b"0x") {
                    (unsafe { value_str.add(2) }, vpiHexStrVal)
                } else {
                    (value_str, vpiDecStrVal)
                };

                let mut v = s_vpi_value {
                    format: format as _,
                    value: t_vpi_value__bindgen_ty_1 { integer: 0 },
                };

                v.value.str_ = final_value_str;

                unsafe {
                    vpi_put_value(
                        complex_handle.vpi_handle,
                        &mut v,
                        std::ptr::null_mut(),
                        $flag as _,
                    )
                };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value_str_by_name>](path: *mut c_char, value_str: *mut c_char) {
                let complex_handle_raw = unsafe { vpiml_handle_by_name(path) };
                unsafe { [<vpiml_ $action _value_str>](complex_handle_raw as _, value_str) };
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value_str_by_name>](path: *mut c_char, value_str: *mut c_char) {
                let complex_handle_raw = unsafe { vpiml_handle_by_name(path) };
                unsafe { [<vpiml_ $action _imm_value_str>](complex_handle_raw as _, value_str) };
            }
        }
    };
}

gen_set_force_value_str!(set, vpiNoDelay);
gen_set_force_value_str!(force, vpiForceFlag);

macro_rules! gen_set_value_str {
    ($type:ident, $format:ident) => {
        paste::paste! {
            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_set_value_ $type _str>](complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let env = get_verilua_env();
                if complex_handle.try_put_value(env, &vpiNoDelay, &$format as _) {
                    complex_handle.put_value_str =
                        unsafe { CStr::from_ptr(value_str).to_str().unwrap().to_string() };
                    env.hdl_put_value.push(complex_handle_raw);
                }
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_set_imm_value_ $type _str>](complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let mut v = s_vpi_value {
                    format: $format as _,
                    value: t_vpi_value__bindgen_ty_1 { str_: value_str },
                };

                unsafe {
                    vpi_put_value(
                        complex_handle.vpi_handle,
                        &mut v,
                        std::ptr::null_mut(),
                        vpiNoDelay as _,
                    )
                };
            }
        }
    };
}

gen_set_value_str!(hex, vpiHexStrVal);
gen_set_value_str!(bin, vpiBinStrVal);
gen_set_value_str!(dec, vpiDecStrVal);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_release_value(complex_handle_raw: ComplexHandleRaw) {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    if cfg!(feature = "verilator") {
        panic!("release value is not supported in verilator!");
    } else {
        let mut v = s_vpi_value {
            format: vpiVectorVal as _,
            value: t_vpi_value__bindgen_ty_1 { integer: 0 as _ },
        };

        // Tips from cocotb:
        //      Best to pass its current value to the sim when releasing
        unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

        let env = get_verilua_env();
        if complex_handle.try_put_value(env, &vpiReleaseFlag, &(v.format as u32)) {
            complex_handle.put_value_integer = unsafe { v.value.integer } as _;
            for i in 0..complex_handle.beat_num {
                complex_handle.put_value_vectors[i].aval =
                    unsafe { v.value.vector.add(i as _).read().aval } as _;
                complex_handle.put_value_vectors[i].bval =
                    unsafe { v.value.vector.add(i as _).read().bval } as _;
            }

            env.hdl_put_value.push(complex_handle_raw);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_release_imm_value(complex_handle_raw: ComplexHandleRaw) {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    if cfg!(feature = "verilator") {
        panic!("release value is not supported in verilator!");
    } else {
        let mut v = s_vpi_value {
            format: vpiVectorVal as _,
            value: t_vpi_value__bindgen_ty_1 { integer: 0 as _ },
        };

        // Tips from cocotb:
        //      Best to pass its current value to the sim when releasing
        unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

        unsafe {
            vpi_put_value(
                complex_handle.vpi_handle,
                &mut v,
                std::ptr::null_mut(),
                vpiReleaseFlag as _,
            )
        };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_release_value_by_name(path: *mut c_char) {
    let handle = unsafe { complex_handle_by_name(path, std::ptr::null_mut()) };
    let chdl = ComplexHandle::from_raw(&handle);
    assert!(
        !chdl.vpi_handle.is_null(),
        "[vpiml_release_value_by_name] No handle found: {}",
        unsafe { CStr::from_ptr(path).to_string_lossy().into_owned() }
    );

    unsafe { vpiml_release_value(handle as _) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_release_imm_value_by_name(path: *mut c_char) {
    let handle = unsafe { complex_handle_by_name(path, std::ptr::null_mut()) };
    let chdl = ComplexHandle::from_raw(&handle);
    assert!(
        !chdl.vpi_handle.is_null(),
        "[vpiml_release_imm_value_by_name] No handle found: {}",
        unsafe { CStr::from_ptr(path).to_string_lossy().into_owned() }
    );

    unsafe { vpiml_release_imm_value(handle as _) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_set_shuffled(complex_handle_raw: ComplexHandleRaw) {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    if complex_handle.width <= 32 {
        unsafe {
            vpiml_set_value(complex_handle_raw, libc::rand() as u32);
        }
    } else if complex_handle.width <= 64 {
        unsafe {
            vpiml_set_value64(
                complex_handle_raw,
                ((libc::rand() as u64) << 32) | (libc::rand() as u64),
            );
        }
    } else {
        let mut value = Vec::with_capacity(complex_handle.beat_num);
        value.extend((0..complex_handle.beat_num).map(|_| unsafe { libc::rand() } as u32));

        unsafe {
            vpiml_set_value_multi(complex_handle_raw, value.as_ptr());
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_set_shuffled_by_name(path: *mut c_char) {
    let handle = unsafe { vpiml_handle_by_name(path) };
    unsafe { vpiml_set_shuffled(handle as _) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_set_imm_shuffled(complex_handle_raw: ComplexHandleRaw) {
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    if complex_handle.width <= 32 {
        unsafe {
            vpiml_set_imm_value(complex_handle_raw, libc::rand() as u32);
        }
    } else if complex_handle.width <= 64 {
        unsafe {
            vpiml_set_imm_value64(
                complex_handle_raw,
                ((libc::rand() as u64) << 32) | (libc::rand() as u64),
            );
        }
    } else {
        let mut value = Vec::with_capacity(complex_handle.beat_num);
        value.extend((0..complex_handle.beat_num).map(|_| unsafe { libc::rand() } as u32));

        unsafe {
            vpiml_set_imm_value_multi(complex_handle_raw, value.as_ptr());
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_set_imm_shuffled_by_name(path: *mut c_char) {
    let handle = unsafe { vpiml_handle_by_name(path) };
    unsafe { vpiml_set_imm_shuffled(handle as _) };
}

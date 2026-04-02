use super::*;
use num_bigint::BigUint;

/// SAFETY:
/// The returned pointer remains valid only until the next string-read call on the
/// same `ComplexHandle`. Callers must copy it immediately and must not cache it.
///
/// The normalization intentionally matches the current backend-specific behavior:
/// trim leading ASCII spaces when requested, and replace lowercase `x` with `0`
/// only when `replace_lower_x_with_zero` is enabled.
#[inline(always)]
fn normalize_value_str_to_c_ptr(
    complex_handle: &mut ComplexHandle,
    raw_ptr: *const c_char,
    trim_leading_space: bool,
    replace_lower_x_with_zero: bool,
) -> *const c_char {
    if !trim_leading_space && !replace_lower_x_with_zero {
        return raw_ptr;
    }

    let raw = unsafe { CStr::from_ptr(raw_ptr) }.to_bytes();
    let start = if trim_leading_space {
        // VCS is known to pad string values with leading ASCII spaces. Keep the
        // current behavior narrow here instead of doing generic whitespace trimming.
        raw.iter()
            .position(|&byte| byte != b' ')
            .unwrap_or(raw.len())
    } else {
        0
    };
    let normalized = &raw[start..];

    if !replace_lower_x_with_zero && start == 0 {
        return raw_ptr;
    }

    let buf = &mut complex_handle.get_value_str_buf;
    buf.clear();

    if replace_lower_x_with_zero && normalized.contains(&b'x') {
        // Preserve the current iVerilog semantics: only lowercase `x` is resolved
        // to `0` here, while other characters such as `X`/`Z` stay unchanged.
        for &byte in normalized {
            buf.push(if byte == b'x' { b'0' } else { byte });
        }
    } else {
        buf.extend_from_slice(normalized);
    }

    buf.push(0);
    buf.as_ptr() as *const c_char
}

impl VeriluaEnv {
    #[inline(always)]
    pub fn vpiml_get_value(&mut self, complex_handle_raw: ComplexHandleRaw) -> u32 {
        let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
        let mut v = s_vpi_value {
            format: vpiIntVal as _,
            value: t_vpi_value__bindgen_ty_1 { integer: 0 },
        };

        unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

        unsafe { v.value.integer as _ }
    }

    pub fn vpiml_get_value64(&mut self, complex_handle_raw: ComplexHandleRaw) -> u64 {
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
        } else if self.resolve_x_as_zero
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

    pub fn vpiml_get_value_multi(
        &mut self,
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
            let resolve_x_as_zero = self.resolve_x_as_zero;
            for i in 1..(len + 1) {
                if resolve_x_as_zero && unsafe { v.value.vector.add((i - 1) as _).read().bval } != 0
                {
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

    pub fn vpiml_get_value_str(
        &mut self,
        complex_handle_raw: ComplexHandleRaw,
        fmt: u32,
    ) -> *const c_char {
        match fmt {
            vpiBinStrVal => self.vpiml_get_value_bin_str(complex_handle_raw),
            vpiHexStrVal => self.vpiml_get_value_hex_str(complex_handle_raw),
            vpiOctStrVal => self.vpiml_get_value_oct_str(complex_handle_raw),
            vpiDecStrVal => self.vpiml_get_value_dec_str(complex_handle_raw),
            _ => panic!("Invalid format => {}", fmt),
        }
    }
}

macro_rules! impl_gen_get_value_str {
    ($name:ident, $format:ident) => {
        impl VeriluaEnv {
            pub fn $name(&mut self, complex_handle_raw: ComplexHandleRaw) -> *const c_char {
                let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                let mut v = s_vpi_value {
                    format: $format as _,
                    value: t_vpi_value__bindgen_ty_1 { integer: 0 },
                };

                unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

                #[cfg(feature = "vcs")]
                {
                    normalize_value_str_to_c_ptr(
                        complex_handle,
                        unsafe { v.value.str_ },
                        true,
                        false,
                    )
                }

                #[cfg(not(feature = "vcs"))]
                {
                    if cfg!(feature = "iverilog") {
                        if self.resolve_x_as_zero {
                            normalize_value_str_to_c_ptr(
                                complex_handle,
                                unsafe { v.value.str_ },
                                true,
                                true,
                            )
                        } else {
                            unsafe { v.value.str_ }
                        }
                    } else {
                        unsafe { v.value.str_ }
                    }
                }
            }
        }
    };
}
impl_gen_get_value_str!(vpiml_get_value_hex_str, vpiHexStrVal);
impl_gen_get_value_str!(vpiml_get_value_bin_str, vpiBinStrVal);
impl_gen_get_value_str!(vpiml_get_value_oct_str, vpiOctStrVal);

// impl_gen_get_value_str!(vpiml_get_value_dec_str, vpiDecStrVal);
impl VeriluaEnv {
    pub fn vpiml_get_value_dec_str(
        &mut self,
        complex_handle_raw: ComplexHandleRaw,
    ) -> *const c_char {
        let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);

        if cfg!(feature = "verilator") {
            // It seems that there is a bug in vpiDecStrVal under verilator(5.034).
            // Here, hex string is used to indirectly generate dec string as a workaround.

            let mut v = s_vpi_value {
                format: vpiHexStrVal as _,
                value: t_vpi_value__bindgen_ty_1 { integer: 0 },
            };
            unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

            let raw_hex_str = unsafe { CStr::from_ptr(v.value.str_) };
            let raw_hex_bytes = raw_hex_str.to_bytes();
            let start = raw_hex_bytes
                .iter()
                .position(|&byte| byte != b' ')
                .unwrap_or(raw_hex_bytes.len());
            let normalized_hex = &raw_hex_bytes[start..];
            let hex_str = raw_hex_str.to_string_lossy();

            let buf = &mut complex_handle.get_value_str_buf;
            buf.clear();

            if normalized_hex.is_empty() {
                buf.extend_from_slice(b"0");
                buf.push(0);
                return buf.as_ptr() as *const c_char;
            }

            for &byte in normalized_hex {
                buf.push(match byte {
                    b'x' | b'X' | b'z' | b'Z' => b'0',
                    _ => byte,
                });
            }

            let value = BigUint::parse_bytes(buf.as_slice(), 16).unwrap_or_else(|| {
                panic!(
                    "Failed to parse cleaned hex string '{}' (from original '{}') from Verilator",
                    String::from_utf8_lossy(buf.as_slice()),
                    hex_str,
                )
            });

            let dec_string = value.to_str_radix(10);
            buf.clear();
            buf.extend_from_slice(dec_string.as_bytes());
            buf.push(0);
            buf.as_ptr() as *const c_char
        } else {
            let mut v = s_vpi_value {
                format: vpiDecStrVal as _,
                value: t_vpi_value__bindgen_ty_1 { integer: 0 },
            };

            unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

            #[cfg(feature = "vcs")]
            {
                normalize_value_str_to_c_ptr(complex_handle, unsafe { v.value.str_ }, true, false)
            }

            #[cfg(not(feature = "vcs"))]
            {
                if cfg!(feature = "iverilog") {
                    if self.resolve_x_as_zero {
                        normalize_value_str_to_c_ptr(
                            complex_handle,
                            unsafe { v.value.str_ },
                            true,
                            true,
                        )
                    } else {
                        unsafe { v.value.str_ }
                    }
                } else {
                    unsafe { v.value.str_ }
                }
            }
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_value(complex_handle_raw: ComplexHandleRaw) -> u32 {
    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
    env.vpiml_get_value(complex_handle_raw)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_value64(complex_handle_raw: ComplexHandleRaw) -> u64 {
    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
    env.vpiml_get_value64(complex_handle_raw)
}

#[unsafe(no_mangle)]
pub extern "C" fn vpiml_get_value_multi(
    complex_handle_raw: ComplexHandleRaw,
    ret: *mut u32,
    len: u32,
) {
    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
    env.vpiml_get_value_multi(complex_handle_raw, ret, len);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_get_value_str(
    complex_handle_raw: ComplexHandleRaw,
    fmt: u32,
) -> *const c_char {
    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
    env.vpiml_get_value_str(complex_handle_raw, fmt)
}

macro_rules! gen_get_value_str {
    ($name:ident, $format:ident) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(complex_handle_raw: ComplexHandleRaw) -> *const c_char {
            let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
            env.$name(complex_handle_raw)
        }
    };
}
gen_get_value_str!(vpiml_get_value_hex_str, vpiHexStrVal);
gen_get_value_str!(vpiml_get_value_bin_str, vpiBinStrVal);
gen_get_value_str!(vpiml_get_value_dec_str, vpiDecStrVal);

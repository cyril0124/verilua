use super::*;
use num_bigint::BigUint;

/// Reuses `get_value_str_buf`, so the pointer stays valid only until the next
/// string-read call on the same `ComplexHandle`. Trims the spaces VCS pads with.
#[inline(always)]
fn trim_leading_spaces_to_c_ptr(
    complex_handle: &mut ComplexHandle,
    raw_ptr: *const c_char,
) -> *const c_char {
    let raw = unsafe { CStr::from_ptr(raw_ptr) }.to_bytes();
    let first_non_space = raw
        .iter()
        .position(|&byte| byte != b' ')
        .unwrap_or(raw.len());

    if first_non_space == 0 {
        return raw_ptr;
    }

    let buf = &mut complex_handle.get_value_str_buf;
    buf.clear();
    buf.extend_from_slice(&raw[first_non_space..]);
    buf.push(0);
    buf.as_ptr() as *const c_char
}

/// `beat`'s value with the `x`/`z` bits read as `0`, keeping the other bits.
#[inline(always)]
fn aval_without_x_bits(beat: &t_vpi_vecval, resolve_x_as_zero: bool) -> i32 {
    if resolve_x_as_zero {
        beat.aval & !beat.bval
    } else {
        beat.aval
    }
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

        let lo = unsafe { v.value.vector.read() };
        let hi = if complex_handle.beat_num > 1 {
            unsafe { v.value.vector.add(1).read() }
        } else {
            t_vpi_vecval { aval: 0, bval: 0 }
        };

        let resolve_x_as_zero = self.resolve_x_as_zero && !cfg!(feature = "verilator");

        let lo_aval = aval_without_x_bits(&lo, resolve_x_as_zero);
        let hi_aval = aval_without_x_bits(&hi, resolve_x_as_zero);

        ((hi_aval as u32 as u64) << 32) | lo_aval as u32 as u64
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

        let resolve_x_as_zero = self.resolve_x_as_zero && !cfg!(feature = "verilator");

        for i in 1..(len + 1) {
            let beat = unsafe { v.value.vector.add((i - 1) as _).read() };
            let aval = aval_without_x_bits(&beat, resolve_x_as_zero);

            unsafe { ret.add(i as _).write(aval as _) };
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

                trim_leading_spaces_to_c_ptr(complex_handle, unsafe { v.value.str_ })
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

            trim_leading_spaces_to_c_ptr(complex_handle, unsafe { v.value.str_ })
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

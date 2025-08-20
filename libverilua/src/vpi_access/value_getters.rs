use super::*;

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
                    // Remove leading `space`
                    let raw_str = unsafe { CStr::from_ptr(v.value.str_) };
                    let trimmed_str = raw_str.to_string_lossy().trim_start().to_string();
                    let trimmed_c_str = std::ffi::CString::new(trimmed_str).unwrap();
                    trimmed_c_str.into_raw()
                }

                #[cfg(not(feature = "vcs"))]
                {
                    if cfg!(feature = "iverilog") {
                        let raw_str = unsafe { CStr::from_ptr(v.value.str_) };
                        let value_str = raw_str.to_string_lossy().trim_start().to_string();

                        if self.resolve_x_as_zero {
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
            let hex_str = raw_hex_str.to_string_lossy();
            let clean_hex_str = hex_str.replace(['x', 'X', 'z', 'Z'], "0");

            match u128::from_str_radix(&clean_hex_str, 16) {
                Ok(value) => {
                    let dec_string = value.to_string();
                    std::ffi::CString::new(dec_string).unwrap().into_raw()
                }
                Err(e) => {
                    panic!(
                        "Failed to parse cleaned hex string '{}' (from original '{}') from Verilator: {}",
                        clean_hex_str, hex_str, e
                    );
                }
            }
        } else {
            let mut v = s_vpi_value {
                format: vpiDecStrVal as _,
                value: t_vpi_value__bindgen_ty_1 { integer: 0 },
            };

            unsafe { vpi_get_value(complex_handle.vpi_handle, &mut v) };

            #[cfg(feature = "vcs")]
            {
                // TODO:
                // Remove leading `space`
                let raw_str = unsafe { CStr::from_ptr(v.value.str_) };
                let trimmed_str = raw_str.to_string_lossy().trim_start().to_string();
                let trimmed_c_str = std::ffi::CString::new(trimmed_str).unwrap();
                trimmed_c_str.into_raw()
            }

            #[cfg(not(feature = "vcs"))]
            {
                if cfg!(feature = "iverilog") {
                    let raw_str = unsafe { CStr::from_ptr(v.value.str_) };
                    let value_str = raw_str.to_string_lossy().trim_start().to_string();

                    if self.resolve_x_as_zero {
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

use super::*;

// ------------------------------------------------------------------
// IMPL set/force value
// ------------------------------------------------------------------
macro_rules! impl_gen_set_force_value {
    ($action:ident, $flag:ty) => {
        // Generate:
        //      vpiml_<set/force>_value
        //      vpiml_<set/force>_value64
        //      vpiml_<set/force>_value64_force_single
        paste::paste!{
            impl VeriluaEnv {
                pub fn [<vpiml_ $action _value>](&mut self, complex_handle_raw: ComplexHandleRaw, value: u32) {
                    if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                        panic!("force value is not supported in verilator!");
                    }

                    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                    if complex_handle.try_put_value(self, &$flag, &vpiVectorVal) {
                        complex_handle.put_value_vectors[0].aval = value as _;
                        self.hdl_put_value.push(complex_handle_raw);
                    }
                }

                pub fn [<vpiml_ $action _imm_value>](&mut self, complex_handle_raw: ComplexHandleRaw, value: u32) {
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

                pub fn [<vpiml_ $action _value64>](&mut self, complex_handle_raw: ComplexHandleRaw, value: u64) {
                    if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                        panic!("force value is not supported in verilator!");
                    }

                    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                    if complex_handle.try_put_value(self, &$flag, &vpiVectorVal) {
                        let vectors = &mut complex_handle.put_value_vectors;
                        vectors[1].aval = (value >> 32) as _;
                        vectors[1].bval = 0;
                        vectors[0].aval = (value & 0xFFFFFFFF) as _;
                        vectors[0].bval = 0;
                        self.hdl_put_value.push(complex_handle_raw);
                    }
                }

                pub fn [<vpiml_ $action _imm_value64>](&mut self, complex_handle_raw: ComplexHandleRaw, value: u64) {
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

                pub fn [<vpiml_ $action _value64_force_single>](&mut self, complex_handle_raw: ComplexHandleRaw, value: u64) {
                    if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                        panic!("force value is not supported in verilator!");
                    }

                    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                    if complex_handle.try_put_value(self, &$flag, &vpiVectorVal) {
                        let vectors = &mut complex_handle.put_value_vectors;
                        for vector in vectors.iter_mut().take(complex_handle.beat_num as usize) {
                            vector.aval = 0;
                            vector.bval = 0;
                        }

                        vectors[1].aval = (value >> 32) as _;
                        vectors[0].aval = ((value << 32) >> 32) as _;

                        self.hdl_put_value.push(complex_handle_raw);
                    }
                }

                pub fn [<vpiml_ $action _imm_value64_force_single>](&mut self, complex_handle_raw: ComplexHandleRaw, value: u64) {
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

                pub unsafe extern "C" fn [<vpiml_ $action _value_multi>](&mut self, complex_handle_raw: ComplexHandleRaw, value: *const u32) {
                    if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                        panic!("force value is not supported in verilator!");
                    }

                    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                    if complex_handle.try_put_value(self, &$flag, &vpiVectorVal) {
                        let vectors = &mut complex_handle.put_value_vectors;
                        for (i, vector) in vectors.iter_mut().enumerate().take(complex_handle.beat_num as usize) {
                            vector.aval = unsafe { *value.add(i) } as _;
                            vector.bval = 0;
                        }

                        self.hdl_put_value.push(complex_handle_raw);
                    }
                }

                pub fn [<vpiml_ $action _imm_value_multi>](&mut self, complex_handle_raw: ComplexHandleRaw, value: *const u32) {
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
}
impl_gen_set_force_value!(set, vpiNoDelay);
impl_gen_set_force_value!(force, vpiForceFlag);

// ------------------------------------------------------------------
// IMPL set/force value str
// ------------------------------------------------------------------
macro_rules! impl_gen_set_value_str {
    ($set_type: ident, $str_type:ident, $flag:ident, $format:ident) => {
        paste::paste! {
            impl VeriluaEnv {
                pub fn [<vpiml_ $set_type _value_ $str_type _str>](&mut self, complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                    if complex_handle.try_put_value(self, &$flag, &$format as _) {
                        complex_handle.put_value_str =
                            unsafe { CStr::from_ptr(value_str).to_str().unwrap().to_string() };
                        self.hdl_put_value.push(complex_handle_raw);
                    }
                }

                pub fn [<vpiml_ $set_type _imm_value_ $str_type _str>](&mut self, complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
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
                            $flag as _,
                        )
                    };
                }
            }
        }
    };
}
impl_gen_set_value_str!(set, hex, vpiNoDelay, vpiHexStrVal);
impl_gen_set_value_str!(set, bin, vpiNoDelay, vpiBinStrVal);
impl_gen_set_value_str!(set, dec, vpiNoDelay, vpiDecStrVal);
impl_gen_set_value_str!(force, hex, vpiForceFlag, vpiHexStrVal);
impl_gen_set_value_str!(force, bin, vpiForceFlag, vpiBinStrVal);
impl_gen_set_value_str!(force, dec, vpiForceFlag, vpiDecStrVal);

// ------------------------------------------------------------------
// IMPL set/force value multi beat
// ------------------------------------------------------------------
macro_rules! impl_gen_set_force_value_multi_beat {
    ($action:ident, $count:literal, $flag:ident, $($i:literal),*) => {
        paste::paste! {
            impl VeriluaEnv {
                pub fn [<vpiml_ $action _value_multi_beat_ $count>](&mut self, complex_handle_raw: ComplexHandleRaw $(, paste::paste!{[<v $i>]}: u32)*) {
                    if $flag == vpiForceFlag && cfg!(feature = "verilator") {
                        panic!("force value is not supported in verilator!");
                    }

                    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
                    if complex_handle.try_put_value(self, &$flag, &vpiVectorVal) {
                        paste::paste! {
                            $( complex_handle.put_value_vectors[$i].aval = [<v $i>] as _ );*
                        }

                        self.hdl_put_value.push(complex_handle_raw);
                    }
                }

                pub fn [<vpiml_ $action _imm_value_multi_beat_ $count>](&mut self, complex_handle_raw: ComplexHandleRaw $(, paste::paste!{[<v $i>]}: u32)*) {
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
        }
    };
}
impl_gen_set_force_value_multi_beat!(set, 2, vpiNoDelay, 0, 1);
impl_gen_set_force_value_multi_beat!(set, 3, vpiNoDelay, 0, 1, 2);
impl_gen_set_force_value_multi_beat!(set, 4, vpiNoDelay, 0, 1, 2, 3);
impl_gen_set_force_value_multi_beat!(set, 5, vpiNoDelay, 0, 1, 2, 3, 4);
impl_gen_set_force_value_multi_beat!(set, 6, vpiNoDelay, 0, 1, 2, 3, 4, 5);
impl_gen_set_force_value_multi_beat!(set, 7, vpiNoDelay, 0, 1, 2, 3, 4, 5, 6);
impl_gen_set_force_value_multi_beat!(set, 8, vpiNoDelay, 0, 1, 2, 3, 4, 5, 6, 7);
impl_gen_set_force_value_multi_beat!(force, 2, vpiForceFlag, 0, 1);
impl_gen_set_force_value_multi_beat!(force, 3, vpiForceFlag, 0, 1, 2);
impl_gen_set_force_value_multi_beat!(force, 4, vpiForceFlag, 0, 1, 2, 3);
impl_gen_set_force_value_multi_beat!(force, 5, vpiForceFlag, 0, 1, 2, 3, 4);
impl_gen_set_force_value_multi_beat!(force, 6, vpiForceFlag, 0, 1, 2, 3, 4, 5);
impl_gen_set_force_value_multi_beat!(force, 7, vpiForceFlag, 0, 1, 2, 3, 4, 5, 6);
impl_gen_set_force_value_multi_beat!(force, 8, vpiForceFlag, 0, 1, 2, 3, 4, 5, 6, 7);

// ------------------------------------------------------------------
// IMPL set/force value str
// ------------------------------------------------------------------
macro_rules! impl_gen_set_force_value_str {
    ($action:ident, $flag:ty) => {
        paste::paste! {
            impl VeriluaEnv {
                pub fn [<vpiml_ $action _value_str>](&mut self, complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
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

                    if complex_handle.try_put_value(self, &$flag, &format as _) {
                        complex_handle.put_value_str = unsafe { CStr::from_ptr(final_value_str).to_str().unwrap().to_string() };
                        self.hdl_put_value.push(complex_handle_raw);
                    }
                }

                pub fn [<vpiml_ $action _imm_value_str>](&mut self, complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
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
            }
        }
    };
}
impl_gen_set_force_value_str!(set, vpiNoDelay);
impl_gen_set_force_value_str!(force, vpiForceFlag);

// ------------------------------------------------------------------
// IMPL release/shuffle value
// ------------------------------------------------------------------
impl VeriluaEnv {
    pub fn vpiml_release_value(&mut self, complex_handle_raw: ComplexHandleRaw) {
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

            if complex_handle.try_put_value(self, &vpiReleaseFlag, &(v.format as u32)) {
                complex_handle.put_value_integer = unsafe { v.value.integer } as _;
                for i in 0..complex_handle.beat_num {
                    complex_handle.put_value_vectors[i].aval =
                        unsafe { v.value.vector.add(i as _).read().aval } as _;
                    complex_handle.put_value_vectors[i].bval =
                        unsafe { v.value.vector.add(i as _).read().bval } as _;
                }

                self.hdl_put_value.push(complex_handle_raw);
            }
        }
    }

    pub fn vpiml_release_imm_value(&mut self, complex_handle_raw: ComplexHandleRaw) {
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

    pub fn vpiml_set_shuffled(&mut self, complex_handle_raw: ComplexHandleRaw) {
        let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
        if complex_handle.width <= 32 {
            unsafe {
                self.vpiml_set_value(complex_handle_raw, libc::rand() as u32);
            }
        } else if complex_handle.width <= 64 {
            unsafe {
                self.vpiml_set_value64(
                    complex_handle_raw,
                    ((libc::rand() as u64) << 32) | (libc::rand() as u64),
                );
            }
        } else {
            let mut value = Vec::with_capacity(complex_handle.beat_num);
            value.extend((0..complex_handle.beat_num).map(|_| unsafe { libc::rand() } as u32));

            unsafe {
                self.vpiml_set_value_multi(complex_handle_raw, value.as_ptr());
            }
        }
    }

    pub fn vpiml_set_imm_shuffled(&mut self, complex_handle_raw: ComplexHandleRaw) {
        let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
        if complex_handle.width <= 32 {
            unsafe {
                self.vpiml_set_imm_value(complex_handle_raw, libc::rand() as u32);
            }
        } else if complex_handle.width <= 64 {
            unsafe {
                self.vpiml_set_imm_value64(
                    complex_handle_raw,
                    ((libc::rand() as u64) << 32) | (libc::rand() as u64),
                );
            }
        } else {
            let mut value = Vec::with_capacity(complex_handle.beat_num);
            value.extend((0..complex_handle.beat_num).map(|_| unsafe { libc::rand() } as u32));

            unsafe {
                self.vpiml_set_imm_value_multi(complex_handle_raw, value.as_ptr());
            }
        }
    }
}

// ------------------------------------------------------------------
// set/force value
// ------------------------------------------------------------------
macro_rules! gen_set_force_value {
    ($action:ident, $flag:ty) => {
        // Generate:
        //      vpiml_<set/force>_value
        //      vpiml_<set/force>_value64
        //      vpiml_<set/force>_value64_force_single
        paste::paste!{
            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value>](complex_handle_raw: ComplexHandleRaw, value: u32) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _value>](complex_handle_raw, value);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value>](complex_handle_raw: ComplexHandleRaw, value: u32) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _imm_value>](complex_handle_raw, value);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value64>](complex_handle_raw: ComplexHandleRaw, value: u64) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _value64>](complex_handle_raw, value);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value64>](complex_handle_raw: ComplexHandleRaw, value: u64) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _imm_value64>](complex_handle_raw, value);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value64_force_single>](complex_handle_raw: ComplexHandleRaw, value: u64) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _value64_force_single>](complex_handle_raw, value);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value64_force_single>](complex_handle_raw: ComplexHandleRaw, value: u64) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _imm_value64_force_single>](complex_handle_raw, value);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value_multi>](complex_handle_raw: ComplexHandleRaw, value: *const u32) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _value_multi>](complex_handle_raw, value);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value_multi>](complex_handle_raw: ComplexHandleRaw, value: *const u32) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _imm_value_multi>](complex_handle_raw, value);
            }
        }
    }
}
gen_set_force_value!(set, vpiNoDelay);
gen_set_force_value!(force, vpiForceFlag);

// ------------------------------------------------------------------
// set/force value bin/dec/hex str
// ------------------------------------------------------------------
macro_rules! gen_set_value_str {
    ($set_type:ident, $str_type:ident, $flag:ident, $format:ident) => {
        paste::paste! {
            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $set_type _value_ $str_type _str>](complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $set_type _value_ $str_type _str>](complex_handle_raw, value_str);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $set_type _imm_value_ $str_type _str>](complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $set_type _imm_value_ $str_type _str>](complex_handle_raw, value_str);
            }
        }
    };
}
gen_set_value_str!(set, hex, vpiNoDelay, vpiHexStrVal);
gen_set_value_str!(set, bin, vpiNoDelay, vpiBinStrVal);
gen_set_value_str!(set, dec, vpiNoDelay, vpiDecStrVal);
gen_set_value_str!(force, hex, vpiForceFlag, vpiHexStrVal);
gen_set_value_str!(force, bin, vpiForceFlag, vpiBinStrVal);
gen_set_value_str!(force, dec, vpiForceFlag, vpiDecStrVal);

// ------------------------------------------------------------------
// GEN set/force value multi beat
// ------------------------------------------------------------------
macro_rules! gen_set_force_value_multi_beat {
    ($action:ident, $count:literal, $flag:ident, $($i:literal),*) => {
        paste::paste! {
            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value_multi_beat_ $count>](complex_handle_raw: ComplexHandleRaw $(, paste::paste!{[<v $i>]}: u32)*) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _value_multi_beat_ $count>](complex_handle_raw $(, paste::paste!{[<v $i>]})*);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value_multi_beat_ $count>](complex_handle_raw: ComplexHandleRaw $(, paste::paste!{[<v $i>]}: u32)*) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _imm_value_multi_beat_ $count>](complex_handle_raw $(, paste::paste!{[<v $i>]})*);
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

// ------------------------------------------------------------------
// GEN set/force value str
// ------------------------------------------------------------------
macro_rules! gen_set_force_value_str {
    ($action:ident, $flag:ty) => {
        paste::paste! {
            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _value_str>](complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _value_str>](complex_handle_raw, value_str);
            }

            #[unsafe(no_mangle)]
            pub unsafe extern "C" fn [<vpiml_ $action _imm_value_str>](complex_handle_raw: ComplexHandleRaw, value_str: *mut c_char) {
                let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
                env.[<vpiml_ $action _imm_value_str>](complex_handle_raw, value_str);
            }
        }
    };
}
gen_set_force_value_str!(set, vpiNoDelay);
gen_set_force_value_str!(force, vpiForceFlag);

// ------------------------------------------------------------------
// GEN release/shuffle value
// ------------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_release_value(complex_handle_raw: ComplexHandleRaw) {
    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
    env.vpiml_release_value(complex_handle_raw);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_release_imm_value(complex_handle_raw: ComplexHandleRaw) {
    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
    env.vpiml_release_imm_value(complex_handle_raw);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_set_shuffled(complex_handle_raw: ComplexHandleRaw) {
    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
    env.vpiml_set_shuffled(complex_handle_raw);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_set_imm_shuffled(complex_handle_raw: ComplexHandleRaw) {
    let env = VeriluaEnv::from_complex_handle_raw(complex_handle_raw);
    env.vpiml_set_imm_shuffled(complex_handle_raw);
}

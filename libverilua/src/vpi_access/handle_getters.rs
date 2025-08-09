use super::*;

impl VeriluaEnv {
    #[inline(always)]
    pub fn complex_handle_by_name(
        &mut self,
        name: *mut PLI_BYTE8,
        scope: vpiHandle,
    ) -> ComplexHandleRaw {
        let hdl = {
            let name_str = unsafe { CStr::from_ptr(name).to_string_lossy().into_owned() };
            if let Some(hdl) = self.hdl_cache.get(&name_str) {
                #[cfg(feature = "debug")]
                log::debug!("[complex_handle_by_name] hit cache => {}", name_str);

                *hdl
            } else {
                #[cfg(feature = "debug")]
                log::debug!("[complex_handle_by_name] miss cache => {}", name_str);

                let vpi_handle = unsafe { vpi_handle_by_name(name, scope) };
                let width = if vpi_handle.is_null() {
                    log::debug!(
                        "[complex_handle_by_name] vpiHandle for `{}` is NULL! width => 0",
                        name_str
                    );
                    0
                } else {
                    unsafe { vpi_get(vpiSize as _, vpi_handle) }
                };
                let mut chdl = ComplexHandle::new(vpi_handle, name, width as _);
                chdl.env = self.as_void_ptr();

                let chdl_ptr = chdl.into_raw();
                self.hdl_cache.insert(name_str, chdl_ptr);
                chdl_ptr
            }
        };

        hdl
    }

    pub fn vpiml_handle_by_name(&mut self, name: *mut c_char) -> ComplexHandleRaw {
        let handle = unsafe { self.complex_handle_by_name(name, std::ptr::null_mut()) };
        let chdl = ComplexHandle::from_raw(&handle);
        assert!(
            !(chdl.vpi_handle as vpiHandle).is_null(),
            "[vpiml_handle_by_name] No handle found: {}",
            unsafe { CStr::from_ptr(name).to_str().unwrap() }
        );
        handle
    }

    pub fn vpiml_handle_by_index(
        &mut self,
        complex_handle_raw: ComplexHandleRaw,
        idx: u32,
    ) -> ComplexHandleRaw {
        let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
        let final_name = format!("{}[{}]", complex_handle.get_name(), idx);
        if let Some(hdl) = self.hdl_cache.get(&final_name) {
            *hdl
        } else {
            let ret_vpi_handle =
                unsafe { vpi_handle_by_index(complex_handle.vpi_handle, idx as _) };
            assert!(
                !ret_vpi_handle.is_null(),
                "No handle found, parent_name => {}, index => {}",
                complex_handle.get_name(),
                idx
            );

            let width = unsafe { vpi_get(vpiSize as _, ret_vpi_handle) };

            let final_name_cstr = std::ffi::CString::new(final_name).unwrap();
            let mut ret_complex_handle =
                ComplexHandle::new(ret_vpi_handle, final_name_cstr.into_raw(), width as _);
            ret_complex_handle.env = self.as_void_ptr();

            ret_complex_handle.into_raw()
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_handle_by_name(
    env: *mut libc::c_void,
    name: *mut c_char,
) -> ComplexHandleRaw {
    let env = unsafe { VeriluaEnv::from_void_ptr(env) };
    env.vpiml_handle_by_name(name)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_handle_by_name_safe(
    env: *mut libc::c_void,
    name: *mut c_char,
) -> ComplexHandleRaw {
    let env = unsafe { VeriluaEnv::from_void_ptr(env) };
    let handle = unsafe { env.complex_handle_by_name(name, std::ptr::null_mut()) };
    let chdl = ComplexHandle::from_raw(&handle);
    if (chdl.vpi_handle as vpiHandle).is_null() {
        #[cfg(feature = "debug")]
        log::debug!(
            "[vpiml_handle_by_name_safe] get NULL vpiHandle => {}",
            unsafe { CStr::from_ptr(name).to_string_lossy().into_owned() }
        );

        -1
    } else {
        handle
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn vpiml_handle_by_index(
    env: *mut libc::c_void,
    complex_handle_raw: ComplexHandleRaw,
    idx: u32,
) -> ComplexHandleRaw {
    let env = unsafe { VeriluaEnv::from_void_ptr(env) };
    env.vpiml_handle_by_index(complex_handle_raw, idx)
}

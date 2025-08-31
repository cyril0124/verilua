use hashbrown::{HashMap, HashSet};
use std::ffi::CStr;
use std::fmt::{self, Debug};

use crate::TaskID;
use crate::verilua_env::VeriluaEnv;
use crate::vpi_user::*;

pub type ComplexHandleRaw = libc::c_longlong;

const MAX_VECTOR_SIZE: usize = 32;

pub struct ShuffledValueVec<T> {
    pub vec: Vec<T>,
    pub len: usize,
}

impl<T> ShuffledValueVec<T>
where
    T: Clone,
{
    #[inline]
    pub fn get_rand_value(&self) -> T {
        let idx = unsafe { libc::rand() } % self.len as i32;
        self.vec[idx as usize].clone()
    }
}

#[derive(Debug, Clone, Copy)]
pub enum ShuffledValueVecType {
    None,
    U32,
    U64,
    HexStr,
}

#[repr(C)]
pub struct ComplexHandle {
    pub env: *mut libc::c_void,

    pub vpi_handle: vpiHandle,
    pub name: *mut libc::c_char,
    pub width: usize,
    pub beat_num: usize,

    pub put_value_format: u32,
    pub put_value_flag: Option<u32>,
    pub put_value_integer: u32,
    pub put_value_str: String,
    pub put_value_vectors: smallvec::SmallVec<[t_vpi_vecval; MAX_VECTOR_SIZE]>,

    #[cfg(feature = "merge_cb")]
    pub posedge_cb_count: HashMap<TaskID, u32>,
    #[cfg(feature = "merge_cb")]
    pub negedge_cb_count: HashMap<TaskID, u32>,
    #[cfg(feature = "merge_cb")]
    pub edge_cb_count: HashMap<TaskID, u32>,

    pub random_value_vec_type: ShuffledValueVecType,
    pub random_value_u32_vec: ShuffledValueVec<u32>,
    pub random_value_u64_vec: ShuffledValueVec<u64>,
    pub random_value_hex_str_vec: ShuffledValueVec<String>,
}

impl ComplexHandle {
    pub fn new(vpi_handle: vpiHandle, name: *mut libc::c_char, width: usize) -> Self {
        let beat_num = (width as f64 / 32.0).ceil() as usize;

        assert!(
            beat_num <= MAX_VECTOR_SIZE,
            "beat_num is too large: {}, width: {}, name: {}",
            beat_num,
            width,
            unsafe { CStr::from_ptr(name).to_string_lossy().into_owned() }
        );

        #[cfg(feature = "merge_cb")]
        {
            Self {
                env: std::ptr::null_mut(),
                vpi_handle,
                name,
                width,
                beat_num,
                put_value_format: 0,
                put_value_flag: None,
                put_value_integer: 0,
                put_value_str: String::new(),
                put_value_vectors: smallvec::smallvec![t_vpi_vecval {
                    aval: 0,
                    bval: 0,
                }; MAX_VECTOR_SIZE],
                posedge_cb_count: HashMap::new(),
                negedge_cb_count: HashMap::new(),
                edge_cb_count: HashMap::new(),
                random_value_vec_type: ShuffledValueVecType::None,
                random_value_u32_vec: ShuffledValueVec {
                    vec: Vec::new(),
                    len: 0,
                },
                random_value_u64_vec: ShuffledValueVec {
                    vec: Vec::new(),
                    len: 0,
                },
                random_value_hex_str_vec: ShuffledValueVec {
                    vec: Vec::new(),
                    len: 0,
                },
            }
        }

        #[cfg(not(feature = "merge_cb"))]
        {
            Self {
                env: std::ptr::null_mut(),
                vpi_handle,
                name,
                width,
                beat_num,
                put_value_format: 0,
                put_value_flag: None,
                put_value_integer: 0,
                put_value_str: String::new(),
                put_value_vectors: smallvec::smallvec![t_vpi_vecval {
                    aval: 0,
                    bval: 0,
                }; MAX_VECTOR_SIZE],
                random_value_vec_type: ShuffledValueVecType::None,
                random_value_u32_vec: ShuffledValueVec {
                    vec: Vec::new(),
                    len: 0,
                },
                random_value_u64_vec: ShuffledValueVec {
                    vec: Vec::new(),
                    len: 0,
                },
                random_value_hex_str_vec: ShuffledValueVec {
                    vec: Vec::new(),
                    len: 0,
                },
            }
        }
    }

    #[inline(always)]
    pub fn from_raw(raw: &ComplexHandleRaw) -> &'static mut Self {
        unsafe { &mut *(*raw as *mut Self) }
    }

    #[inline(always)]
    pub fn into_raw(self) -> ComplexHandleRaw {
        Box::into_raw(Box::new(self)) as ComplexHandleRaw
    }

    #[inline(always)]
    pub fn get_name(&self) -> String {
        unsafe { CStr::from_ptr(self.name).to_string_lossy().into_owned() }
    }

    #[inline(always)]
    pub fn try_put_value(&mut self, env: &mut VeriluaEnv, flag: &u32, format: &u32) -> bool {
        match self.put_value_flag {
            Some(curr_flag) => {
                if curr_flag == vpiForceFlag && *flag != vpiForceFlag {
                    // vpiForceFlag has higher priority than other flags
                    false
                } else {
                    // New force value will overwrite old force value
                    self.put_value_flag = Some(*flag);
                    self.put_value_format = *format;

                    // Remove old flag
                    let target_idx = env.hdl_put_value.iter().position(|complex_handle_raw| {
                        let complex_handle = ComplexHandle::from_raw(complex_handle_raw);
                        complex_handle.vpi_handle == self.vpi_handle
                    });

                    assert!(
                        target_idx.is_some(),
                        "Duplicate flag, but not found in env.hdl_put_value, curr_flag: {}, new_flag: {}, self: {:?}",
                        curr_flag,
                        *flag,
                        self
                    );
                    env.hdl_put_value
                        .remove(unsafe { target_idx.unwrap_unchecked() });

                    true
                }
            }
            None => {
                self.put_value_flag = Some(*flag);
                self.put_value_format = *format;
                true
            }
        }
    }
}

impl Debug for ComplexHandle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        #[cfg(feature = "merge_cb")]
        {
            write!(
                f,
                "ComplexHandle({}, name: {}, width: {}, beat_num: {}, posedge_cb_count: {:?}, negedge_cb_count: {:?}, edge_cb_count: {:?})",
                self.vpi_handle as libc::c_longlong,
                unsafe { CStr::from_ptr(self.name).to_string_lossy().into_owned() },
                self.width,
                self.beat_num,
                self.posedge_cb_count,
                self.negedge_cb_count,
                self.edge_cb_count
            )
        }

        #[cfg(not(feature = "merge_cb"))]
        {
            write!(
                f,
                "ComplexHandle({}, name: {}, width: {}, beat_num: {})",
                self.vpi_handle as libc::c_longlong,
                unsafe { CStr::from_ptr(self.name).to_string_lossy().into_owned() },
                self.width,
                self.beat_num
            )
        }
    }
}

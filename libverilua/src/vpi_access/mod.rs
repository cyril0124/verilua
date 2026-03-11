#![allow(non_upper_case_globals)]
use libc::{c_char, c_longlong, c_void};
use std::ffi::{CStr, CString};

use crate::complex_handle::{
    ComplexHandle, ComplexHandleRaw, ShuffledValueVec, ShuffledValueVecType,
};
use crate::utils;
use crate::verilua_env::VeriluaEnv;
use crate::vpi_user::*;

mod handle_getters;
mod hierarchy_collect;
mod meta_getters;
mod value_getters;
mod value_setters;

pub use meta_getters::*;

//! # Complex Handle
//!
//! This module provides an enhanced VPI handle wrapper (`ComplexHandle`) that adds
//! caching, metadata, and efficient value manipulation capabilities on top of raw VPI handles.
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                       ComplexHandle                             │
//! ├─────────────────────────────────────────────────────────────────┤
//! │  ┌─────────────┐  ┌───────────────┐  ┌────────────────────────┐ │
//! │  │ VPI Handle  │  │   Metadata    │  │   Pending Put Values   │ │
//! │  │ (raw ptr)   │  │ (width, name) │  │ (format, flag, value)  │ │
//! │  └─────────────┘  └───────────────┘  └────────────────────────┘ │
//! │                                                                 │
//! │  ┌─────────────────────────┐  ┌────────────────────────────┐    │
//! │  │  Callback Count Maps    │  │   Random Value Generator   │    │
//! │  │ (posedge/negedge/edge)  │  │  (shuffled value support)  │    │
//! │  └─────────────────────────┘  └────────────────────────────┘    │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!

#[cfg(feature = "merge_cb")]
use hashbrown::HashMap;
use std::fmt::{self, Debug};

use crate::utils;
use crate::verilua_env::VeriluaEnv;
use crate::vpi_user::*;

#[cfg(feature = "merge_cb")]
use crate::TaskID;

/// Raw handle type for FFI boundary - a pointer cast to i64 for Lua compatibility
pub type ComplexHandleRaw = libc::c_longlong;

/// Maximum number of 32-bit words supported for vector values.
/// Signals wider than 32 * MAX_VECTOR_SIZE bits will cause a panic.
const MAX_VECTOR_SIZE: usize = 32;

/// Container for pre-shuffled random values.
///
/// Used by `set_shuffled()` to efficiently pick random values from a predefined set.
/// The random selection uses `libc::rand()` for performance.
pub struct ShuffledValueVec<T> {
    pub vec: Vec<T>,
    pub len: usize,
}

impl<T> ShuffledValueVec<T>
where
    T: Clone,
{
    /// Returns a random value from the shuffled pool.
    ///
    /// Uses modulo of `libc::rand()` for index selection.
    /// This is faster than Rust's thread_rng but less random - acceptable for testbench use.
    #[inline]
    pub fn get_rand_value(&self) -> T {
        let idx = unsafe { libc::rand() } % self.len as i32;
        self.vec[idx as usize].clone()
    }
}

/// Indicates the type of random value pool configured for a handle
#[derive(Debug, Clone, Copy)]
pub enum ShuffledValueVecType {
    /// No shuffle pool - generate truly random values
    None,
    /// Pool of u32 values
    U32,
    /// Pool of u64 values
    U64,
    /// Pool of hex string values
    HexStr,
}

/// Enhanced VPI handle with caching and metadata.
///
/// `ComplexHandle` wraps a raw VPI handle and adds:
/// - Cached signal metadata (width, name, beat count)
/// - Pending value buffer for batched writes
/// - Callback reference counting for merge optimization
/// - Random value generation support
#[repr(C)]
pub struct ComplexHandle {
    /// Back-reference to the owning VeriluaEnv instance
    pub env: *mut libc::c_void,

    /// Raw VPI handle to the HDL signal
    pub vpi_handle: vpiHandle,

    /// Signal name (C string, owned)
    pub name: *mut libc::c_char,

    /// Signal bit width
    pub width: usize,

    /// Number of 32-bit beats needed to represent the full value
    /// Calculated as `ceil(width / 32)`
    pub beat_num: usize,

    // ──────────────────────────────────────────────────────────────────────
    // Pending Put Value Fields
    // These fields buffer write operations for batched application
    // ──────────────────────────────────────────────────────────────────────
    /// VPI value format for pending write (e.g., vpiIntVal, vpiVectorVal)
    pub put_value_format: u32,

    /// VPI flag for pending write (e.g., vpiNoDelay, vpiForceFlag)
    /// None indicates no pending write
    pub put_value_flag: Option<u32>,

    /// Integer value for single-beat signals
    pub put_value_integer: u32,

    /// String value for string-format writes
    pub put_value_str: String,

    /// Vector value buffer using SmallVec to avoid heap for common cases
    pub put_value_vectors: smallvec::SmallVec<[t_vpi_vecval; MAX_VECTOR_SIZE]>,

    // ──────────────────────────────────────────────────────────────────────
    // Callback Merge Tracking (feature = "merge_cb")
    // Counts active callbacks per task to enable callback deduplication
    // ──────────────────────────────────────────────────────────────────────
    #[cfg(feature = "merge_cb")]
    pub posedge_cb_count: HashMap<TaskID, u32>,
    #[cfg(feature = "merge_cb")]
    pub negedge_cb_count: HashMap<TaskID, u32>,
    #[cfg(feature = "merge_cb")]
    pub edge_cb_count: HashMap<TaskID, u32>,

    // ──────────────────────────────────────────────────────────────────────
    // Random Value Generation
    // Pre-shuffled value pools for constrained random generation
    // ──────────────────────────────────────────────────────────────────────
    /// Type of shuffled value pool configured
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
            utils::c_char_to_string(name)
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
        utils::c_char_to_string(self.name)
    }

    #[inline(always)]
    pub fn try_put_value(&mut self, env: &mut VeriluaEnv, flag: &u32, format: &u32) -> bool {
        match self.put_value_flag {
            Some(curr_flag) => {
                if curr_flag == vpiForceFlag && *flag != vpiForceFlag && *flag != vpiReleaseFlag {
                    // vpiForceFlag/vpiReleaseFlag has higher priority than other flags
                    false
                } else {
                    // New force value will overwrite old force value
                    self.put_value_flag = Some(*flag);
                    self.put_value_format = *format;

                    let hdl_put_value: &mut Vec<ComplexHandleRaw>;
                    if cfg!(feature = "vcs") || cfg!(feature = "iverilog") {
                        if env.use_hdl_put_value_bak {
                            hdl_put_value = &mut env.hdl_put_value_bak;
                        } else {
                            hdl_put_value = &mut env.hdl_put_value;
                        }
                    } else {
                        hdl_put_value = &mut env.hdl_put_value;
                    };

                    // Remove old flag
                    let target_idx = hdl_put_value.iter().position(|complex_handle_raw| {
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

                    hdl_put_value.remove(unsafe { target_idx.unwrap_unchecked() });

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
                utils::c_char_to_string(self.name),
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
                utils::c_char_to_string(self.name),
                self.width,
                self.beat_num
            )
        }
    }
}

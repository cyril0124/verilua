//! # Native Clock Module
//!
//! This module implements a high-performance clock driver for Verilua, inspired by
//! cocotb's GpiClock implementation. The clock toggles entirely in Rust/C without
//! returning to Lua, significantly reducing overhead for pure clock driving.
//!
//! ## Design
//!
//! ```text
//! ┌──────────────────────────────────────────────────────────────────┐
//! │                    NativeClock Architecture                      │
//! ├──────────────────────────────────────────────────────────────────┤
//! │                                                                  │
//! │   Lua Layer                                                      │
//! │   ┌──────────────────────────────────────────────────────────┐   │
//! │   │  local clk = NativeClock(dut.clock:chdl())               │   │
//! │   │  clk:start(10, "ns")  -- Start clock                     │   │
//! │   │  clk:stop()           -- Stop when done                  │   │
//! │   └──────────────────────────────────────────────────────────┘   │
//! │                          │                                       │
//! │                          ▼ FFI                                   │
//! │   Rust Layer                                                     │
//! │   ┌──────────────────────────────────────────────────────────┐   │
//! │   │  struct NativeClock {                                    │   │
//! │   │      signal_hdl: vpiHandle,                              │   │
//! │   │      period_steps: u64,                                  │   │
//! │   │      high_steps: u64,                                    │   │
//! │   │      current_val: u8,                                    │   │
//! │   │      cb_handle: Option<vpiHandle>,                       │   │
//! │   │  }                                                       │   │
//! │   └──────────────────────────────────────────────────────────┘   │
//! │                          │                                       │
//! │                          ▼ VPI                                   │
//! │   Simulator                                                      │
//! │   ┌──────────────────────────────────────────────────────────┐   │
//! │   │  cbAfterDelay → toggle_callback() → schedule next        │   │
//! │   │     ↑                                          │         │   │
//! │   │     └──────────────────────────────────────────┘         │   │
//! │   └──────────────────────────────────────────────────────────┘   │
//! │                                                                  │
//! └──────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Performance
//!
//! Unlike Lua-based clock implementations that require Lua coroutine switches
//! for each clock edge, NativeClock keeps the clock toggling loop entirely in
//! native code. This is especially beneficial for high-frequency clocks.

#![allow(dead_code)]

use std::collections::HashSet;

use crate::complex_handle::{ComplexHandle, ComplexHandleRaw};
use crate::vpi_user::*;

// ────────────────────────────────────────────────────────────────────────────────
// Global Signal Registry
// ────────────────────────────────────────────────────────────────────────────────

/// Global registry of signals with active NativeClock drivers.
/// Prevents conflicts when multiple NativeClock instances try to drive the same signal.
static mut ACTIVE_SIGNALS: *mut HashSet<usize> = std::ptr::null_mut();

#[inline]
fn get_active_signals() -> &'static mut HashSet<usize> {
    unsafe {
        if ACTIVE_SIGNALS.is_null() {
            ACTIVE_SIGNALS = Box::into_raw(Box::new(HashSet::new()));
        }
        &mut *ACTIVE_SIGNALS
    }
}

// ────────────────────────────────────────────────────────────────────────────────
// NativeClock Structure
// ────────────────────────────────────────────────────────────────────────────────

/// A high-performance clock driver that toggles entirely in native code.
///
/// NativeClock uses VPI timed callbacks to toggle a clock signal without returning
/// to Lua for each edge. This significantly reduces overhead compared to Lua-based
/// clock implementations.
pub struct NativeClock {
    /// VPI handle to the clock signal
    signal_hdl: vpiHandle,

    /// Clock period in simulation time steps
    period_steps: u64,

    /// Number of steps the clock is high (duty cycle control)
    high_steps: u64,

    /// Current clock value (0 or 1)
    current_val: u8,

    /// Handle to the currently registered VPI callback (None if stopped)
    cb_handle: Option<vpiHandle>,

    /// VPI value structure for setting clock values (reused to avoid allocation)
    vpi_value: t_vpi_value,

    /// Flag to track if we're inside the callback (prevents premature destruction)
    in_callback: bool,

    /// Flag to track if destroy was requested while in callback
    destroy_pending: bool,
}

/// Opaque handle type for FFI
pub type NativeClockHandle = *mut NativeClock;

impl NativeClock {
    /// Create a new NativeClock instance for the given signal.
    ///
    /// # Arguments
    /// * `signal_hdl` - VPI handle to the clock signal
    ///
    /// # Returns
    /// A new NativeClock instance (not yet started)
    pub fn new(signal_hdl: vpiHandle) -> Self {
        Self {
            signal_hdl,
            period_steps: 0,
            high_steps: 0,
            current_val: 0,
            cb_handle: None,
            vpi_value: t_vpi_value {
                format: vpiIntVal as _,
                value: t_vpi_value__bindgen_ty_1 { integer: 0 },
            },
            in_callback: false,
            destroy_pending: false,
        }
    }

    /// Start the clock with the specified timing parameters.
    ///
    /// # Arguments
    /// * `period` - Clock period in simulation time steps
    /// * `high` - Number of steps the clock is high
    /// * `start_high` - Whether to start with clock high (true) or low (false)
    ///
    /// # Returns
    /// * `0` - Success
    /// * `libc::EBUSY` - This NativeClock instance is already running
    /// * `libc::EEXIST` - Another NativeClock instance is already driving this signal
    /// * `libc::EINVAL` - Invalid parameters (period < 2, high < 1, or high >= period)
    pub fn start(&mut self, period: u64, high: u64, start_high: bool) -> i32 {
        // Check if this instance is already running
        if self.cb_handle.is_some() {
            return libc::EBUSY;
        }

        // Check if another NativeClock is driving this signal
        let signal_addr = self.signal_hdl as usize;
        let active = get_active_signals();
        if active.contains(&signal_addr) {
            return libc::EEXIST;
        }

        // Validate parameters
        if period < 2 || high < 1 || high >= period {
            return libc::EINVAL;
        }

        // Register this signal as active
        active.insert(signal_addr);

        self.period_steps = period;
        self.high_steps = high;
        self.current_val = if start_high { 1 } else { 0 };
        self.toggle(true)
    }

    /// Stop the clock.
    ///
    /// Removes the registered VPI callback and unregisters from the active signals.
    /// The clock signal will retain its last value.
    pub fn stop(&mut self) {
        // Always unregister from active signals when stop() is called
        let signal_addr = self.signal_hdl as usize;
        get_active_signals().remove(&signal_addr);

        // Remove the callback if one is pending
        if let Some(hdl) = self.cb_handle.take() {
            unsafe { vpi_remove_cb(hdl) };
        }
    }

    /// Check if the clock is currently running.
    #[inline]
    pub fn is_running(&self) -> bool {
        self.cb_handle.is_some()
    }

    /// Toggle the clock value and schedule the next toggle.
    ///
    /// # Arguments
    /// * `first_call` - True if this is the initial call (from start())
    ///
    /// # Returns
    /// * `0` - Success
    /// * Non-zero - Error code from VPI
    fn toggle(&mut self, first_call: bool) -> i32 {
        // Set the clock value
        self.vpi_value.value.integer = self.current_val as _;
        unsafe {
            vpi_put_value(
                self.signal_hdl,
                &mut self.vpi_value,
                std::ptr::null_mut(),
                vpiNoDelay as _,
            );
        }

        // Calculate delay until next toggle
        let delay = if self.current_val == 1 {
            self.high_steps
        } else {
            self.period_steps - self.high_steps
        };

        // Toggle value for next time
        self.current_val ^= 1;

        // Create a new t_vpi_time for this callback
        // Use vpiSimTime format - time in simulation precision units
        let adjusted_delay = delay;

        // Allocate vpi_time on heap to ensure it stays valid
        // (VPI spec says simulator copies data, but just to be safe)
        let mut vpi_time = Box::new(t_vpi_time {
            type_: vpiSimTime as _,
            high: (adjusted_delay >> 32) as _,
            low: (adjusted_delay & 0xFFFFFFFF) as _,
            real: 0.0,
        });

        let mut cb_data = s_cb_data {
            reason: cbAfterDelay as _,
            cb_rtn: Some(native_clock_toggle_callback),
            time: vpi_time.as_mut(),
            obj: std::ptr::null_mut(),
            user_data: self as *mut _ as *mut _,
            value: std::ptr::null_mut(),
            index: 0,
        };

        let new_hdl = unsafe { vpi_register_cb(&mut cb_data) };

        // Keep vpi_time alive until after vpi_register_cb returns
        // (Simulator should have copied the data by now)
        drop(vpi_time);
        if new_hdl.is_null() {
            // Failed to register callback
            if first_call {
                // Clean up: remove from active signals
                let signal_addr = self.signal_hdl as usize;
                get_active_signals().remove(&signal_addr);
            }
            return libc::EIO;
        }

        self.cb_handle = Some(new_hdl);
        0
    }
}

impl Drop for NativeClock {
    fn drop(&mut self) {
        self.stop();
    }
}

/// VPI callback handler for clock toggle.
///
/// This function is called by the simulator at the scheduled time to toggle
/// the clock and schedule the next toggle.
unsafe extern "C" fn native_clock_toggle_callback(cb_data: *mut t_cb_data) -> PLI_INT32 {
    let clock = &mut *((*cb_data).user_data as *mut NativeClock);

    // Mark that we're inside the callback (prevents premature destruction)
    clock.in_callback = true;

    // Clear the old callback handle (it's been triggered)
    clock.cb_handle = None;

    // Toggle and schedule next
    clock.toggle(false);

    // Mark callback complete
    clock.in_callback = false;

    // If destroy was requested while we were in the callback, do it now
    if clock.destroy_pending {
        // Drop the clock by reconstructing the Box
        let _ = Box::from_raw(clock as *mut NativeClock);
    }

    0
}

// ────────────────────────────────────────────────────────────────────────────────
// FFI Functions
// ────────────────────────────────────────────────────────────────────────────────

/// Create a new NativeClock instance.
///
/// # Arguments
/// * `complex_handle_raw` - ComplexHandleRaw from Lua (pointer to ComplexHandle)
///
/// # Returns
/// Opaque handle to the NativeClock instance
#[unsafe(no_mangle)]
pub extern "C" fn vpiml_native_clock_new(
    complex_handle_raw: ComplexHandleRaw,
) -> NativeClockHandle {
    // Extract the actual vpiHandle from the ComplexHandle
    let complex_handle = ComplexHandle::from_raw(&complex_handle_raw);
    let vpi_handle = complex_handle.vpi_handle;

    let clock = Box::new(NativeClock::new(vpi_handle));
    Box::into_raw(clock)
}

/// Start the clock with the specified timing parameters.
///
/// # Arguments
/// * `handle` - NativeClock handle from `vpiml_native_clock_new`
/// * `period` - Clock period in simulation time steps
/// * `high` - Number of steps the clock is high
/// * `start_high` - Whether to start with clock high (1) or low (0)
///
/// # Returns
/// * `0` - Success
/// * `libc::EBUSY` - Already running
/// * `libc::EEXIST` - Signal already driven by another NativeClock
/// * `libc::EINVAL` - Invalid parameters
/// * `libc::EIO` - VPI callback registration failed
#[unsafe(no_mangle)]
pub extern "C" fn vpiml_native_clock_start(
    handle: NativeClockHandle,
    period: u64,
    high: u64,
    start_high: u8,
) -> i32 {
    if handle.is_null() {
        return libc::EINVAL;
    }
    let clock = unsafe { &mut *handle };
    clock.start(period, high, start_high != 0)
}

/// Stop the clock.
///
/// # Arguments
/// * `handle` - NativeClock handle from `vpiml_native_clock_new`
#[unsafe(no_mangle)]
pub extern "C" fn vpiml_native_clock_stop(handle: NativeClockHandle) {
    if !handle.is_null() {
        let clock = unsafe { &mut *handle };
        clock.stop();
    }
}

/// Check if the clock is running.
///
/// # Arguments
/// * `handle` - NativeClock handle from `vpiml_native_clock_new`
///
/// # Returns
/// * `1` - Running
/// * `0` - Not running or invalid handle
#[unsafe(no_mangle)]
pub extern "C" fn vpiml_native_clock_is_running(handle: NativeClockHandle) -> u8 {
    if handle.is_null() {
        return 0;
    }
    let clock = unsafe { &*handle };
    clock.is_running() as u8
}

/// Destroy the NativeClock instance and free resources.
///
/// # Arguments
/// * `handle` - NativeClock handle from `vpiml_native_clock_new`
#[unsafe(no_mangle)]
pub extern "C" fn vpiml_native_clock_destroy(handle: NativeClockHandle) {
    if !handle.is_null() {
        let clock = unsafe { &mut *handle };

        // If we're inside the callback, defer destruction
        if clock.in_callback {
            clock.destroy_pending = true;
            // Also stop the clock to prevent further callbacks
            clock.stop();
            return;
        }

        let _ = unsafe { Box::from_raw(handle) };
    }
}

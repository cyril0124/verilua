//! Pure-Rust big-integer backend for `StrBitsUtils`. Every function is a
//! coarse-grained chain: one FFI call performs parse-hex -> operations ->
//! to-hex, so LuaJIT crosses the FFI boundary once per operation.
//!
//! Conventions:
//! - Input/output values are lowercase hex strings without `0x` prefix.
//! - Returned `*const c_char` points into a thread-local buffer that stays
//!   valid until the next call on the same thread; callers must copy it
//!   immediately (LuaJIT side does `ffi.string`).
//! - A null return means the input was not a valid hex string; the Lua caller
//!   asserts on it (no silent fallback).

#![allow(clippy::missing_safety_doc)]

use std::cell::RefCell;
use std::ffi::{c_char, CStr};

use num_bigint::BigUint;

thread_local! {
    static OUT_BUF: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

/// Hex digit -> value table; 0xff marks an invalid character.
static HEX_VAL: [u8; 256] = {
    let mut t = [0xffu8; 256];
    let mut i = 0u8;
    while i < 10 {
        t[(b'0' + i) as usize] = i;
        i += 1;
    }
    let mut j = 0u8;
    while j < 6 {
        t[(b'a' + j) as usize] = 10 + j;
        t[(b'A' + j) as usize] = 10 + j;
        j += 1;
    }
    t
};

const HEX_CHARS: &[u8; 16] = b"0123456789abcdef";

/// Parse a NUL-terminated hex string into a `BigUint`. Returns `None` on
/// invalid input (non-hex characters or empty string).
///
/// Hex is a power-of-two radix, so this is pure byte packing (nibble pairs ->
/// big-endian bytes -> `from_bytes_be`), avoiding num-bigint's generic radix
/// conversion which is much slower on wide values.
unsafe fn parse_hex(ptr: *const c_char) -> Option<BigUint> {
    if ptr.is_null() {
        return None;
    }
    let hex = unsafe { CStr::from_ptr(ptr) }.to_bytes();
    if hex.is_empty() {
        return None;
    }

    // Pack groups of 8 hex chars (from the least significant end) directly
    // into little-endian u32 digits.
    let mut digits = Vec::with_capacity(hex.len().div_ceil(8));
    let mut i = hex.len();
    while i > 0 {
        let start = i.saturating_sub(8);
        let mut d: u32 = 0;
        for &c in &hex[start..i] {
            let v = HEX_VAL[c as usize];
            if v == 0xff {
                return None;
            }
            d = (d << 4) | v as u32;
        }
        digits.push(d);
        i = start;
    }
    Some(BigUint::new(digits))
}

/// Store `value` as a lowercase hex string (no leading zeros, "0" for zero) in
/// the thread-local buffer and return a pointer to it (valid until the next
/// call on this thread). Byte unpacking for the same reason as `parse_hex`.
fn to_hex_ptr(value: &BigUint) -> *const c_char {
    OUT_BUF.with(|buf| {
        let mut buf = buf.borrow_mut();
        buf.clear();

        let digits: Vec<u32> = value.iter_u32_digits().collect();
        if digits.is_empty() {
            // Zero has no digits.
            buf.extend_from_slice(b"0\0");
            return buf.as_ptr() as *const c_char;
        }

        // Top digit is written without leading zeros; the rest use 8 nibbles.
        let top = *digits.last().unwrap();
        let top_nibbles = (32 - top.leading_zeros() as usize).div_ceil(4);
        let total = top_nibbles + (digits.len() - 1) * 8;
        buf.resize(total + 1, 0);

        let mut pos = 0;
        for k in (0..top_nibbles).rev() {
            buf[pos] = HEX_CHARS[((top >> (k * 4)) & 0xf) as usize];
            pos += 1;
        }
        for &d in digits[..digits.len() - 1].iter().rev() {
            for k in (0..8).rev() {
                buf[pos] = HEX_CHARS[((d >> (k * 4)) & 0xf) as usize];
                pos += 1;
            }
        }
        buf[pos] = 0;
        buf.as_ptr() as *const c_char
    })
}

fn mask_of(bits: u64) -> BigUint {
    (BigUint::from(1u32) << bits) - 1u32
}

/// Extract bits [s, e] (inclusive, 0-based LSB) as a hex string.
/// Caller guarantees s <= e.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_bitfield(hex: *const c_char, s: u64, e: u64) -> *const c_char {
    let Some(v) = (unsafe { parse_hex(hex) }) else {
        return std::ptr::null();
    };
    to_hex_ptr(&((v >> s) & mask_of(e - s + 1)))
}

/// Replace bits [s, e] (inclusive, 0-based LSB) with `val_hex` (trimmed to the
/// field width) and return the whole value as hex. Caller guarantees s <= e.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_set_bitfield(
    hex: *const c_char,
    s: u64,
    e: u64,
    val_hex: *const c_char,
) -> *const c_char {
    let (Some(v), Some(val)) = (unsafe { parse_hex(hex) }, unsafe { parse_hex(val_hex) }) else {
        return std::ptr::null();
    };
    let mask = mask_of(e - s + 1);
    // Clear the target field, then OR in the trimmed value.
    let cleared = &v ^ (&v & (&mask << s));
    to_hex_ptr(&(cleared | ((val & mask) << s)))
}

#[no_mangle]
pub unsafe extern "C" fn vl_bigint_lshift(hex: *const c_char, n: u64) -> *const c_char {
    let Some(v) = (unsafe { parse_hex(hex) }) else {
        return std::ptr::null();
    };
    to_hex_ptr(&(v << n))
}

#[no_mangle]
pub unsafe extern "C" fn vl_bigint_rshift(hex: *const c_char, n: u64) -> *const c_char {
    let Some(v) = (unsafe { parse_hex(hex) }) else {
        return std::ptr::null();
    };
    to_hex_ptr(&(v >> n))
}

macro_rules! gen_binop {
    ($name:ident, $op:tt) => {
        #[no_mangle]
        pub unsafe extern "C" fn $name(a: *const c_char, b: *const c_char) -> *const c_char {
            let (Some(x), Some(y)) = (unsafe { parse_hex(a) }, unsafe { parse_hex(b) }) else {
                return std::ptr::null();
            };
            to_hex_ptr(&(x $op y))
        }
    };
}

gen_binop!(vl_bigint_band, &);
gen_binop!(vl_bigint_bor, |);
gen_binop!(vl_bigint_bxor, ^);
gen_binop!(vl_bigint_add, +);

/// Bitwise NOT within `bitwidth` bits: `value XOR ((1 << bitwidth) - 1)`.
/// Caller guarantees the input already fits in `bitwidth` bits.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_bnot(hex: *const c_char, bitwidth: u64) -> *const c_char {
    let Some(v) = (unsafe { parse_hex(hex) }) else {
        return std::ptr::null();
    };
    to_hex_ptr(&(v ^ mask_of(bitwidth)))
}

/// Count set bits. Returns u64::MAX on invalid input.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_popcount(hex: *const c_char) -> u64 {
    let Some(v) = (unsafe { parse_hex(hex) }) else {
        return u64::MAX;
    };
    v.count_ones()
}

//! Pure-Rust big-integer backend for `StrBitsUtils`.
//!
//! Every function is a coarse-grained chain: one FFI call performs hex parse ->
//! operation -> hex formatting, so LuaJIT crosses the FFI boundary once per
//! operation.
//!
//! Conventions:
//! - Input and output values are hex strings without a `0x` prefix; output is
//!   lowercase and inputs may mix cases.
//! - A returned `*const c_char` points into a thread-local buffer that stays
//!   valid until the next call on the same thread, so callers must copy it
//!   immediately (the LuaJIT side calls `ffi.string`).
//! - A null return means an argument was not a valid hex string; the Lua caller
//!   reports that as an error instead of falling back silently.
//!
//! # Safety contract
//!
//! Every exported function only reads its `*const c_char` arguments, treating
//! null as invalid input and rejecting non-hex bytes by returning null.
//!
//! # Why unsafe code is required
//!
//! The crate exposes a C ABI to LuaJIT FFI, which needs `extern "C"` functions
//! over raw pointers. The unsafe surface is the C string read in
//! `parse_hex_argument`: all arithmetic and hex packing runs in safe code.
#![deny(unsafe_op_in_unsafe_fn)]
#![deny(clippy::undocumented_unsafe_blocks)]

use std::cell::RefCell;
use std::ffi::{c_char, CStr};
use std::ptr;

use num_bigint::BigUint;

/// Value in [`HEX_VALUE`] that marks a byte as a non-hex digit.
const INVALID_HEX_DIGIT: u8 = 0xff;

/// Hex digits carried by one 32-bit limb of a [`BigUint`].
const HEX_DIGITS_PER_LIMB: usize = 8;

/// Bits carried by one hex digit.
const BITS_PER_HEX_DIGIT: usize = 4;

/// Lowercase hex alphabet; uppercase digits fold onto the same table entries.
const HEX_DIGITS: &[u8; 16] = b"0123456789abcdef";

/// Returned by [`vl_bigint_popcount`] when its argument is not valid hex.
const INVALID_POPCOUNT: u64 = u64::MAX;

/// Byte -> hex digit value; [`INVALID_HEX_DIGIT`] marks a non-hex byte.
static HEX_VALUE: [u8; 256] = {
    let mut table = [INVALID_HEX_DIGIT; 256];
    let mut value = 0u8;
    while value < 16 {
        let digit = HEX_DIGITS[value as usize];
        table[digit as usize] = value;
        // Digits have no case, so upper-casing them maps back to themselves.
        table[digit.to_ascii_uppercase() as usize] = value;
        value += 1;
    }
    table
};

thread_local! {
    /// Scratch buffer for formatted output, reused across calls on one thread.
    static OUTPUT_BUFFER: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

/// Parses a NUL-terminated hex argument into a [`BigUint`].
///
/// # Safety
///
/// `hex` must be null or point to a NUL-terminated buffer that stays readable
/// for the duration of the call.
unsafe fn parse_hex_argument(hex: *const c_char) -> Option<BigUint> {
    if hex.is_null() {
        return None;
    }
    // SAFETY: the caller guarantees a NUL-terminated buffer.
    let bytes = unsafe { CStr::from_ptr(hex) }.to_bytes();
    parse_hex_bytes(bytes)
}

/// Parses hex digit bytes into a [`BigUint`]; `None` for empty input or a byte
/// that is not a hex digit.
///
/// Hex is a power-of-two radix, so this is pure byte packing: nibble pairs ->
/// 32-bit limbs -> [`BigUint::new`]. That is one shift-or per digit; num-bigint's
/// generic radix conversion instead multiplies and adds per digit, so its cost
/// grows quadratically with the digit count.
fn parse_hex_bytes(hex: &[u8]) -> Option<BigUint> {
    if hex.is_empty() {
        return None;
    }

    // Pack from the least significant end, one limb per 8 hex digits.
    let mut limbs = Vec::with_capacity(hex.len().div_ceil(HEX_DIGITS_PER_LIMB));
    let mut end = hex.len();
    while end > 0 {
        let start = end.saturating_sub(HEX_DIGITS_PER_LIMB);
        let mut limb: u32 = 0;
        for &byte in &hex[start..end] {
            let value = HEX_VALUE[byte as usize];
            if value == INVALID_HEX_DIGIT {
                return None;
            }
            limb = (limb << BITS_PER_HEX_DIGIT) | u32::from(value);
        }
        limbs.push(limb);
        end = start;
    }
    Some(BigUint::new(limbs))
}

/// Formats `value` as lowercase hex into [`OUTPUT_BUFFER`] and returns a pointer
/// to it, valid until the next call on this thread.
///
/// Unpacking 32-bit limbs to nibbles mirrors [`parse_hex_bytes`] and avoids the
/// generic radix conversion for the same reason.
fn to_hex_ptr(value: &BigUint) -> *const c_char {
    OUTPUT_BUFFER.with(|buffer| {
        let mut buffer = buffer.borrow_mut();
        buffer.clear();

        let limbs: Vec<u32> = value.iter_u32_digits().collect();
        let Some(&top_limb) = limbs.last() else {
            // Zero has no limbs and prints as a single digit.
            buffer.extend_from_slice(b"0\0");
            return buffer.as_ptr().cast::<c_char>();
        };

        // The top limb prints without leading zeros; every lower limb prints all
        // of its digits.
        let top_limb_digits = hex_digit_count(top_limb);
        let lower_limbs = &limbs[..limbs.len() - 1];
        buffer.resize(
            top_limb_digits + lower_limbs.len() * HEX_DIGITS_PER_LIMB + 1,
            0,
        );

        let mut position = 0;
        for index in (0..top_limb_digits).rev() {
            buffer[position] = HEX_DIGITS[hex_digit_at(top_limb, index)];
            position += 1;
        }
        for &limb in lower_limbs.iter().rev() {
            for index in (0..HEX_DIGITS_PER_LIMB).rev() {
                buffer[position] = HEX_DIGITS[hex_digit_at(limb, index)];
                position += 1;
            }
        }
        // Close the string: the ABI hands this buffer out as a C string.
        buffer[position] = 0;
        buffer.as_ptr().cast::<c_char>()
    })
}

/// Number of hex digits `value` needs when printed without leading zeros.
fn hex_digit_count(value: u32) -> usize {
    let significant_bits = (u32::BITS - value.leading_zeros()) as usize;
    significant_bits.div_ceil(BITS_PER_HEX_DIGIT)
}

/// Hex digit value `index` positions above the least significant digit of
/// `limb`.
fn hex_digit_at(limb: u32, index: usize) -> usize {
    ((limb >> (index * BITS_PER_HEX_DIGIT)) & 0xf) as usize
}

/// Returns the mask of the low `bits` bits, `(1 << bits) - 1`; a zero-width
/// field yields an empty mask.
fn mask_of(bits: u64) -> BigUint {
    (BigUint::from(1u32) << bits) - 1u32
}

/// Applies `operation` to both hex arguments and formats the result.
///
/// # Safety
///
/// `left` and `right` must be null or NUL-terminated buffers.
unsafe fn binary_operation(
    left: *const c_char,
    right: *const c_char,
    operation: impl FnOnce(BigUint, BigUint) -> BigUint,
) -> *const c_char {
    // SAFETY: the caller guarantees both arguments are NUL-terminated buffers.
    let Some(left) = (unsafe { parse_hex_argument(left) }) else {
        return ptr::null();
    };
    // SAFETY: the caller guarantees both arguments are NUL-terminated buffers.
    let Some(right) = (unsafe { parse_hex_argument(right) }) else {
        return ptr::null();
    };
    to_hex_ptr(&operation(left, right))
}

/// Extracts bits `[s, e]` (inclusive, 0-based from the least significant bit) as
/// a hex string.
///
/// `s <= e` is required; the Lua wrapper rejects reversed or out-of-width
/// ranges before calling.
///
/// # Safety
///
/// `hex` must be null or a NUL-terminated buffer.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_bitfield(hex: *const c_char, s: u64, e: u64) -> *const c_char {
    // SAFETY: the caller guarantees a NUL-terminated buffer.
    let Some(value) = (unsafe { parse_hex_argument(hex) }) else {
        return ptr::null();
    };
    to_hex_ptr(&((value >> s) & mask_of(e - s + 1)))
}

/// Replaces bits `[s, e]` (inclusive, 0-based from the LSB) with `val_hex`
/// trimmed to the field width, and returns the whole value as hex.
///
/// `s <= e` is required; the Lua wrapper rejects reversed or out-of-width
/// ranges before calling.
///
/// # Safety
///
/// `hex` and `val_hex` must be null or NUL-terminated buffers.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_set_bitfield(
    hex: *const c_char,
    s: u64,
    e: u64,
    val_hex: *const c_char,
) -> *const c_char {
    // SAFETY: the caller guarantees both arguments are NUL-terminated buffers.
    let Some(value) = (unsafe { parse_hex_argument(hex) }) else {
        return ptr::null();
    };
    // SAFETY: the caller guarantees both arguments are NUL-terminated buffers.
    let Some(field) = (unsafe { parse_hex_argument(val_hex) }) else {
        return ptr::null();
    };
    let mask = mask_of(e - s + 1);
    // Clear the target field, then OR in the value trimmed to the field width.
    let cleared = &value ^ (&value & (&mask << s));
    to_hex_ptr(&(cleared | ((field & mask) << s)))
}

/// Shifts `hex` left by `n` bits.
///
/// # Safety
///
/// `hex` must be null or a NUL-terminated buffer.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_lshift(hex: *const c_char, n: u64) -> *const c_char {
    // SAFETY: the caller guarantees a NUL-terminated buffer.
    let Some(value) = (unsafe { parse_hex_argument(hex) }) else {
        return ptr::null();
    };
    to_hex_ptr(&(value << n))
}

/// Shifts `hex` right by `n` bits.
///
/// # Safety
///
/// `hex` must be null or a NUL-terminated buffer.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_rshift(hex: *const c_char, n: u64) -> *const c_char {
    // SAFETY: the caller guarantees a NUL-terminated buffer.
    let Some(value) = (unsafe { parse_hex_argument(hex) }) else {
        return ptr::null();
    };
    to_hex_ptr(&(value >> n))
}

/// Bitwise AND of two hex values.
///
/// # Safety
///
/// `a` and `b` must be null or NUL-terminated buffers.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_band(a: *const c_char, b: *const c_char) -> *const c_char {
    // SAFETY: both arguments are NUL-terminated buffers.
    unsafe { binary_operation(a, b, |left, right| left & right) }
}

/// Bitwise OR of two hex values.
///
/// # Safety
///
/// `a` and `b` must be null or NUL-terminated buffers.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_bor(a: *const c_char, b: *const c_char) -> *const c_char {
    // SAFETY: both arguments are NUL-terminated buffers.
    unsafe { binary_operation(a, b, |left, right| left | right) }
}

/// Bitwise XOR of two hex values.
///
/// # Safety
///
/// `a` and `b` must be null or NUL-terminated buffers.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_bxor(a: *const c_char, b: *const c_char) -> *const c_char {
    // SAFETY: both arguments are NUL-terminated buffers.
    unsafe { binary_operation(a, b, |left, right| left ^ right) }
}

/// Sum of two hex values.
///
/// # Safety
///
/// `a` and `b` must be null or NUL-terminated buffers.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_add(a: *const c_char, b: *const c_char) -> *const c_char {
    // SAFETY: both arguments are NUL-terminated buffers.
    unsafe { binary_operation(a, b, |left, right| left + right) }
}

/// Bitwise NOT within `bitwidth` bits: `value XOR ((1 << bitwidth) - 1)`.
///
/// Input wider than `bitwidth` keeps its high bits, since only the low field is
/// inverted.
///
/// # Safety
///
/// `hex` must be null or a NUL-terminated buffer.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_bnot(hex: *const c_char, bitwidth: u64) -> *const c_char {
    // SAFETY: the caller guarantees a NUL-terminated buffer.
    let Some(value) = (unsafe { parse_hex_argument(hex) }) else {
        return ptr::null();
    };
    to_hex_ptr(&(value ^ mask_of(bitwidth)))
}

/// Counts the set bits of a hex value, or `u64::MAX` when the argument is not
/// valid hex.
///
/// # Safety
///
/// `hex` must be null or a NUL-terminated buffer.
#[no_mangle]
pub unsafe extern "C" fn vl_bigint_popcount(hex: *const c_char) -> u64 {
    // SAFETY: the caller guarantees a NUL-terminated buffer.
    let Some(value) = (unsafe { parse_hex_argument(hex) }) else {
        return INVALID_POPCOUNT;
    };
    value.count_ones()
}

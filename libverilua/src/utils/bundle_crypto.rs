//! AES-256-GCM envelope for bundled LuaJIT bytecode.
//!
//! File format:
//! `VLBC | ver:u8 | nonce:12 | tag:16 | ciphertext`
//!
//! The key is baked in at compile time via `VL_BUNDLE_KEY_HEX`.
//! Exactly 64 hex chars is used as the raw AES-256 key; any other non-empty
//! string is SHA-256'd to 32 bytes. Never read at simulation runtime.
//! Builds without the env var still link; seal/unseal return `VL_BUNDLE_ERR_NO_KEY`.

use aes_gcm::aead::{AeadInPlace, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use rand::RngCore;
use sha2::{Digest, Sha256};
use std::ptr;

pub const MAGIC: &[u8; 4] = b"VLBC";
pub const VERSION: u8 = 1;
pub const NONCE_LEN: usize = 12;
pub const TAG_LEN: usize = 16;
pub const HEADER_LEN: usize = 4 + 1 + NONCE_LEN + TAG_LEN;

pub const VL_BUNDLE_OK: i32 = 0;
pub const VL_BUNDLE_ERR_NO_KEY: i32 = -1;
pub const VL_BUNDLE_ERR_ARGS: i32 = -2;
pub const VL_BUNDLE_ERR_BUF: i32 = -3;
pub const VL_BUNDLE_ERR_FORMAT: i32 = -4;
pub const VL_BUNDLE_ERR_AUTH: i32 = -5;

/// Seal overhead: header plus GCM tag sitting in the header.
pub fn sealed_len(plain_len: usize) -> usize {
    HEADER_LEN + plain_len
}

fn parse_raw_hex64(hex: &str) -> Result<[u8; 32], &'static str> {
    let mut key = [0u8; 32];
    for i in 0..32 {
        key[i] = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16)
            .map_err(|_| "VL_BUNDLE_KEY_HEX raw key must be hexadecimal")?;
    }
    Ok(key)
}

/// 64 hex digits → raw AES-256 key. Anything else → SHA-256(utf8).
pub fn parse_key_material(input: &str) -> Result<[u8; 32], &'static str> {
    let input = input.trim();
    if input.is_empty() {
        return Err("VL_BUNDLE_KEY_HEX is empty");
    }
    if input.len() == 64 && input.bytes().all(|b| b.is_ascii_hexdigit()) {
        return parse_raw_hex64(input);
    }
    let digest = Sha256::digest(input.as_bytes());
    let mut key = [0u8; 32];
    key.copy_from_slice(&digest);
    Ok(key)
}

pub fn compiled_key() -> Option<[u8; 32]> {
    option_env!("VL_BUNDLE_KEY_HEX").map(|raw| {
        parse_key_material(raw).unwrap_or_else(|e| panic!("invalid VL_BUNDLE_KEY_HEX: {e}"))
    })
}

pub fn seal_with_key(key: &[u8; 32], plain: &[u8]) -> Vec<u8> {
    let cipher = Aes256Gcm::new_from_slice(key).expect("AES-256 key");
    let mut nonce = [0u8; NONCE_LEN];
    rand::rng().fill_bytes(&mut nonce);

    let mut body = plain.to_vec();
    let tag = cipher
        .encrypt_in_place_detached(Nonce::from_slice(&nonce), b"", &mut body)
        .expect("aes-gcm encrypt");

    let mut out = Vec::with_capacity(sealed_len(plain.len()));
    out.extend_from_slice(MAGIC);
    out.push(VERSION);
    out.extend_from_slice(&nonce);
    out.extend_from_slice(tag.as_slice());
    out.extend_from_slice(&body);
    out
}

pub fn unseal_with_key(key: &[u8; 32], blob: &[u8]) -> Result<Vec<u8>, i32> {
    if blob.len() < HEADER_LEN {
        return Err(VL_BUNDLE_ERR_FORMAT);
    }
    if &blob[0..4] != MAGIC {
        return Err(VL_BUNDLE_ERR_FORMAT);
    }
    if blob[4] != VERSION {
        return Err(VL_BUNDLE_ERR_FORMAT);
    }
    let nonce = &blob[5..5 + NONCE_LEN];
    let tag = &blob[5 + NONCE_LEN..5 + NONCE_LEN + TAG_LEN];
    let mut body = blob[HEADER_LEN..].to_vec();

    let cipher = Aes256Gcm::new_from_slice(key).expect("AES-256 key");
    cipher
        .decrypt_in_place_detached(
            Nonce::from_slice(nonce),
            b"",
            &mut body,
            aes_gcm::Tag::from_slice(tag),
        )
        .map_err(|_| VL_BUNDLE_ERR_AUTH)?;
    Ok(body)
}

unsafe fn copy_out(src: &[u8], output: *mut u8, output_cap: usize, output_len: *mut usize) -> i32 {
    if output_len.is_null() {
        return VL_BUNDLE_ERR_ARGS;
    }
    unsafe {
        *output_len = src.len();
    }
    if output.is_null() {
        return VL_BUNDLE_ERR_ARGS;
    }
    if output_cap < src.len() {
        return VL_BUNDLE_ERR_BUF;
    }
    unsafe {
        ptr::copy_nonoverlapping(src.as_ptr(), output, src.len());
    }
    VL_BUNDLE_OK
}

/// Seal `input` with the compile-time key.
///
/// Returns `0` on success. `*output_len` is always set to the required size
/// when `output_len` is non-null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vl_bundle_seal(
    input: *const u8,
    input_len: usize,
    output: *mut u8,
    output_cap: usize,
    output_len: *mut usize,
) -> i32 {
    let Some(key) = compiled_key() else {
        return VL_BUNDLE_ERR_NO_KEY;
    };
    if input.is_null() && input_len != 0 {
        return VL_BUNDLE_ERR_ARGS;
    }
    let plain = if input_len == 0 {
        &[][..]
    } else {
        unsafe { std::slice::from_raw_parts(input, input_len) }
    };
    let sealed = seal_with_key(&key, plain);
    unsafe { copy_out(&sealed, output, output_cap, output_len) }
}

/// Unseal `input` with the compile-time key.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vl_bundle_unseal(
    input: *const u8,
    input_len: usize,
    output: *mut u8,
    output_cap: usize,
    output_len: *mut usize,
) -> i32 {
    let Some(key) = compiled_key() else {
        return VL_BUNDLE_ERR_NO_KEY;
    };
    if input.is_null() || input_len == 0 {
        return VL_BUNDLE_ERR_ARGS;
    }
    let blob = unsafe { std::slice::from_raw_parts(input, input_len) };
    match unseal_with_key(&key, blob) {
        Ok(plain) => unsafe { copy_out(&plain, output, output_cap, output_len) },
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::parse_key_material;

    #[test]
    fn raw_hex64_is_not_hashed() {
        let hex = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        let key = parse_key_material(hex).unwrap();
        assert_eq!(key[0], 0x00);
        assert_eq!(key[1], 0x11);
        assert_eq!(key[31], 0xff);
    }

    #[test]
    fn short_passphrase_is_sha256() {
        // echo -n hello | sha256sum
        let expect = hex_key("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
        assert_eq!(parse_key_material("hello").unwrap(), expect);
        assert_eq!(parse_key_material(" hello ").unwrap(), expect);
        assert_ne!(parse_key_material("world").unwrap(), expect);
    }

    #[test]
    fn empty_is_error() {
        assert!(parse_key_material("").is_err());
        assert!(parse_key_material("   ").is_err());
    }

    fn hex_key(hex: &str) -> [u8; 32] {
        super::parse_raw_hex64(hex).unwrap()
    }
}

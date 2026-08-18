//! Minimal SQLite-subset C ABI over Turso (`turso_sdk_kit` rsapi).
//! Used by LuaDataBaseV2 via LuaJIT FFI.
//!
//! # Safety
//!
//! All exported functions share one contract:
//! - `db` / `stmt` handles must be pointers returned by [`turso_ffi_open`] /
//!   [`turso_ffi_prepare`] of this library. Null, closed, finalized, or foreign
//!   pointers are rejected via the live-handle registries and report an error
//!   instead of being dereferenced.
//! - C string arguments must be valid NUL-terminated buffers; `text` with
//!   `len >= 0` must point to at least `len` readable bytes.
//! - Returned strings (`errmsg` / `column_text`) are owned by the library and
//!   only valid until the next call on the same handle.
// The shared contract above replaces per-function `# Safety` sections.
#![allow(clippy::missing_safety_doc)]

use std::collections::HashSet;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::{Arc, Mutex, OnceLock};

use turso_core::{IOResult, Numeric};
use turso_sdk_kit::rsapi::{
    TursoConnection, TursoDatabase, TursoDatabaseConfig, TursoError, TursoStatement,
    TursoStatusCode, Value,
};
use turso_sdk_kit::IoBackend;

pub const TURSO_FFI_OK: c_int = 0;
pub const TURSO_FFI_ROW: c_int = 100;
pub const TURSO_FFI_DONE: c_int = 101;
pub const TURSO_FFI_ERR: c_int = 1;

/// Last error when no live `Db` handle exists (e.g. open failure).
static LAST_GLOBAL_ERR: OnceLock<Mutex<(String, CString)>> = OnceLock::new();
static LIVE_DBS: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
static LIVE_STMTS: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();

fn global_err_slot() -> &'static Mutex<(String, CString)> {
    LAST_GLOBAL_ERR.get_or_init(|| Mutex::new((String::new(), CString::default())))
}

fn live_dbs() -> &'static Mutex<HashSet<usize>> {
    LIVE_DBS.get_or_init(|| Mutex::new(HashSet::new()))
}

fn live_stmts() -> &'static Mutex<HashSet<usize>> {
    LIVE_STMTS.get_or_init(|| Mutex::new(HashSet::new()))
}

fn set_global_err(msg: impl Into<String>) {
    let msg = msg.into();
    let c = CString::new(msg.replace('\0', "")).unwrap_or_default();
    if let Ok(mut g) = global_err_slot().lock() {
        *g = (msg, c);
    }
}

fn clear_global_err() {
    if let Ok(mut g) = global_err_slot().lock() {
        *g = (String::new(), CString::default());
    }
}

fn register_db(p: *mut Db) {
    if let Ok(mut s) = live_dbs().lock() {
        s.insert(p as usize);
    }
}

fn unregister_db(p: *mut Db) -> bool {
    live_dbs()
        .lock()
        .map(|mut s| s.remove(&(p as usize)))
        .unwrap_or(false)
}

fn is_live_db(p: *mut Db) -> bool {
    if p.is_null() {
        return false;
    }
    live_dbs()
        .lock()
        .map(|s| s.contains(&(p as usize)))
        .unwrap_or(false)
}

fn register_stmt(p: *mut Stmt) {
    if let Ok(mut s) = live_stmts().lock() {
        s.insert(p as usize);
    }
}

fn unregister_stmt(p: *mut Stmt) -> bool {
    live_stmts()
        .lock()
        .map(|mut s| s.remove(&(p as usize)))
        .unwrap_or(false)
}

fn is_live_stmt(p: *mut Stmt) -> bool {
    if p.is_null() {
        return false;
    }
    live_stmts()
        .lock()
        .map(|s| s.contains(&(p as usize)))
        .unwrap_or(false)
}

struct Db {
    _database: Arc<TursoDatabase>,
    conn: Arc<TursoConnection>,
    errmsg: String,
    errmsg_c: CString,
    /// Scratch for column_text; valid until next column_text on this db.
    col_text_c: CString,
}

struct Stmt {
    db: *mut Db,
    stmt: Box<TursoStatement>,
}

fn set_err(db: &mut Db, err: TursoError) {
    set_err_str(db, err.to_string());
}

fn set_err_str(db: &mut Db, msg: impl Into<String>) {
    db.errmsg = msg.into();
    db.errmsg_c = CString::new(db.errmsg.as_str().replace('\0', "")).unwrap_or_default();
    set_global_err(db.errmsg.clone());
}

fn cstr_to_str<'a>(p: *const c_char) -> Result<&'a str, String> {
    if p.is_null() {
        return Err("null string".into());
    }
    unsafe { CStr::from_ptr(p) }
        .to_str()
        .map_err(|e| e.to_string())
}

fn open_db(path: &str) -> Result<Db, String> {
    let database = TursoDatabase::new(TursoDatabaseConfig {
        path: path.to_string(),
        experimental_features: None,
        async_io: false,
        encryption: None,
        vfs: IoBackend::Default,
        io: None,
        db_file: None,
    });
    match database.open().map_err(|e| e.to_string())? {
        IOResult::Done(()) => {}
        IOResult::IO(_) => return Err("open returned pending IO with async_io=false".into()),
    }
    let conn = database.connect().map_err(|e| e.to_string())?;
    Ok(Db {
        _database: database,
        conn,
        errmsg: String::new(),
        errmsg_c: CString::default(),
        col_text_c: CString::default(),
    })
}

/// Execute all statements in `sql` (multi-statement supported).
fn exec_sql(db: &mut Db, sql: &str) -> Result<(), String> {
    let mut remaining = sql;
    loop {
        let trimmed = remaining.trim();
        if trimmed.is_empty() {
            break;
        }
        let prepared = db
            .conn
            .prepare_first(remaining)
            .map_err(|e| e.to_string())?;
        let Some((mut stmt, tail)) = prepared else {
            break;
        };
        match stmt.execute(None) {
            Ok(result) => {
                if result.status != TursoStatusCode::Done {
                    let _ = stmt.finalize(None);
                    return Err(format!("execute status: {:?}", result.status));
                }
            }
            Err(e) => {
                let _ = stmt.finalize(None);
                return Err(e.to_string());
            }
        }
        match stmt.finalize(None) {
            Ok(TursoStatusCode::Done) => {}
            Ok(other) => return Err(format!("finalize status: {other:?}")),
            Err(e) => return Err(e.to_string()),
        }
        if tail >= remaining.len() {
            break;
        }
        remaining = &remaining[tail..];
    }
    Ok(())
}

unsafe fn db_mut(db: *mut c_void) -> Option<&'static mut Db> {
    let p = db as *mut Db;
    if !is_live_db(p) {
        return None;
    }
    Some(&mut *p)
}

unsafe fn stmt_mut(stmt: *mut c_void) -> Option<&'static mut Stmt> {
    let p = stmt as *mut Stmt;
    if !is_live_stmt(p) {
        return None;
    }
    let s = &mut *p;
    if !is_live_db(s.db) {
        return None;
    }
    Some(s)
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_open(path: *const c_char, out_db: *mut *mut c_void) -> c_int {
    if out_db.is_null() {
        set_global_err("out_db is null");
        return TURSO_FFI_ERR;
    }
    *out_db = ptr::null_mut();
    let path = match cstr_to_str(path) {
        Ok(s) => s,
        Err(e) => {
            set_global_err(e);
            return TURSO_FFI_ERR;
        }
    };
    match open_db(path) {
        Ok(db) => {
            clear_global_err();
            let raw = Box::into_raw(Box::new(db));
            register_db(raw);
            *out_db = raw as *mut c_void;
            TURSO_FFI_OK
        }
        Err(e) => {
            set_global_err(e);
            TURSO_FFI_ERR
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_close(db: *mut c_void) -> c_int {
    let p = db as *mut Db;
    if !unregister_db(p) {
        set_global_err("close: null or already closed db");
        return TURSO_FFI_ERR;
    }
    let boxed = Box::from_raw(p);
    match boxed.conn.close() {
        Ok(()) => {
            clear_global_err();
            TURSO_FFI_OK
        }
        Err(e) => {
            set_global_err(e.to_string());
            TURSO_FFI_ERR
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_exec(db: *mut c_void, sql: *const c_char) -> c_int {
    let Some(db) = db_mut(db) else {
        set_global_err("exec: null or closed db");
        return TURSO_FFI_ERR;
    };
    let sql = match cstr_to_str(sql) {
        Ok(s) => s,
        Err(e) => {
            set_err_str(db, e);
            return TURSO_FFI_ERR;
        }
    };
    match exec_sql(db, sql) {
        Ok(()) => {
            db.errmsg.clear();
            db.errmsg_c = CString::default();
            clear_global_err();
            TURSO_FFI_OK
        }
        Err(e) => {
            set_err_str(db, e);
            TURSO_FFI_ERR
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_prepare(
    db: *mut c_void,
    sql: *const c_char,
    out_stmt: *mut *mut c_void,
) -> c_int {
    if out_stmt.is_null() {
        set_global_err("prepare: out_stmt is null");
        return TURSO_FFI_ERR;
    }
    *out_stmt = ptr::null_mut();
    let db_ptr = db as *mut Db;
    let Some(db_ref) = db_mut(db) else {
        set_global_err("prepare: null or closed db");
        return TURSO_FFI_ERR;
    };
    let sql = match cstr_to_str(sql) {
        Ok(s) => s,
        Err(e) => {
            set_err_str(db_ref, e);
            return TURSO_FFI_ERR;
        }
    };
    match db_ref.conn.prepare_single(sql) {
        Ok(stmt) => {
            db_ref.errmsg.clear();
            db_ref.errmsg_c = CString::default();
            clear_global_err();
            let raw = Box::into_raw(Box::new(Stmt { db: db_ptr, stmt }));
            register_stmt(raw);
            *out_stmt = raw as *mut c_void;
            TURSO_FFI_OK
        }
        Err(e) => {
            set_err(db_ref, e);
            TURSO_FFI_ERR
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_bind_int(stmt: *mut c_void, idx: c_int, value: i64) -> c_int {
    if idx <= 0 {
        set_global_err("bind_int: index must be >= 1");
        return TURSO_FFI_ERR;
    }
    let Some(stmt) = stmt_mut(stmt) else {
        set_global_err("bind_int: null/finalized stmt or closed db");
        return TURSO_FFI_ERR;
    };
    match stmt
        .stmt
        .bind_positional(idx as usize, Value::from_i64(value))
    {
        Ok(()) => TURSO_FFI_OK,
        Err(e) => {
            if is_live_db(stmt.db) {
                set_err(&mut *stmt.db, e);
            } else {
                set_global_err(e.to_string());
            }
            TURSO_FFI_ERR
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_bind_text(
    stmt: *mut c_void,
    idx: c_int,
    text: *const c_char,
    len: c_int,
) -> c_int {
    if idx <= 0 || text.is_null() {
        set_global_err("bind_text: bad args");
        return TURSO_FFI_ERR;
    }
    let Some(stmt) = stmt_mut(stmt) else {
        set_global_err("bind_text: null/finalized stmt or closed db");
        return TURSO_FFI_ERR;
    };
    let s = if len < 0 {
        match cstr_to_str(text) {
            Ok(v) => v.to_string(),
            Err(e) => {
                if is_live_db(stmt.db) {
                    set_err_str(&mut *stmt.db, e);
                } else {
                    set_global_err(e);
                }
                return TURSO_FFI_ERR;
            }
        }
    } else {
        let bytes = std::slice::from_raw_parts(text as *const u8, len as usize);
        match std::str::from_utf8(bytes) {
            Ok(v) => v.to_string(),
            Err(e) => {
                if is_live_db(stmt.db) {
                    set_err_str(&mut *stmt.db, e.to_string());
                } else {
                    set_global_err(e.to_string());
                }
                return TURSO_FFI_ERR;
            }
        }
    };
    match stmt
        .stmt
        .bind_positional(idx as usize, Value::build_text(s))
    {
        Ok(()) => TURSO_FFI_OK,
        Err(e) => {
            if is_live_db(stmt.db) {
                set_err(&mut *stmt.db, e);
            } else {
                set_global_err(e.to_string());
            }
            TURSO_FFI_ERR
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_step(stmt: *mut c_void) -> c_int {
    let Some(stmt) = stmt_mut(stmt) else {
        set_global_err("step: null/finalized stmt or closed db");
        return TURSO_FFI_ERR;
    };
    match stmt.stmt.step(None) {
        Ok(TursoStatusCode::Row) => TURSO_FFI_ROW,
        Ok(TursoStatusCode::Done) => TURSO_FFI_DONE,
        Ok(other) => {
            if is_live_db(stmt.db) {
                set_err_str(&mut *stmt.db, format!("step status: {other:?}"));
            } else {
                set_global_err(format!("step status: {other:?}"));
            }
            TURSO_FFI_ERR
        }
        Err(e) => {
            if is_live_db(stmt.db) {
                set_err(&mut *stmt.db, e);
            } else {
                set_global_err(e.to_string());
            }
            TURSO_FFI_ERR
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_reset(stmt: *mut c_void) -> c_int {
    let Some(stmt) = stmt_mut(stmt) else {
        set_global_err("reset: null/finalized stmt or closed db");
        return TURSO_FFI_ERR;
    };
    match stmt.stmt.reset() {
        Ok(()) => TURSO_FFI_OK,
        Err(e) => {
            if is_live_db(stmt.db) {
                set_err(&mut *stmt.db, e);
            } else {
                set_global_err(e.to_string());
            }
            TURSO_FFI_ERR
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_finalize(stmt: *mut c_void) -> c_int {
    let p = stmt as *mut Stmt;
    if !unregister_stmt(p) {
        set_global_err("finalize: null or already finalized stmt");
        return TURSO_FFI_ERR;
    }
    let mut boxed = Box::from_raw(p);
    let db_ptr = boxed.db;
    match boxed.stmt.finalize(None) {
        Ok(TursoStatusCode::Done) => {
            clear_global_err();
            TURSO_FFI_OK
        }
        Ok(other) => {
            let msg = format!("finalize status: {other:?}");
            if is_live_db(db_ptr) {
                set_err_str(&mut *db_ptr, msg);
            } else {
                set_global_err(msg);
            }
            TURSO_FFI_ERR
        }
        Err(e) => {
            if is_live_db(db_ptr) {
                set_err(&mut *db_ptr, e);
            } else {
                set_global_err(e.to_string());
            }
            TURSO_FFI_ERR
        }
    }
}

/// Error message for the given db, or the last global error if `db` is null/closed.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_errmsg(db: *mut c_void) -> *const c_char {
    let p = db as *mut Db;
    if is_live_db(p) {
        return (*p).errmsg_c.as_ptr();
    }
    if let Ok(g) = global_err_slot().lock() {
        return g.1.as_ptr();
    }
    c"".as_ptr()
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_column_int(stmt: *mut c_void, idx: c_int) -> i64 {
    if idx < 0 {
        set_global_err("column_int: index must be >= 0");
        return 0;
    }
    let Some(stmt) = stmt_mut(stmt) else {
        set_global_err("column_int: null/finalized stmt or closed db");
        return 0;
    };
    match stmt.stmt.row_value(idx as usize) {
        Ok(Value::Numeric(Numeric::Integer(v))) => v,
        Ok(Value::Numeric(Numeric::Float(v))) => f64::from(v) as i64,
        Ok(_) => {
            if is_live_db(stmt.db) {
                set_err_str(&mut *stmt.db, "column_int: value is not numeric");
            }
            0
        }
        Err(e) => {
            if is_live_db(stmt.db) {
                set_err(&mut *stmt.db, e);
            } else {
                set_global_err(e.to_string());
            }
            0
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn turso_ffi_column_text(stmt: *mut c_void, idx: c_int) -> *const c_char {
    if idx < 0 {
        set_global_err("column_text: index must be >= 0");
        return c"".as_ptr();
    }
    let Some(stmt) = stmt_mut(stmt) else {
        set_global_err("column_text: null/finalized stmt or closed db");
        return c"".as_ptr();
    };
    let s = match stmt.stmt.row_value(idx as usize) {
        Ok(Value::Text(t)) => t.as_str().to_string(),
        Ok(Value::Numeric(Numeric::Integer(v))) => v.to_string(),
        Ok(Value::Numeric(Numeric::Float(v))) => f64::from(v).to_string(),
        Ok(Value::Null) => {
            if is_live_db(stmt.db) {
                set_err_str(&mut *stmt.db, "column_text: NULL");
            }
            return c"".as_ptr();
        }
        Ok(_) => {
            if is_live_db(stmt.db) {
                set_err_str(&mut *stmt.db, "column_text: unsupported type");
            }
            return c"".as_ptr();
        }
        Err(e) => {
            if is_live_db(stmt.db) {
                set_err(&mut *stmt.db, e);
            } else {
                set_global_err(e.to_string());
            }
            return c"".as_ptr();
        }
    };
    if !is_live_db(stmt.db) {
        set_global_err("column_text: parent db closed");
        return c"".as_ptr();
    }
    let db = &mut *stmt.db;
    db.col_text_c = CString::new(s.replace('\0', "")).unwrap_or_default();
    db.col_text_c.as_ptr()
}

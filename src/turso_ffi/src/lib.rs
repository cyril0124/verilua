//! Minimal SQLite-subset C ABI over Turso (`turso_sdk_kit` rsapi), used by
//! `LuaDataBaseV2` through LuaJIT FFI.
//!
//! # Safety contract
//!
//! All exported functions share one contract, so their individual `# Safety`
//! sections only point at the parts they rely on.
//!
//! - `db` / `statement` handles must be pointers returned by [`turso_ffi_open`] /
//!   [`turso_ffi_prepare`] of this library. Null, closed, finalized, or foreign
//!   pointers are rejected through the live-handle registries and report an
//!   error instead of being dereferenced.
//! - One handle must not be used by two calls at the same time. Every call may
//!   therefore assume exclusive access to the state behind a live handle.
//! - C string arguments must be valid NUL-terminated buffers, and `text` with
//!   `len >= 0` must point to at least `len` readable bytes.
//! - Returned strings (`errmsg` / `column_text`) are owned by the library and
//!   only valid until the next call on the same handle.
//!
//! # Why unsafe code is required
//!
//! The crate exists to expose a C ABI to LuaJIT FFI, which is only expressible
//! through `extern "C"` functions over raw pointers. The unsafe surface is kept
//! out of the logic: exported functions validate handles and forward to safe
//! helpers, and every raw dereference is confined to one of those helpers with a
//! `SAFETY` comment.
#![deny(unsafe_op_in_unsafe_fn)]
#![deny(clippy::undocumented_unsafe_blocks)]

use std::collections::HashSet;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::slice;
use std::str;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use turso_core::{IOResult, Numeric};
use turso_sdk_kit::rsapi::{
    TursoConnection, TursoDatabase, TursoDatabaseConfig, TursoStatement, TursoStatusCode, Value,
};
use turso_sdk_kit::IoBackend;

/// Successful completion; same value as `SQLITE_OK`.
pub const TURSO_FFI_OK: c_int = 0;
/// A result row is available; same value as `SQLITE_ROW`.
pub const TURSO_FFI_ROW: c_int = 100;
/// The statement has finished; same value as `SQLITE_DONE`.
pub const TURSO_FFI_DONE: c_int = 101;
/// Failure; see [`turso_ffi_errmsg`]. Same value as `SQLITE_ERROR`.
pub const TURSO_FFI_ERR: c_int = 1;

/// Error message plus the NUL-terminated copy handed out over FFI.
///
/// `c_text` mirrors `text` so the pointer-returning calls hand out a stable
/// buffer without reallocating on every read.
#[derive(Default)]
struct ErrorMessage {
    text: String,
    c_text: CString,
}

impl ErrorMessage {
    fn clear(&mut self) {
        self.text.clear();
        self.c_text = CString::default();
    }

    fn set(&mut self, text: String) {
        self.c_text = to_c_string(&text);
        self.text = text;
    }
}

/// Error slot used while no live database handle exists, e.g. when opening
/// fails.
static LAST_GLOBAL_ERROR: OnceLock<Mutex<ErrorMessage>> = OnceLock::new();
/// Addresses of the database handles that callers may still use.
static LIVE_DATABASES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
/// Addresses of the statement handles that callers may still use.
static LIVE_STATEMENTS: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();

fn global_error() -> MutexGuard<'static, ErrorMessage> {
    LAST_GLOBAL_ERROR
        .get_or_init(|| Mutex::new(ErrorMessage::default()))
        .lock()
        .expect("the global error mutex is never poisoned: no code panics while holding it")
}

fn live_databases() -> MutexGuard<'static, HashSet<usize>> {
    LIVE_DATABASES
        .get_or_init(|| Mutex::new(HashSet::new()))
        .lock()
        .expect("the live-database registry mutex is never poisoned")
}

fn live_statements() -> MutexGuard<'static, HashSet<usize>> {
    LIVE_STATEMENTS
        .get_or_init(|| Mutex::new(HashSet::new()))
        .lock()
        .expect("the live-statement registry mutex is never poisoned")
}

/// Address that identifies a handle in the live-handle registries.
fn handle_address<T>(handle: *const T) -> usize {
    handle.addr()
}

fn set_global_error(text: impl Into<String>) {
    global_error().set(text.into());
}

fn clear_global_error() {
    global_error().clear();
}

fn register_database(db: *mut DatabaseHandle) {
    live_databases().insert(handle_address(db));
}

fn unregister_database(db: *mut DatabaseHandle) -> bool {
    live_databases().remove(&handle_address(db))
}

fn is_live_database(db: *const DatabaseHandle) -> bool {
    !db.is_null() && live_databases().contains(&handle_address(db))
}

fn register_statement(statement: *mut StatementHandle) {
    live_statements().insert(handle_address(statement));
}

fn unregister_statement(statement: *mut StatementHandle) -> bool {
    live_statements().remove(&handle_address(statement))
}

fn is_live_statement(statement: *const StatementHandle) -> bool {
    !statement.is_null() && live_statements().contains(&handle_address(statement))
}

/// State owned by one database handle.
struct DatabaseHandle {
    /// Keeps the database alive for as long as its connection exists; the field
    /// itself is never read.
    _database: Arc<TursoDatabase>,
    connection: Arc<TursoConnection>,
    error: ErrorMessage,
    /// Scratch buffer for [`turso_ffi_column_text`], valid until the next call
    /// on this handle.
    column_text_c_string: CString,
}

/// State owned by one statement handle.
struct StatementHandle {
    /// Parent database. Becomes dangling once that database is closed, which is
    /// why every use goes through [`is_usable_statement`] first.
    db: *mut DatabaseHandle,
    statement: Box<TursoStatement>,
}

/// Stores `text` in a live handle's error slot and mirrors it into the global
/// slot, which outlives the handle.
fn set_handle_error(db: &mut DatabaseHandle, text: String) {
    db.error.set(text);
    set_global_error(db.error.text.clone());
}

/// Clears a live handle's error slot together with the mirrored global one.
fn clear_handle_error(db: &mut DatabaseHandle) {
    db.error.clear();
    clear_global_error();
}

/// Routes `text` to the parent database's slot when it is still live, otherwise
/// to the global slot. Statement operations need this because their parent
/// database may already be closed.
fn report_error(db: *mut DatabaseHandle, text: impl Into<String>) {
    if is_live_database(db) {
        // SAFETY: the registry says `db` is live, so it points to a
        // `DatabaseHandle` owned by this library, and the C ABI contract
        // guarantees no other call holds a reference to it.
        set_handle_error(unsafe { &mut *db }, text.into());
    } else {
        set_global_error(text);
    }
}

/// Runs `operation` on the database behind `db`.
///
/// A null or closed handle has no error slot of its own, so it reports a global
/// error and returns `fallback`.
fn with_database<T>(
    db: *mut c_void,
    context: &str,
    fallback: T,
    operation: impl FnOnce(&mut DatabaseHandle) -> T,
) -> T {
    let db = db.cast::<DatabaseHandle>();
    if !is_live_database(db) {
        set_global_error(format!("{context}: null or closed db"));
        return fallback;
    }
    // SAFETY: the registry says `db` is live, so it is a valid, uniquely owned
    // `DatabaseHandle`; the C ABI contract keeps the exclusive borrow confined
    // to this call.
    operation(unsafe { &mut *db })
}

/// Runs `operation` on the statement behind `statement`.
///
/// Reports a global error and returns `fallback` when either the statement or
/// its parent database is gone.
fn with_statement<T>(
    statement: *mut c_void,
    context: &str,
    fallback: T,
    operation: impl FnOnce(&mut StatementHandle) -> T,
) -> T {
    let statement = statement.cast::<StatementHandle>();
    if !is_usable_statement(statement) {
        set_global_error(format!("{context}: null/finalized stmt or closed db"));
        return fallback;
    }
    // SAFETY: the statement and its parent database are both live, so the handle
    // is valid; the C ABI contract keeps the exclusive borrow confined to this
    // call.
    operation(unsafe { &mut *statement })
}

/// Reports whether `statement` and its parent database are both still live, so
/// the handle can be used.
fn is_usable_statement(statement: *const StatementHandle) -> bool {
    if !is_live_statement(statement) {
        return false;
    }
    // SAFETY: the registry says `statement` is live, so the parent pointer is
    // readable; the parent itself may already be closed, hence the extra check.
    let parent = unsafe { &*statement }.db;
    is_live_database(parent)
}

/// Returns a pointer to a static empty C string, used instead of null results.
fn empty_c_string() -> *const c_char {
    c"".as_ptr()
}

/// Copies `text` into the NUL-terminated form required by the C ABI.
///
/// Interior NUL bytes are dropped, since `CString` cannot hold them and a
/// truncated message is better than a failed call.
fn to_c_string(text: &str) -> CString {
    let bytes: Vec<u8> = text.bytes().filter(|byte| *byte != 0).collect();
    CString::new(bytes).expect("interior NUL bytes were filtered out above")
}

/// Borrows a NUL-terminated C string.
///
/// # Safety
///
/// `text` must be null or point to a NUL-terminated buffer that stays readable
/// for the returned borrow.
unsafe fn c_string_to_str<'text>(text: *const c_char) -> Result<&'text str, String> {
    if text.is_null() {
        return Err("null string".to_string());
    }
    // SAFETY: the caller guarantees a NUL-terminated buffer; `CStr::from_ptr`
    // requires nothing else.
    let text = unsafe { CStr::from_ptr(text) };
    text.to_str().map_err(|e| e.to_string())
}

/// Copies a `(pointer, length)` text argument into an owned `String`, where a
/// negative `len` means "read up to the terminating NUL".
///
/// # Safety
///
/// `text` must be non-null and either NUL-terminated (`len < 0`) or point to at
/// least `len` readable bytes.
unsafe fn copy_argument_text(text: *const c_char, len: c_int) -> Result<String, String> {
    if text.is_null() {
        return Err("null string".to_string());
    }
    if len < 0 {
        // SAFETY: the caller guarantees a NUL-terminated buffer.
        return unsafe { c_string_to_str(text) }.map(str::to_string);
    }
    let len = usize::try_from(len).expect("`len` is non-negative here");
    // SAFETY: the caller guarantees at least `len` readable bytes.
    let bytes = unsafe { slice::from_raw_parts(text.cast::<u8>(), len) };
    str::from_utf8(bytes)
        .map(str::to_string)
        .map_err(|e| e.to_string())
}

/// Converts a 1-based argument index from the FFI boundary.
fn argument_index(index: c_int) -> Option<usize> {
    usize::try_from(index).ok().filter(|index| *index >= 1)
}

/// Converts a 0-based column index from the FFI boundary.
fn column_index(index: c_int) -> Option<usize> {
    usize::try_from(index).ok()
}

/// Opens `path` over the default VFS with synchronous IO and connects to it.
fn open_database(path: &str) -> Result<DatabaseHandle, String> {
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
        IOResult::IO(_) => return Err("open returned pending IO with async_io=false".to_string()),
    }
    let connection = database.connect().map_err(|e| e.to_string())?;
    Ok(DatabaseHandle {
        _database: database,
        connection,
        error: ErrorMessage::default(),
        column_text_c_string: CString::default(),
    })
}

/// Executes every statement in `sql`; multi-statement input is supported.
fn execute_sql(db: &mut DatabaseHandle, sql: &str) -> Result<(), String> {
    let mut remaining = sql;
    loop {
        if remaining.trim().is_empty() {
            break;
        }
        let Some((mut statement, tail)) = db
            .connection
            .prepare_first(remaining)
            .map_err(|e| e.to_string())?
        else {
            break;
        };
        match statement.execute(None) {
            Ok(result) if result.status == TursoStatusCode::Done => {}
            Ok(result) => {
                let _ = statement.finalize(None);
                return Err(format!("execute status: {:?}", result.status));
            }
            Err(e) => {
                let _ = statement.finalize(None);
                return Err(e.to_string());
            }
        }
        match statement.finalize(None) {
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

/// Copies `text` into the parent database's column-text scratch buffer and
/// returns a pointer to it.
fn store_column_text(db: *mut DatabaseHandle, text: &str) -> *const c_char {
    if !is_live_database(db) {
        set_global_error("column_text: parent db closed");
        return empty_c_string();
    }
    // SAFETY: the registry says `db` is live, so it is a valid, uniquely owned
    // `DatabaseHandle`; the C ABI contract keeps the exclusive borrow confined
    // to this call.
    let db = unsafe { &mut *db };
    db.column_text_c_string = to_c_string(text);
    db.column_text_c_string.as_ptr()
}

/// Opens `path` and returns the new handle in `out_db`.
///
/// # Safety
///
/// `out_db` must be non-null and writable; `path` must be a NUL-terminated
/// buffer.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_open(path: *const c_char, out_db: *mut *mut c_void) -> c_int {
    if out_db.is_null() {
        set_global_error("open: out_db is null");
        return TURSO_FFI_ERR;
    }
    // SAFETY: `out_db` was checked non-null and the caller owns the slot.
    unsafe { *out_db = ptr::null_mut() };
    // SAFETY: the caller guarantees a NUL-terminated `path`.
    let path = match unsafe { c_string_to_str(path) } {
        Ok(path) => path,
        Err(e) => {
            set_global_error(e);
            return TURSO_FFI_ERR;
        }
    };

    match open_database(path) {
        Ok(db) => {
            clear_global_error();
            let handle = Box::into_raw(Box::new(db));
            register_database(handle);
            // SAFETY: `out_db` was checked non-null and the caller owns the slot.
            unsafe { *out_db = handle.cast::<c_void>() };
            TURSO_FFI_OK
        }
        Err(e) => {
            set_global_error(e);
            TURSO_FFI_ERR
        }
    }
}

/// Closes and frees a database handle.
///
/// # Safety
///
/// `db` must be null or a live handle from [`turso_ffi_open`] that the caller
/// does not use again afterwards.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_close(db: *mut c_void) -> c_int {
    let db = db.cast::<DatabaseHandle>();
    if !unregister_database(db) {
        set_global_error("close: null or already closed db");
        return TURSO_FFI_ERR;
    }
    // SAFETY: this call unregistered `db`, so no exported function can obtain a
    // reference to it any more and the allocation is ours to free.
    let handle = unsafe { Box::from_raw(db) };
    match handle.connection.close() {
        Ok(()) => {
            clear_global_error();
            TURSO_FFI_OK
        }
        Err(e) => {
            set_global_error(e.to_string());
            TURSO_FFI_ERR
        }
    }
}

/// Executes every statement in `sql`.
///
/// # Safety
///
/// `db` must be null or live; `sql` must be a NUL-terminated buffer.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_exec(db: *mut c_void, sql: *const c_char) -> c_int {
    with_database(db, "exec", TURSO_FFI_ERR, |db| {
        // SAFETY: the caller guarantees a NUL-terminated `sql`.
        let sql = match unsafe { c_string_to_str(sql) } {
            Ok(sql) => sql,
            Err(e) => {
                set_handle_error(db, e);
                return TURSO_FFI_ERR;
            }
        };
        match execute_sql(db, sql) {
            Ok(()) => {
                clear_handle_error(db);
                TURSO_FFI_OK
            }
            Err(e) => {
                set_handle_error(db, e);
                TURSO_FFI_ERR
            }
        }
    })
}

/// Prepares a single statement and returns it in `out_stmt`.
///
/// # Safety
///
/// `db` must be null or live; `sql` must be a NUL-terminated buffer; `out_stmt`
/// must be non-null and writable.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_prepare(
    db: *mut c_void,
    sql: *const c_char,
    out_stmt: *mut *mut c_void,
) -> c_int {
    if out_stmt.is_null() {
        set_global_error("prepare: out_stmt is null");
        return TURSO_FFI_ERR;
    }
    // SAFETY: `out_stmt` was checked non-null and the caller owns the slot.
    unsafe { *out_stmt = ptr::null_mut() };

    with_database(db, "prepare", TURSO_FFI_ERR, |db| {
        // SAFETY: the caller guarantees a NUL-terminated `sql`.
        let sql = match unsafe { c_string_to_str(sql) } {
            Ok(sql) => sql,
            Err(e) => {
                set_handle_error(db, e);
                return TURSO_FFI_ERR;
            }
        };
        match db.connection.prepare_single(sql) {
            Ok(statement) => {
                clear_handle_error(db);
                let handle = Box::into_raw(Box::new(StatementHandle {
                    db: ptr::from_mut(db),
                    statement,
                }));
                register_statement(handle);
                // SAFETY: `out_stmt` was checked non-null and the caller owns
                // the slot.
                unsafe { *out_stmt = handle.cast::<c_void>() };
                TURSO_FFI_OK
            }
            Err(e) => {
                set_handle_error(db, e.to_string());
                TURSO_FFI_ERR
            }
        }
    })
}

/// Binds an integer to the 1-based parameter `idx`.
///
/// # Safety
///
/// `statement` must be null or live.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_bind_int(
    statement: *mut c_void,
    idx: c_int,
    value: i64,
) -> c_int {
    with_statement(statement, "bind_int", TURSO_FFI_ERR, |statement| {
        let Some(index) = argument_index(idx) else {
            report_error(
                statement.db,
                format!("bind_int: index must be >= 1, got {idx}"),
            );
            return TURSO_FFI_ERR;
        };
        match statement
            .statement
            .bind_positional(index, Value::from_i64(value))
        {
            Ok(()) => TURSO_FFI_OK,
            Err(e) => {
                report_error(statement.db, e.to_string());
                TURSO_FFI_ERR
            }
        }
    })
}

/// Binds text to the 1-based parameter `idx`; a negative `len` reads up to the
/// terminating NUL.
///
/// # Safety
///
/// `statement` must be null or live; `text` must be non-null and either
/// NUL-terminated (`len < 0`) or point to at least `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_bind_text(
    statement: *mut c_void,
    idx: c_int,
    text: *const c_char,
    len: c_int,
) -> c_int {
    with_statement(statement, "bind_text", TURSO_FFI_ERR, |statement| {
        let Some(index) = argument_index(idx) else {
            report_error(
                statement.db,
                format!("bind_text: index must be >= 1, got {idx}"),
            );
            return TURSO_FFI_ERR;
        };
        // SAFETY: the caller guarantees `text` matches `len` as documented.
        let value = match unsafe { copy_argument_text(text, len) } {
            Ok(value) => value,
            Err(e) => {
                report_error(statement.db, e);
                return TURSO_FFI_ERR;
            }
        };
        match statement
            .statement
            .bind_positional(index, Value::build_text(value))
        {
            Ok(()) => TURSO_FFI_OK,
            Err(e) => {
                report_error(statement.db, e.to_string());
                TURSO_FFI_ERR
            }
        }
    })
}

/// Advances the statement to the next row.
///
/// # Safety
///
/// `statement` must be null or live.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_step(statement: *mut c_void) -> c_int {
    with_statement(
        statement,
        "step",
        TURSO_FFI_ERR,
        |statement| match statement.statement.step(None) {
            Ok(TursoStatusCode::Row) => TURSO_FFI_ROW,
            Ok(TursoStatusCode::Done) => TURSO_FFI_DONE,
            Ok(other) => {
                report_error(statement.db, format!("step status: {other:?}"));
                TURSO_FFI_ERR
            }
            Err(e) => {
                report_error(statement.db, e.to_string());
                TURSO_FFI_ERR
            }
        },
    )
}

/// Resets the statement so it can be stepped again.
///
/// # Safety
///
/// `statement` must be null or live.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_reset(statement: *mut c_void) -> c_int {
    with_statement(
        statement,
        "reset",
        TURSO_FFI_ERR,
        |statement| match statement.statement.reset() {
            Ok(()) => TURSO_FFI_OK,
            Err(e) => {
                report_error(statement.db, e.to_string());
                TURSO_FFI_ERR
            }
        },
    )
}

/// Finalizes and frees a statement handle.
///
/// # Safety
///
/// `statement` must be null or a live handle from [`turso_ffi_prepare`] that the
/// caller does not use again afterwards.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_finalize(statement: *mut c_void) -> c_int {
    let statement = statement.cast::<StatementHandle>();
    if !unregister_statement(statement) {
        set_global_error("finalize: null or already finalized stmt");
        return TURSO_FFI_ERR;
    }
    // SAFETY: this call unregistered `statement`, so no exported function can
    // reach it any more and the allocation is ours to free.
    let mut handle = unsafe { Box::from_raw(statement) };
    let db = handle.db;
    match handle.statement.finalize(None) {
        Ok(TursoStatusCode::Done) => {
            clear_global_error();
            TURSO_FFI_OK
        }
        Ok(other) => {
            report_error(db, format!("finalize status: {other:?}"));
            TURSO_FFI_ERR
        }
        Err(e) => {
            report_error(db, e.to_string());
            TURSO_FFI_ERR
        }
    }
}

/// Returns the last error of `db`, or the last global error when `db` is null or
/// closed.
///
/// # Safety
///
/// `db` must be null or live. The returned pointer stays valid only until the
/// next call on the same handle.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_errmsg(db: *mut c_void) -> *const c_char {
    let db = db.cast::<DatabaseHandle>();
    if is_live_database(db) {
        // SAFETY: the registry says `db` is live; a shared reference is sound
        // under the "no concurrent use" contract.
        let db = unsafe { &*db };
        return db.error.c_text.as_ptr();
    }
    global_error().c_text.as_ptr()
}

/// Returns column `idx` as an integer, coercing numeric values.
///
/// # Safety
///
/// `statement` must be null or live, and positioned on a row.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_column_int(statement: *mut c_void, idx: c_int) -> i64 {
    with_statement(statement, "column_int", 0, |statement| {
        let Some(index) = column_index(idx) else {
            report_error(
                statement.db,
                format!("column_int: index must be >= 0, got {idx}"),
            );
            return 0;
        };
        match statement.statement.row_value(index) {
            Ok(Value::Numeric(Numeric::Integer(value))) => value,
            // SQLite truncates the fraction and saturates on overflow; `as`
            // matches that well-defined behavior.
            Ok(Value::Numeric(Numeric::Float(value))) => f64::from(value) as i64,
            Ok(_) => {
                report_error(statement.db, "column_int: value is not numeric");
                0
            }
            Err(e) => {
                report_error(statement.db, e.to_string());
                0
            }
        }
    })
}

/// Returns column `idx` as text, coercing numeric values.
///
/// # Safety
///
/// `statement` must be null or live, and positioned on a row. The returned pointer
/// stays valid only until the next call on the parent database.
#[no_mangle]
pub unsafe extern "C" fn turso_ffi_column_text(
    statement: *mut c_void,
    idx: c_int,
) -> *const c_char {
    with_statement(statement, "column_text", empty_c_string(), |statement| {
        let Some(index) = column_index(idx) else {
            report_error(
                statement.db,
                format!("column_text: index must be >= 0, got {idx}"),
            );
            return empty_c_string();
        };
        let text = match statement.statement.row_value(index) {
            Ok(Value::Text(text)) => text.as_str().to_string(),
            Ok(Value::Numeric(Numeric::Integer(value))) => value.to_string(),
            Ok(Value::Numeric(Numeric::Float(value))) => f64::from(value).to_string(),
            Ok(Value::Null) => {
                report_error(statement.db, "column_text: NULL");
                return empty_c_string();
            }
            Ok(_) => {
                report_error(statement.db, "column_text: unsupported type");
                return empty_c_string();
            }
            Err(e) => {
                report_error(statement.db, e.to_string());
                return empty_c_string();
            }
        };
        store_column_text(statement.db, &text)
    })
}

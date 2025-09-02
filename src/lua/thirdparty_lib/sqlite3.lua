
-- https://github.com/Playermet/luajit-sqlite

-----------------------------------------------------------
--  Binding for SQLite v3.29.0
-----------------------------------------------------------

--[[ LICENSE
  The MIT License (MIT)

  luajit-sqlite - SQLite binding for LuaJIT

  Copyright (c) 2019 Playermet

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
]]

local ffi = require 'ffi'
local bit = require 'bit'

local mod = {} -- Lua module namespace
local aux = {} -- Auxiliary utils

local args -- Arguments for binding
local clib -- C library namespace

local is_luajit = pcall(require, 'jit')


local load_clib, bind_clib -- Forward declaration

local function init(mod, name_or_args)
  if clib ~= nil then
    return mod
  end

  if type(name_or_args) == 'table' then
    args = name_or_args
    args.name = args.name or args[1]
  elseif type(name_or_args) == 'string' then
    args = {}
    args.name = name_or_args
  end

  clib = load_clib()
  bind_clib()

  return mod
end

function load_clib()
  if args.clib ~= nil then
    return args.clib
  end

  if type(args.name) == 'string' then
    if type(args.path) == 'string' then
      local lib = package.searchpath(args.name, args.path)
      assert(lib, "[thirdparty_lib.sqlite.lua] library not found, name: " .. tostring(args.name) .. ", path: " .. tostring(args.path))
      return ffi.load(package.searchpath(args.name, args.path))
    else
      return ffi.load(args.name)
    end
  end

  -- If no library or name is provided, we just
  -- assume that the appropriate SQLite libraries
  -- are statically linked to the calling program
  return ffi.C
end

function bind_clib()
  -----------------------------------------------------------
  --  Namespaces
  -----------------------------------------------------------
  local const = {} -- Table for contants
  local funcs = {} -- Table for functions
  local types = {} -- Table for types
  local cbs   = {} -- Table for callbacks

  mod.const = const
  mod.funcs = funcs
  mod.types = types
  mod.cbs   = cbs
  mod.clib  = clib

  -- Access to funcs from module namespace by default
  aux.set_mt_method(mod, '__index', funcs)

  -----------------------------------------------------------
  --  Constants
  -----------------------------------------------------------
  const.OK           = 0

  -- Result Codes
  const.ERROR        = 1
  const.INTERNAL     = 2
  const.PERM         = 3
  const.ABORT        = 4
  const.BUSY         = 5
  const.LOCKED       = 6
  const.NOMEM        = 7
  const.READONLY     = 8
  const.INTERRUPT    = 9
  const.IOERR       = 10
  const.CORRUPT     = 11
  const.NOTFOUND    = 12
  const.FULL        = 13
  const.CANTOPEN    = 14
  const.PROTOCOL    = 15
  const.EMPTY       = 16
  const.SCHEMA      = 17
  const.TOOBIG      = 18
  const.CONSTRAINT  = 19
  const.MISMATCH    = 20
  const.MISUSE      = 21
  const.NOLFS       = 22
  const.AUTH        = 23
  const.FORMAT      = 24
  const.RANGE       = 25
  const.NOTADB      = 26
  const.NOTICE      = 27
  const.WARNING     = 28
  const.ROW         = 100
  const.DONE        = 101

  -- Extended Result Codes
  const.ERROR_MISSING_COLLSEQ   = bit.bor(const.ERROR,      bit.lshift(1, 8))
  const.ERROR_RETRY             = bit.bor(const.ERROR,      bit.lshift(2, 8))
  const.ERROR_SNAPSHOT          = bit.bor(const.ERROR,      bit.lshift(3, 8))
  const.IOERR_READ              = bit.bor(const.IOERR,      bit.lshift(1, 8))
  const.IOERR_SHORT_READ        = bit.bor(const.IOERR,      bit.lshift(2, 8))
  const.IOERR_WRITE             = bit.bor(const.IOERR,      bit.lshift(3, 8))
  const.IOERR_FSYNC             = bit.bor(const.IOERR,      bit.lshift(4, 8))
  const.IOERR_DIR_FSYNC         = bit.bor(const.IOERR,      bit.lshift(5, 8))
  const.IOERR_TRUNCATE          = bit.bor(const.IOERR,      bit.lshift(6, 8))
  const.IOERR_FSTAT             = bit.bor(const.IOERR,      bit.lshift(7, 8))
  const.IOERR_UNLOCK            = bit.bor(const.IOERR,      bit.lshift(8, 8))
  const.IOERR_RDLOCK            = bit.bor(const.IOERR,      bit.lshift(9, 8))
  const.IOERR_DELETE            = bit.bor(const.IOERR,      bit.lshift(10, 8))
  const.IOERR_BLOCKED           = bit.bor(const.IOERR,      bit.lshift(11, 8))
  const.IOERR_NOMEM             = bit.bor(const.IOERR,      bit.lshift(12, 8))
  const.IOERR_ACCESS            = bit.bor(const.IOERR,      bit.lshift(13, 8))
  const.IOERR_CHECKRESERVEDLOCK = bit.bor(const.IOERR,      bit.lshift(14, 8))
  const.IOERR_LOCK              = bit.bor(const.IOERR,      bit.lshift(15, 8))
  const.IOERR_CLOSE             = bit.bor(const.IOERR,      bit.lshift(16, 8))
  const.IOERR_DIR_CLOSE         = bit.bor(const.IOERR,      bit.lshift(17, 8))
  const.IOERR_SHMOPEN           = bit.bor(const.IOERR,      bit.lshift(18, 8))
  const.IOERR_SHMSIZE           = bit.bor(const.IOERR,      bit.lshift(19, 8))
  const.IOERR_SHMLOCK           = bit.bor(const.IOERR,      bit.lshift(20, 8))
  const.IOERR_SHMMAP            = bit.bor(const.IOERR,      bit.lshift(21, 8))
  const.IOERR_SEEK              = bit.bor(const.IOERR,      bit.lshift(22, 8))
  const.IOERR_DELETE_NOENT      = bit.bor(const.IOERR,      bit.lshift(23, 8))
  const.IOERR_MMAP              = bit.bor(const.IOERR,      bit.lshift(24, 8))
  const.IOERR_GETTEMPPATH       = bit.bor(const.IOERR,      bit.lshift(25, 8))
  const.IOERR_CONVPATH          = bit.bor(const.IOERR,      bit.lshift(26, 8))
  const.IOERR_VNODE             = bit.bor(const.IOERR,      bit.lshift(27, 8))
  const.IOERR_AUTH              = bit.bor(const.IOERR,      bit.lshift(28, 8))
  const.IOERR_BEGIN_ATOMIC      = bit.bor(const.IOERR,      bit.lshift(29, 8))
  const.IOERR_COMMIT_ATOMIC     = bit.bor(const.IOERR,      bit.lshift(30, 8))
  const.IOERR_ROLLBACK_ATOMIC   = bit.bor(const.IOERR,      bit.lshift(31, 8))
  const.LOCKED_SHAREDCACHE      = bit.bor(const.LOCKED,     bit.lshift(1, 8))
  const.LOCKED_VTAB             = bit.bor(const.LOCKED,     bit.lshift(2, 8))
  const.BUSY_RECOVERY           = bit.bor(const.BUSY,       bit.lshift(1, 8))
  const.BUSY_SNAPSHOT           = bit.bor(const.BUSY,       bit.lshift(2, 8))
  const.CANTOPEN_NOTEMPDIR      = bit.bor(const.CANTOPEN,   bit.lshift(1, 8))
  const.CANTOPEN_ISDIR          = bit.bor(const.CANTOPEN,   bit.lshift(2, 8))
  const.CANTOPEN_FULLPATH       = bit.bor(const.CANTOPEN,   bit.lshift(3, 8))
  const.CANTOPEN_CONVPATH       = bit.bor(const.CANTOPEN,   bit.lshift(4, 8))
  const.CANTOPEN_DIRTYWAL       = bit.bor(const.CANTOPEN,   bit.lshift(5, 8))
  const.CORRUPT_VTAB            = bit.bor(const.CORRUPT,    bit.lshift(1, 8))
  const.CORRUPT_SEQUENCE        = bit.bor(const.CORRUPT,    bit.lshift(2, 8))
  const.READONLY_RECOVERY       = bit.bor(const.READONLY,   bit.lshift(1, 8))
  const.READONLY_CANTLOCK       = bit.bor(const.READONLY,   bit.lshift(2, 8))
  const.READONLY_ROLLBACK       = bit.bor(const.READONLY,   bit.lshift(3, 8))
  const.READONLY_DBMOVED        = bit.bor(const.READONLY,   bit.lshift(4, 8))
  const.READONLY_CANTINIT       = bit.bor(const.READONLY,   bit.lshift(5, 8))
  const.READONLY_DIRECTORY      = bit.bor(const.READONLY,   bit.lshift(6, 8))
  const.ABORT_ROLLBACK          = bit.bor(const.ABORT,      bit.lshift(2, 8))
  const.CONSTRAINT_CHECK        = bit.bor(const.CONSTRAINT, bit.lshift(1, 8))
  const.CONSTRAINT_COMMITHOOK   = bit.bor(const.CONSTRAINT, bit.lshift(2, 8))
  const.CONSTRAINT_FOREIGNKEY   = bit.bor(const.CONSTRAINT, bit.lshift(3, 8))
  const.CONSTRAINT_FUNCTION     = bit.bor(const.CONSTRAINT, bit.lshift(4, 8))
  const.CONSTRAINT_NOTNULL      = bit.bor(const.CONSTRAINT, bit.lshift(5, 8))
  const.CONSTRAINT_PRIMARYKEY   = bit.bor(const.CONSTRAINT, bit.lshift(6, 8))
  const.CONSTRAINT_TRIGGER      = bit.bor(const.CONSTRAINT, bit.lshift(7, 8))
  const.CONSTRAINT_UNIQUE       = bit.bor(const.CONSTRAINT, bit.lshift(8, 8))
  const.CONSTRAINT_VTAB         = bit.bor(const.CONSTRAINT, bit.lshift(9, 8))
  const.CONSTRAINT_ROWID        = bit.bor(const.CONSTRAINT, bit.lshift(10, 8))
  const.NOTICE_RECOVER_WAL      = bit.bor(const.NOTICE,     bit.lshift(1, 8))
  const.NOTICE_RECOVER_ROLLBACK = bit.bor(const.NOTICE,     bit.lshift(2, 8))
  const.WARNING_AUTOINDEX       = bit.bor(const.WARNING,    bit.lshift(1, 8))
  const.AUTH_USER               = bit.bor(const.AUTH,       bit.lshift(1, 8))
  const.OK_LOAD_PERMANENTLY     = bit.bor(const.OK,         bit.lshift(1, 8))

  -- Flags for sqlite3_open_v2
  const.OPEN_READONLY       = 0x00000001
  const.OPEN_READWRITE      = 0x00000002
  const.OPEN_CREATE         = 0x00000004
  const.OPEN_DELETEONCLOSE  = 0x00000008
  const.OPEN_EXCLUSIVE      = 0x00000010
  const.OPEN_AUTOPROXY      = 0x00000020
  const.OPEN_URI            = 0x00000040
  const.OPEN_MEMORY         = 0x00000080
  const.OPEN_MAIN_DB        = 0x00000100
  const.OPEN_TEMP_DB        = 0x00000200
  const.OPEN_TRANSIENT_DB   = 0x00000400
  const.OPEN_MAIN_JOURNAL   = 0x00000800
  const.OPEN_TEMP_JOURNAL   = 0x00001000
  const.OPEN_SUBJOURNAL     = 0x00002000
  const.OPEN_MASTER_JOURNAL = 0x00004000
  const.OPEN_NOMUTEX        = 0x00008000
  const.OPEN_FULLMUTEX      = 0x00010000
  const.OPEN_SHAREDCACHE    = 0x00020000
  const.OPEN_PRIVATECACHE   = 0x00040000
  const.OPEN_WAL            = 0x00080000

  -- Limits for sqlite3_limit
  const.LIMIT_LENGTH              = 0
  const.LIMIT_SQL_LENGTH          = 1
  const.LIMIT_COLUMN              = 2
  const.LIMIT_EXPR_DEPTH          = 3
  const.LIMIT_COMPOUND_SELECT     = 4
  const.LIMIT_VDBE_OP             = 5
  const.LIMIT_FUNCTION_ARG        = 6
  const.LIMIT_ATTACHED            = 7
  const.LIMIT_LIKE_PATTERN_LENGTH = 8
  const.LIMIT_VARIABLE_NUMBER     = 9
  const.LIMIT_TRIGGER_DEPTH       = 10
  const.LIMIT_WORKER_THREADS      = 11

  -- Prepare Flags for sqlite3_prepare_v3
  const.PREPARE_PERSISTENT = 0x01
  const.PREPARE_NORMALIZE  = 0x02
  const.PREPARE_NO_VTAB    = 0x03

  -- Codes for fundamental types
  const.INTEGER = 1
  const.FLOAT   = 2
  const.TEXT    = 3
  const.BLOB    = 4
  const.NULL    = 5

  -- Status Parameters for sqlite3_stmt_status
  const.STMTSTATUS_FULLSCAN_STEP = 1
  const.STMTSTATUS_SORT          = 2
  const.STMTSTATUS_AUTOINDEX     = 3
  const.STMTSTATUS_VM_STEP       = 4
  const.STMTSTATUS_REPREPARE     = 5
  const.STMTSTATUS_RUN           = 6
  const.STMTSTATUS_MEMUSED       = 99

  -- Authorizer Return Codes
  const.DENY   = 1
  const.IGNORE = 2

  -- Action codes
  const.CREATE_INDEX        = 1
  const.CREATE_TABLE        = 2
  const.CREATE_TEMP_INDEX   = 3
  const.CREATE_TEMP_TABLE   = 4
  const.CREATE_TEMP_TRIGGER = 5
  const.CREATE_TEMP_VIEW    = 6
  const.CREATE_TRIGGER      = 7
  const.CREATE_VIEW         = 8
  const.DELETE              = 9
  const.DROP_INDEX          = 10
  const.DROP_TABLE          = 11
  const.DROP_TEMP_INDEX     = 12
  const.DROP_TEMP_TABLE     = 13
  const.DROP_TEMP_TRIGGER   = 14
  const.DROP_TEMP_VIEW      = 15
  const.DROP_TRIGGER        = 16
  const.DROP_VIEW           = 17
  const.INSERT              = 18
  const.PRAGMA              = 19
  const.READ                = 20
  const.SELECT              = 21
  const.TRANSACTION         = 22
  const.UPDATE              = 23
  const.ATTACH              = 24
  const.DETACH              = 25
  const.ALTER_TABLE         = 26
  const.REINDEX             = 27
  const.ANALYZE             = 28
  const.CREATE_VTABLE       = 29
  const.DROP_VTABLE         = 30
  const.FUNCTION            = 31
  const.SAVEPOINT           = 32
  const.RECURSIVE           = 33

  -- SQL trace event codes
  const.TRACE_STMT    = 0x01
  const.TRACE_PROFILE = 0x02
  const.TRACE_ROW     = 0x04
  const.TRACE_CLOSE   = 0x08

  -- For C pointers comparison
  if not is_luajit then
    const.NULL = ffi.C.NULL
  end

  -----------------------------------------------------------
  --  Types
  -----------------------------------------------------------
  ffi.cdef [[
    typedef __int64 sqlite3_int64;
    typedef unsigned __int64 sqlite3_uint64;

    typedef struct sqlite3 sqlite3;
    typedef struct sqlite3_stmt sqlite3_stmt;
    typedef struct sqlite3_value sqlite3_value;
    typedef struct sqlite3_context sqlite3_context;
    typedef struct sqlite3_backup sqlite3_backup;
  ]]

  local sqlite3_mt = aux.class()
  local sqlite3_stmt_mt = aux.class()
  local sqlite3_value_mt = aux.class()
  local sqlite3_context_mt = aux.class()
  local sqlite3_backup_mt = aux.class()

  ffi.cdef [[
    sqlite3_backup *sqlite3_backup_init(
      sqlite3 *pDest,
      const char *zDestName,
      sqlite3 *pSource,
      const char *zSourceName
    );
    int sqlite3_backup_step(sqlite3_backup *p, int nPage);
    int sqlite3_backup_finish(sqlite3_backup *p);
    int sqlite3_backup_remaining(sqlite3_backup *p);
    int sqlite3_backup_pagecount(sqlite3_backup *p);
  ]]

  -----------------------------------------------------------
  --  Functions
  -----------------------------------------------------------
  ffi.cdef [[
    const char *sqlite3_libversion();
    const char *sqlite3_sourceid();
    int sqlite3_libversion_number();
  ]]

  function funcs.libversion()
    return aux.wrap_string(clib.sqlite3_libversion())
  end

  function funcs.sourceid()
    return aux.wrap_string(clib.sqlite3_sourceid())
  end

  function funcs.libversion_number()
    return clib.sqlite3_libversion_number()
  end


  ffi.cdef [[
    int sqlite3_compileoption_used(const char*);
    const char *sqlite3_compileoption_get(int);
    int sqlite3_threadsafe();
  ]]

  function funcs.compileoption_used(option_name)
    return aux.wrap_bool(
      clib.sqlite3_compileoption_used(option_name)
    )
  end

  function funcs.compileoption_get(option_number)
    return aux.wrap_string(
      clib.sqlite3_compileoption_get(option_number)
    )
  end

  function funcs.threadsafe()
    -- can return 0, 1, or 2
    return clib.sqlite3_threadsafe()
  end


  ffi.cdef [[ const char *sqlite3_errstr(int); ]]
  function funcs.errstr(code)
    return aux.wrap_string(clib.sqlite3_errstr(code))
  end


  ffi.cdef [[ void sqlite3_free(void*); ]]
  function funcs.free(pointer)
    clib.sqlite3_free(pointer)
  end


  ffi.cdef [[
    sqlite3_int64 sqlite3_memory_used(void);
    sqlite3_int64 sqlite3_memory_highwater(int);
    sqlite3_int64 sqlite3_soft_heap_limit64(sqlite3_int64);
  ]]

  function funcs.memory_used()
    return clib.sqlite3_memory_used()
  end

  function funcs.memory_highwater(reset_flag)
    return clib.sqlite3_memory_highwater(reset_flag)
  end

  function funcs.soft_heap_limit64(limit)
    return clib.sqlite3_soft_heap_limit64(limit or -1)
  end


  ffi.cdef [[
    int sqlite3_initialize(void);
    int sqlite3_shutdown(void);
  ]]

  function funcs.initialize()
    return clib.sqlite3_initialize()
  end

  function funcs.shutdown()
    return clib.sqlite3_shutdown()
  end


  ffi.cdef [[
    int sqlite3_open(const char*, sqlite3**);
    int sqlite3_open_v2(const char*, sqlite3**, int, const char*);
    int sqlite3_close(sqlite3*);
    int sqlite3_close_v2(sqlite3*);
  ]]

  function funcs.open(filename)
    local db_p = ffi.new('sqlite3*[1]')
    local code = clib.sqlite3_open(filename, db_p)
    return code, db_p[0]
  end

  function funcs.open_v2(filename, flags, vfs)
    local db_p = ffi.new('sqlite3*[1]')
    local code = clib.sqlite3_open_v2(filename, db_p, flags, vfs)
    return code, db_p[0]
  end

  function funcs.close(db)
    return clib.sqlite3_close(db)
  end

  function funcs.close_v2(db)
    return clib.sqlite3_close_v2(db)
  end


  ffi.cdef [[
    int sqlite3_exec(sqlite3*, const char*,
      int (*)(void*,int,char**,char**), void*, char**
    );
    sqlite3_int64 sqlite3_last_insert_rowid(sqlite3*);
    void sqlite3_set_last_insert_rowid(sqlite3*, sqlite3_int64);
  ]]

  function funcs.exec(db, sql, callback, arg1, errmsg)
    if errmsg == true then
      local cstr = ffi.new('char*[1]')
      local code = clib.sqlite3_exec(db, sql, callback, arg1, cstr)
      local lstr = aux.wrap_string(cstr[0])
      clib.sqlite3_free(cstr)
      return code, lstr
    end
    return clib.sqlite3_exec(db, sql, callback, arg1, errmsg)
  end

  function funcs.last_insert_rowid(db)
    return clib.sqlite3_last_insert_rowid(db)
  end

  function funcs.set_last_insert_rowid(db, rowid)
    clib.sqlite3_set_last_insert_rowid(db, rowid)
  end


  ffi.cdef [[
    int sqlite3_extended_result_codes(sqlite3*, int);
    int sqlite3_errcode(sqlite3*);
    int sqlite3_extended_errcode(sqlite3*);
    const char *sqlite3_errmsg(sqlite3*);
  ]]

  function funcs.extended_result_codes(db, onoff)
    return clib.sqlite3_extended_result_codes(db, onoff)
  end

  function funcs.errcode(db)
    return clib.sqlite3_errcode(db)
  end

  function funcs.extended_errcode(db)
    return clib.sqlite3_extended_errcode(db)
  end

  function funcs.errmsg(db)
    return aux.wrap_string(clib.sqlite3_errmsg(db))
  end


  ffi.cdef [[ int sqlite3_limit(sqlite3*, int, int); ]]
  function funcs.limit(db, limit_code, value)
    return clib.sqlite3_limit(db, limit_code, value or -1)
  end


  ffi.cdef [[
    void sqlite3_progress_handler(sqlite3*, int, int(*)(void*), void*);
    int sqlite3_busy_handler(sqlite3*, int(*)(void*,int), void*);
    int sqlite3_busy_timeout(sqlite3*, int);
  ]]

  function funcs.progress_handler(db, period, func, arg1)
    clib.sqlite3_progress_handler(db, period or -1, func, arg1)
  end

  function funcs.busy_handler(db, func, arg1)
    return clib.sqlite3_busy_handler(db, func, arg1)
  end

  function funcs.busy_timeout(db, time_ms)
    return clib.sqlite3_busy_timeout(db, time_ms or -1)
  end


  ffi.cdef [[
    void *sqlite3_commit_hook(sqlite3*, int(*)(void*), void*);
    void *sqlite3_rollback_hook(sqlite3*, void(*)(void*), void*);
  ]]

  function funcs.commit_hook(db, func, arg1)
    return clib.sqlite3_commit_hook(db, func, arg1)
  end

  function funcs.rollback_hook(db, func, arg1)
    return clib.sqlite3_rollback_hook(db, func, arg1)
  end


  ffi.cdef [[
    void *sqlite3_update_hook(
      sqlite3*,
      void(*)(void*, int, char const*, char const*, sqlite3_int64),
      void*
    );
  ]]
  function funcs.update_hook(db, func, arg1)
    return clib.sqlite3_update_hook(db, func, arg1)
  end

  ffi.cdef [[ int sqlite3_unlock_notify(sqlite3*, void(*)(void**,int), void*); ]]
  function funcs.unlock_notify(db, func, arg1)
    return clib.sqlite3_unlock_notify(db, func, arg1)
  end

  ffi.cdef [[
    int sqlite3_set_authorizer(
      sqlite3*,
      int(*xAuth)(void*, int, const char*, const char*, const char*, const char*),
      void*
    );
  ]]
  function funcs.set_authorizer(db, func, arg1)
    return clib.sqlite3_set_authorizer(db, func, arg1)
  end

  ffi.cdef [[
    int sqlite3_trace_v2(
      sqlite3*,
      unsigned,
      int(*)(unsigned,void*,void*,void*),
      void*
    );
  ]]
  function funcs.trace_v2(db, mask, func, pctx)
    return clib.sqlite3_trace_v2(db, mask, func, pctx)
  end


  ffi.cdef [[
    int sqlite3_changes(sqlite3*);
    int sqlite3_total_changes(sqlite3*);
    void sqlite3_interrupt(sqlite3*);
    int sqlite3_get_autocommit(sqlite3*);
    int sqlite3_complete(const char *sql);
  ]]

  function funcs.changes(db)
    return clib.sqlite3_changes(db)
  end

  function funcs.total_changes(db)
    return clib.sqlite3_total_changes(db)
  end

  function funcs.interrupt(db)
    clib.sqlite3_interrupt(db)
  end

  function funcs.get_autocommit(db)
    return aux.wrap_bool(clib.sqlite3_get_autocommit(db))
  end

  function funcs.complete(sql)
    return aux.wrap_bool(clib.sqlite3_complete(sql))
  end


  ffi.cdef [[
    int sqlite3_table_column_metadata(
      sqlite3 *db,                /* Connection handle */
      const char *zDbName,        /* Database name or NULL */
      const char *zTableName,     /* Table name */
      const char *zColumnName,    /* Column name */
      char const **pzDataType,    /* OUTPUT: Declared data type */
      char const **pzCollSeq,     /* OUTPUT: Collation sequence name */
      int *pNotNull,              /* OUTPUT: True if NOT NULL constraint exists */
      int *pPrimaryKey,           /* OUTPUT: True if column part of PK */
      int *pAutoinc               /* OUTPUT: True if column is auto-increment */
    );
  ]]
  function funcs.table_column_metadata(db, db_name, table, column)
    if column then
      local ptype = ffi.new('char*[1]')
      local pcoll = ffi.new('char*[1]')
      local pnull = ffi.new('int[1]')
      local pprim = ffi.new('int[1]')
      local pauto = ffi.new('int[1]')

      local code = clib.sqlite3_table_column_metadata(
        db, db_name, table, column,
        ptype, pcoll, pnull, pprim, pauto
      )

      if code == const.OK then
        return code, {
          type      = aux.wrap_string(ptype[0]),
          collation = aux.wrap_string(pcoll[0]),
          not_null  = aux.wrap_bool(pnull[0]),
          primary   = aux.wrap_bool(pprim[0]),
          autoinc   = aux.wrap_bool(pauto[0])
        }
      end

      return code
    end
    -- TODO
    return clib.sqlite3_table_column_metadata(db, db_name, table)
  end

  ffi.cdef [[ sqlite3_stmt *sqlite3_next_stmt(sqlite3*, sqlite3_stmt*); ]]
  function funcs.next_stmt(db, stmt)
    return clib.sqlite3_next_stmt(db, stmt)
  end


  ffi.cdef [[
    int sqlite3_prepare(sqlite3*, const char*, int, sqlite3_stmt**, const char**);
    int sqlite3_prepare_v2(sqlite3*, const char*, int, sqlite3_stmt**, const char**);
    int sqlite3_prepare_v3(sqlite3*, const char*, int, unsigned int, sqlite3_stmt**, const char**);
    int sqlite3_finalize(sqlite3_stmt*);
  ]]

  function funcs.prepare(db, sql)
    local pstmt = ffi.new('sqlite3_stmt*[1]')
    local code  = clib.sqlite3_prepare(db, sql, #sql, pstmt, nil);
    if code == const.OK then
      return code, pstmt[0]
    else
      return code, nil
    end
  end

  function funcs.prepare_v2(db, sql)
    local pstmt = ffi.new('sqlite3_stmt*[1]')
    local code  = clib.sqlite3_prepare_v2(db, sql, #sql, pstmt, nil);
    if code == const.OK then
      return code, pstmt[0]
    else
      return code, nil
    end
  end

  function funcs.prepare_v3(db, sql, flags)
    local pstmt = ffi.new('sqlite3_stmt*[1]')
    local code  = clib.sqlite3_prepare_v3(db, sql, #sql, flags, pstmt, nil);
    if code == const.OK then
      return code, pstmt[0]
    else
      return code, nil
    end
  end

  function funcs.finalize(stmt)
    return clib.sqlite3_finalize(stmt)
  end


  ffi.cdef [[
    sqlite3 *sqlite3_db_handle(sqlite3_stmt*);
    const char *sqlite3_db_filename(sqlite3 *db, const char *zDbName);
    int sqlite3_db_readonly(sqlite3 *db, const char *zDbName);
  ]]

  function funcs.db_handle(stmt)
    return clib.sqlite3_db_handle(stmt)
  end

  function funcs.db_filename(db, name)
    return aux.wrap_string(clib.sqlite3_db_filename(db, name))
  end

  function funcs.db_readonly(db, name)
    -- returns -1, 0, 1
    return clib.sqlite3_db_readonly(db, name)
  end


  ffi.cdef [[
    int sqlite3_step(sqlite3_stmt*);
    int sqlite3_reset(sqlite3_stmt*);
    int sqlite3_clear_bindings(sqlite3_stmt*);
  ]]

  function funcs.step(stmt)
    return clib.sqlite3_step(stmt)
  end

  function funcs.reset(stmt)
    return clib.sqlite3_reset(stmt)
  end

  function funcs.clear_bindings(stmt)
    return clib.sqlite3_sqlite3_clear_bindings(stmt)
  end


  ffi.cdef [[
    int sqlite3_stmt_busy(sqlite3_stmt*);
    int sqlite3_stmt_readonly(sqlite3_stmt*);
    int sqlite3_stmt_status(sqlite3_stmt*, int, int);
    int sqlite3_stmt_isexplain(sqlite3_stmt *pStmt);
  ]]

  function funcs.stmt_busy(stmt)
    return aux.wrap_bool(clib.sqlite3_stmt_busy(stmt))
  end

  function funcs.stmt_readonly(stmt)
    return aux.wrap_bool(clib.sqlite3_stmt_readonly(stmt))
  end

  function funcs.stmt_status(stmt, parameter_code, reset_flag)
    return clib.sqlite3_stmt_status(stmt, parameter_code, reset_flag)
  end

  function funcs.stmt_isexplain(stmt)
    return aux.wrap_bool(clib.sqlite3_stmt_isexplain(stmt))
  end



  ffi.cdef [[
    const char *sqlite3_sql(sqlite3_stmt*);
    char *sqlite3_expanded_sql(sqlite3_stmt*);
    const char *sqlite3_normalized_sql(sqlite3_stmt *pStmt);
  ]]

  function funcs.sql(stmt)
    return aux.wrap_string(clib.sqlite3_sql(stmt))
  end

  function funcs.expanded_sql(stmt)
    local cstr = clib.sqlite3_expanded_sql(stmt)
    local lstr = ffi.string(cstr)
    clib.sqlite3_free(cstr)
    return lstr
  end

  function funcs.normalized_sql(stmt)
    return aux.wrap_string(clib.sqlite3_normalized_sql(stmt))
  end


  ffi.cdef [[
    int sqlite3_bind_parameter_count(sqlite3_stmt*);
    const char *sqlite3_bind_parameter_name(sqlite3_stmt*, int);
    int sqlite3_bind_parameter_index(sqlite3_stmt*, const char*);
  ]]

  function funcs.bind_parameter_count(stmt)
    return clib.sqlite3_bind_parameter_count(stmt)
  end

  function funcs.bind_parameter_name(stmt, index)
    return aux.wrap_string(clib.sqlite3_bind_parameter_name(stmt, index))
  end

  function funcs.bind_parameter_index(stmt, name)
    return clib.sqlite3_bind_parameter_index(stmt, name)
  end


  ffi.cdef [[
    int sqlite3_bind_blob(sqlite3_stmt*, int, const void*, int n, void(*)(void*));
    int sqlite3_bind_blob64(sqlite3_stmt*, int, const void*, sqlite3_uint64, void(*)(void*));
    int sqlite3_bind_double(sqlite3_stmt*, int, double);
    int sqlite3_bind_int(sqlite3_stmt*, int, int);
    int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);
    int sqlite3_bind_null(sqlite3_stmt*, int);
    int sqlite3_bind_text(sqlite3_stmt*, int, const char*, int, void(*)(void*));
    int sqlite3_bind_value(sqlite3_stmt*, int, const sqlite3_value*);
    int sqlite3_bind_pointer(sqlite3_stmt*, int, void*, const char*, void(*)(void*));
    int sqlite3_bind_zeroblob(sqlite3_stmt*, int, int);
    int sqlite3_bind_zeroblob64(sqlite3_stmt*, int, sqlite3_uint64);
  ]]

  function funcs.bind_blob(stmt, index, pointer, size, destructor)
    return clib.sqlite3_bind_blob(stmt, index, pointer, size, destructor)
  end

  function funcs.bind_blob64(stmt, index, pointer, size, destructor)
    return clib.sqlite3_bind_blob64(stmt, index, pointer, size, destructor)
  end

  function funcs.bind_double(stmt, index, value)
    return clib.sqlite3_bind_double(stmt, index, value)
  end

  function funcs.bind_int(stmt, index, value)
    return clib.sqlite3_bind_int(stmt, index, value)
  end

  function funcs.bind_int64(stmt, index, value)
    return clib.sqlite3_bind_int64(stmt, index, value)
  end

  function funcs.bind_null(stmt, index)
    return clib.sqlite3_bind_null(stmt, index)
  end

  function funcs.bind_text(stmt, index, text, length, destructor)
    if type(text) == 'string' then
      return clib.sqlite3_bind_text(stmt, index, text, length or #text, nil)
    end
    return clib.sqlite3_bind_text(stmt, index, text, length, destructor)
  end

  function funcs.bind_value(stmt, index, value)
    return clib.sqlite3_bind_value(stmt, index, value)
  end

  function funcs.bind_pointer(stmt, index, pointer, type, destructor)
    return clib.sqlite3_bind_pointer(stmt, index, pointer, type, destructor)
  end

  function funcs.bind_zeroblob(stmt, index, size)
    return clib.sqlite3_bind_zeroblob(stmt, index, size)
  end

  function funcs.bind_zeroblob64(stmt, index, size)
    return clib.sqlite3_bind_zeroblob64(stmt, index, size)
  end


  ffi.cdef [[
    int sqlite3_data_count(sqlite3_stmt*);
    int sqlite3_column_count(sqlite3_stmt*);
    const char *sqlite3_column_name(sqlite3_stmt*, int);
    const char *sqlite3_column_decltype(sqlite3_stmt*, int);
  ]]

  function funcs.data_count(stmt)
    return clib.sqlite3_data_count(stmt)
  end

  function funcs.column_count(stmt)
    return clib.sqlite3_column_count(stmt)
  end

  function funcs.column_name(stmt, index)
    return aux.wrap_string(clib.sqlite3_column_name(stmt, index))
  end

  function funcs.column_decltype(stmt, index)
    return aux.wrap_string(clib.sqlite3_column_decltype(stmt, index))
  end


  ffi.cdef [[
    const char *sqlite3_column_database_name(sqlite3_stmt*, int);
    const char *sqlite3_column_table_name(sqlite3_stmt*, int);
    const char *sqlite3_column_origin_name(sqlite3_stmt*, int);
  ]]

  function funcs.column_database_name(stmt, index)
    return aux.wrap_string(clib.sqlite3_column_database_name(stmt, index))
  end

  function funcs.column_table_name(stmt, index)
    return aux.wrap_string(clib.sqlite3_column_table_name(stmt, index))
  end

  function funcs.column_origin_name(stmt, index)
    return aux.wrap_string(clib.sqlite3_column_origin_name(stmt, index))
  end


  ffi.cdef [[
    const void *sqlite3_column_blob(sqlite3_stmt*, int);
    double sqlite3_column_double(sqlite3_stmt*, int);
    int sqlite3_column_int(sqlite3_stmt*, int);
    sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int);
    const unsigned char *sqlite3_column_text(sqlite3_stmt*, int);
    sqlite3_value *sqlite3_column_value(sqlite3_stmt*, int);
    int sqlite3_column_bytes(sqlite3_stmt*, int);
    int sqlite3_column_type(sqlite3_stmt*, int);
  ]]

  function funcs.column_blob(stmt, column)
    return clib.sqlite3_column_blob(stmt, column)
  end

  function funcs.column_double(stmt, column)
    return clib.sqlite3_column_double(stmt, column)
  end

  function funcs.column_int(stmt, column)
    return clib.sqlite3_column_int(stmt, column)
  end

  function funcs.column_int64(stmt, column)
    return clib.sqlite3_column_int64(stmt, column)
  end

  function funcs.column_text(stmt, column)
    return aux.wrap_string(clib.sqlite3_column_text(stmt, column))
  end

  function funcs.column_value(stmt, column)
    return clib.sqlite3_column_value(stmt, column)
  end

  function funcs.column_bytes(stmt, column)
    return clib.sqlite3_column_bytes(stmt, column)
  end

  function funcs.column_type(stmt, column)
    return clib.sqlite3_column_type(stmt, column)
  end


  ffi.cdef [[
    sqlite3_value *sqlite3_value_dup(const sqlite3_value*);
    void sqlite3_value_free(sqlite3_value*);
  ]]

  function funcs.value_dup(value)
    return clib.sqlite3_value_dup(value)
  end

  function funcs.value_free(value)
    clib.sqlite3_value_free(value)
  end


  ffi.cdef [[ unsigned int sqlite3_value_subtype(sqlite3_value*); ]]
  function funcs.value_subtype(value)
    clib.sqlite3_value_subtype(value)
  end


  ffi.cdef [[
    const void *sqlite3_value_blob(sqlite3_value*);
    double sqlite3_value_double(sqlite3_value*);
    int sqlite3_value_int(sqlite3_value*);
    sqlite3_int64 sqlite3_value_int64(sqlite3_value*);
    void *sqlite3_value_pointer(sqlite3_value*, const char*);
    const unsigned char *sqlite3_value_text(sqlite3_value*);
    int sqlite3_value_bytes(sqlite3_value*);
    int sqlite3_value_type(sqlite3_value*);
    int sqlite3_value_numeric_type(sqlite3_value*);
    int sqlite3_value_nochange(sqlite3_value*);
    int sqlite3_value_frombind(sqlite3_value*);
  ]]

  function funcs.value_blob(value)
    return clib.sqlite3_value_blob(value)
  end

  function funcs.value_double(value)
    return clib.sqlite3_value_double(value)
  end

  function funcs.value_int(value)
    return clib.sqlite3_value_int(value)
  end

  function funcs.value_int64(value)
    return clib.sqlite3_value_int64(value)
  end

  function funcs.value_pointer(value, type)
    return clib.sqlite3_value_pointer(value, type)
  end

  function funcs.value_text(value)
    return aux.wrap_string(clib.sqlite3_value_text(value))
  end

  function funcs.value_bytes(value)
    return clib.sqlite3_value_bytes(value)
  end

  function funcs.value_type(value)
    return clib.sqlite3_value_type(value)
  end

  function funcs.value_numeric_type(value)
    return clib.sqlite3_value_numeric_type(value)
  end

  function funcs.value_nochange(value)
    return clib.sqlite3_value_nochange(value)
  end

  function funcs.value_frombind(value)
    return clib.sqlite3_value_frombind(value)
  end


  ffi.cdef [[ sqlite3 *sqlite3_context_db_handle(sqlite3_context*); ]]
  function funcs.context_db_handle(context)
    return clib.sqlite3_context_db_handle(context)
  end


  ffi.cdef [[
    void *sqlite3_user_data(sqlite3_context*);
    void *sqlite3_get_auxdata(sqlite3_context*, int N);
    void sqlite3_set_auxdata(sqlite3_context*, int N, void*, void (*)(void*));
    void *sqlite3_aggregate_context(sqlite3_context*, int);
  ]]

  function funcs.user_data(context)
    return clib.sqlite3_user_data(context)
  end

  function funcs.get_auxdata(context, arg_index)
    return clib.sqlite3_get_auxdata(context, arg_index)
  end

  function funcs.set_auxdata(context, arg_index, pointer, destructor)
    clib.sqlite3_set_auxdata(context, arg_index, pointer, destructor)
  end

  function funcs.aggregate_context(context, bytes)
    return clib.sqlite3_aggregate_context(context, bytes)
  end


  ffi.cdef [[
    void sqlite3_result_blob(sqlite3_context*, const void*, int, void(*)(void*));
    void sqlite3_result_blob64(sqlite3_context*, const void*, sqlite3_uint64, void(*)(void*));
    void sqlite3_result_double(sqlite3_context*, double);
    void sqlite3_result_error(sqlite3_context*, const char*, int);
    void sqlite3_result_error_toobig(sqlite3_context*);
    void sqlite3_result_error_nomem(sqlite3_context*);
    void sqlite3_result_error_code(sqlite3_context*, int);
    void sqlite3_result_int(sqlite3_context*, int);
    void sqlite3_result_int64(sqlite3_context*, sqlite3_int64);
    void sqlite3_result_null(sqlite3_context*);
    void sqlite3_result_text(sqlite3_context*, const char*, int, void(*)(void*));
    void sqlite3_result_value(sqlite3_context*, sqlite3_value*);
    void sqlite3_result_pointer(sqlite3_context*, void*, const char*, void(*)(void*));
    void sqlite3_result_zeroblob(sqlite3_context*, int);
    int sqlite3_result_zeroblob64(sqlite3_context*, sqlite3_uint64);
  ]]

  function funcs.result_blob(context, poiner, size, destructor)
    clib.sqlite3_result_blob(context, poiner, size, destructor)
  end

  function funcs.result_blob64(context, poiner, size, destructor)
    clib.sqlite3_result_blob64(context, poiner, size, destructor)
  end

  function funcs.result_double(context, value)
    clib.sqlite3_result_double(context, value)
  end

  function funcs.result_error(context, text, length)
    if type(text) == 'string' then
      clib.sqlite3_result_error(context, text, length or #text)
    else
      clib.sqlite3_result_error(context, text, length)
    end
  end

  function funcs.result_error_toobig(context)
    clib.sqlite3_result_error_toobig(context)
  end

  function funcs.result_error_nomem(context)
    clib.sqlite3_result_error_nomem(context)
  end

  function funcs.result_error_code(context, code)
    clib.sqlite3_result_error_code(context, code)
  end

  function funcs.result_int(context, value)
    clib.sqlite3_result_int(context, value)
  end

  function funcs.result_int64(context, value)
    clib.sqlite3_result_int64(context, value)
  end

  function funcs.result_null(context, value)
    clib.sqlite3_result_null(context, value)
  end

  function funcs.result_text(context, text, length, destructor)
    if type(text) == 'string' then
      clib.sqlite3_result_text(context, text, length or #text, nil)
    else
      clib.sqlite3_result_text(context, text, length, destructor)
    end
  end

  function funcs.result_value(context, value)
    clib.sqlite3_result_value(context, value)
  end

  function funcs.result_pointer(context, pointer, type, destructor)
    clib.sqlite3_result_pointer(context, pointer, type, destructor)
  end

  function funcs.result_zeroblob(context, size)
    clib.sqlite3_result_zeroblob(context, size)
  end

  function funcs.result_zeroblob64(context, size)
    return clib.sqlite3_result_zeroblob64(context, size)
  end


  ffi.cdef [[ void sqlite3_result_subtype(sqlite3_context*, unsigned int); ]]
  function funcs.result_subtype(context, subtype)
    clib.sqlite3_result_subtype(context, subtype)
  end



  -----------------------------------------------------------
  --  Extended Functions
  -----------------------------------------------------------
  function funcs.using_db(filename, func)
    local pdb  = ffi.new('sqlite3*[1]')
    local code = clib.sqlite3_open(filename, pdb)
    if code == const.OK then
      func(pdb[0])
    end
    clib.sqlite3_close(pdb[0])
    return code
  end

  function funcs.execf(db, str, ...)
    return db:exec(string.format(str, ...))
  end

  function funcs.using_stmt(db, sql, func)
    local code, stmt = funcs.prepare_v2(db, sql)
    if code == const.OK then
      func(db, stmt)
      clib.sqlite3_finalize(stmt)
    end
    return code
  end

  function funcs.using_stmt_loop(db, sql, func)
    local code, stmt = funcs.prepare_v2(db, sql)
    if code == const.OK then
      while funcs.step(stmt) == const.ROW do
        func(db, stmt)
      end
      funcs.finalize(stmt)
    end
    return code
  end

  do
    local function stmt_next(stmt)
      local code = funcs.step(stmt)
      if code == const.ROW then
        return stmt
      elseif code == const.DONE then
        funcs.finalize(stmt)
      else
        return nil, code
      end
    end

    function funcs.using_stmt_iter(db, sql)
      local code, stmt = funcs.prepare_v2(db, sql)
      if code == const.OK then
        return stmt_next, stmt
      else
        return stmt_next, nil
      end
    end
  end

  function funcs.stmt_loop(stmt, func)
    local code
    while true do
      code = funcs.step(stmt)
      if code == const.ROW then
        func(stmt)
      elseif code == const.DONE then
        funcs.reset(stmt)
        return code
      else
        return code
      end
    end
  end

  function funcs.stmt_next(stmt)
    local code = funcs.step(stmt)
    if code == const.ROW then
      return stmt
    elseif code == const.DONE then
      funcs.reset(stmt)
    else
      return nil, code
    end
  end

  function funcs.stmt_iter(stmt)
    return funcs.stmt_next, stmt
  end


  sqlite3_mt.close                 = funcs.close
  sqlite3_mt.close_v2              = funcs.close_v2
  sqlite3_mt.exec                  = funcs.exec
  sqlite3_mt.last_insert_rowid     = funcs.last_insert_rowid
  sqlite3_mt.extended_result_codes = funcs.extended_result_codes
  sqlite3_mt.errcode               = funcs.errcode
  sqlite3_mt.extended_errcode      = funcs.extended_errcode
  sqlite3_mt.errmsg                = funcs.errmsg
  sqlite3_mt.limit                 = funcs.limit
  sqlite3_mt.progress_handler      = funcs.progress_handler
  sqlite3_mt.busy_handler          = funcs.busy_handler
  sqlite3_mt.busy_timeout          = funcs.busy_timeout
  sqlite3_mt.commit_hook           = funcs.commit_hook
  sqlite3_mt.rollback_hook         = funcs.rollback_hook
  sqlite3_mt.update_hook           = funcs.update_hook
  sqlite3_mt.unlock_notify         = funcs.unlock_notify
  sqlite3_mt.set_authorizer        = funcs.set_authorizer
  sqlite3_mt.trace_v2              = funcs.trace_v2
  sqlite3_mt.changes               = funcs.changes
  sqlite3_mt.total_changes         = funcs.total_changes
  sqlite3_mt.interrupt             = funcs.interrupt
  sqlite3_mt.get_autocommit        = funcs.get_autocommit
  sqlite3_mt.table_column_metadata = funcs.table_column_metadata
  sqlite3_mt.next_stmt             = funcs.next_stmt
  sqlite3_mt.prepare               = funcs.prepare
  sqlite3_mt.prepare_v2            = funcs.prepare_v2
  sqlite3_mt.db_filename           = funcs.db_filename
  sqlite3_mt.db_readonly           = funcs.db_readonly

  sqlite3_stmt_mt.finalize             = funcs.finalize
  sqlite3_stmt_mt.db_handle            = funcs.db_handle
  sqlite3_stmt_mt.step                 = funcs.step
  sqlite3_stmt_mt.reset                = funcs.reset
  sqlite3_stmt_mt.clear_bindings       = funcs.clear_bindings
  sqlite3_stmt_mt.busy                 = funcs.stmt_busy
  sqlite3_stmt_mt.readonly             = funcs.stmt_readonly
  sqlite3_stmt_mt.status               = funcs.stmt_status
  sqlite3_stmt_mt.isexplain            = funcs.stmt_isexplain
  sqlite3_stmt_mt.sql                  = funcs.sql
  sqlite3_stmt_mt.expanded_sql         = funcs.expanded_sql
  sqlite3_stmt_mt.normalized_sql       = funcs.normalized_sql
  sqlite3_stmt_mt.bind_parameter_count = funcs.bind_parameter_count
  sqlite3_stmt_mt.bind_parameter_name  = funcs.bind_parameter_name
  sqlite3_stmt_mt.bind_parameter_index = funcs.bind_parameter_index
  sqlite3_stmt_mt.bind_blob            = funcs.bind_blob
  sqlite3_stmt_mt.bind_blob64          = funcs.bind_blob64
  sqlite3_stmt_mt.bind_double          = funcs.bind_double
  sqlite3_stmt_mt.bind_int             = funcs.bind_int
  sqlite3_stmt_mt.bind_int64           = funcs.bind_int64
  sqlite3_stmt_mt.bind_null            = funcs.bind_null
  sqlite3_stmt_mt.bind_text            = funcs.bind_text
  sqlite3_stmt_mt.bind_value           = funcs.bind_value
  sqlite3_stmt_mt.bind_zeroblob        = funcs.bind_zeroblob
  sqlite3_stmt_mt.bind_zeroblob64      = funcs.bind_zeroblob64
  sqlite3_stmt_mt.data_count           = funcs.data_count
  sqlite3_stmt_mt.column_count         = funcs.column_count
  sqlite3_stmt_mt.column_name          = funcs.column_name
  sqlite3_stmt_mt.column_decltype      = funcs.column_decltype
  sqlite3_stmt_mt.column_database_name = funcs.column_database_name
  sqlite3_stmt_mt.column_table_name    = funcs.column_table_name
  sqlite3_stmt_mt.column_origin_name   = funcs.column_origin_name
  sqlite3_stmt_mt.column_blob          = funcs.column_blob
  sqlite3_stmt_mt.column_bytes         = funcs.column_bytes
  sqlite3_stmt_mt.column_double        = funcs.column_double
  sqlite3_stmt_mt.column_int           = funcs.column_int
  sqlite3_stmt_mt.column_int64         = funcs.column_int64
  sqlite3_stmt_mt.column_text          = funcs.column_text
  sqlite3_stmt_mt.column_type          = funcs.column_type
  sqlite3_stmt_mt.column_value         = funcs.column_value

  sqlite3_value_mt.dup          = funcs.value_dup
  sqlite3_value_mt.free         = funcs.value_free
  sqlite3_value_mt.subtype      = funcs.value_subtype
  sqlite3_value_mt.blob         = funcs.value_blob
  sqlite3_value_mt.bytes        = funcs.value_bytes
  sqlite3_value_mt.double       = funcs.value_double
  sqlite3_value_mt.int          = funcs.value_int
  sqlite3_value_mt.int64        = funcs.value_int64
  sqlite3_value_mt.text         = funcs.value_text
  sqlite3_value_mt.type         = funcs.value_type
  sqlite3_value_mt.numeric_type = funcs.value_numeric_type
  sqlite3_value_mt.nochange     = funcs.value_nochange
  sqlite3_value_mt.frombind     = funcs.value_frombind

  sqlite3_context_mt.db_handle           = funcs.context_db_handle
  sqlite3_context_mt.user_data           = funcs.user_data
  sqlite3_context_mt.get_auxdata         = funcs.get_auxdata
  sqlite3_context_mt.set_auxdata         = funcs.set_auxdata
  sqlite3_context_mt.aggregate_context   = funcs.aggregate_context
  sqlite3_context_mt.result_blob         = funcs.result_blob
  sqlite3_context_mt.result_blob64       = funcs.result_blob64
  sqlite3_context_mt.result_double       = funcs.result_double
  sqlite3_context_mt.result_error        = funcs.result_error
  sqlite3_context_mt.result_error_toobig = funcs.result_error_toobig
  sqlite3_context_mt.result_error_nomem  = funcs.result_error_nomem
  sqlite3_context_mt.result_error_code   = funcs.result_error_code
  sqlite3_context_mt.result_int          = funcs.result_int
  sqlite3_context_mt.result_int64        = funcs.result_int64
  sqlite3_context_mt.result_null         = funcs.result_null
  sqlite3_context_mt.result_text         = funcs.result_text
  sqlite3_context_mt.result_value        = funcs.result_value
  sqlite3_context_mt.result_zeroblob     = funcs.result_zeroblob
  sqlite3_context_mt.result_zeroblob64   = funcs.result_zeroblob64
  sqlite3_context_mt.result_subtype      = funcs.result_subtype

  -- Extended Methods
  sqlite3_mt.execf           = funcs.execf
  sqlite3_mt.using_stmt      = funcs.using_stmt
  sqlite3_mt.using_stmt_loop = funcs.using_stmt_loop
  sqlite3_mt.using_stmt_iter = funcs.using_stmt_iter
  sqlite3_stmt_mt.next       = funcs.stmt_next
  sqlite3_stmt_mt.loop       = funcs.stmt_loop
  sqlite3_stmt_mt.iter       = funcs.stmt_iter

  -----------------------------------------------------------
  --  Finalize types metatables
  -----------------------------------------------------------
  ffi.metatype('sqlite3', sqlite3_mt)
  ffi.metatype('sqlite3_stmt', sqlite3_stmt_mt)
  ffi.metatype('sqlite3_value', sqlite3_value_mt)
  ffi.metatype('sqlite3_context', sqlite3_context_mt)
  ffi.metatype('sqlite3_backup', sqlite3_backup_mt)
end

-----------------------------------------------------------
--  Auxiliary
-----------------------------------------------------------
function aux.class()
  local class = {}
  class.__index = class
  return class
end

function aux.set_mt_method(t,k,v)
  local mt = getmetatable(t)
  if mt then
    mt[k] = v
  else
    setmetatable(t, { [k] = v })
  end
end

if is_luajit then
  -- LuaJIT way to compare with NULL
  function aux.is_null(ptr)
    return ptr == nil
  end
else
  -- LuaFFI way to compare with NULL
  function aux.is_null(ptr)
    return ptr == ffi.C.NULL
  end
end

function aux.wrap_string(c_str)
  if not aux.is_null(c_str) then
    return ffi.string(c_str)
  end
  return nil
end

function aux.wrap_bool(c_bool)
  return c_bool ~= 0
end

return setmetatable(mod, { __call = init })
local ffi = require "ffi"

-- LuaJIT FFI wrapper over `libturso_ffi.so` (see `crates/turso_ffi`), exposing the
-- same `open`/`db`/`stmt` object model as `thirdparty_lib.sqlite3` so that
-- LuaDataBaseV2 can reuse its sqlite3 code path unchanged.
--
-- Unlike the sqlite3 backend (which resolves `libsqlite3.so` through
-- LD_LIBRARY_PATH and may hit ancient copies shipped by EDA tools, e.g. VCS's
-- sqlite 3.7.13 lacking `sqlite3_errstr`), this library is loaded by absolute
-- path from `$VERILUA_HOME/shared` and has no external sqlite dependency.

ffi.cdef [[
    typedef struct verilua_turso_db verilua_turso_db;
    typedef struct verilua_turso_stmt verilua_turso_stmt;

    int turso_ffi_open(const char* path, verilua_turso_db** out_db);
    int turso_ffi_close(verilua_turso_db* db);
    int turso_ffi_exec(verilua_turso_db* db, const char* sql);
    int turso_ffi_prepare(verilua_turso_db* db, const char* sql, verilua_turso_stmt** out_stmt);
    int turso_ffi_bind_int(verilua_turso_stmt* stmt, int idx, int64_t value);
    int turso_ffi_bind_text(verilua_turso_stmt* stmt, int idx, const char* text, int len);
    int turso_ffi_step(verilua_turso_stmt* stmt);
    int turso_ffi_reset(verilua_turso_stmt* stmt);
    int turso_ffi_finalize(verilua_turso_stmt* stmt);
    const char* turso_ffi_errmsg(verilua_turso_db* db);
    int64_t turso_ffi_column_int(verilua_turso_stmt* stmt, int idx);
    const char* turso_ffi_column_text(verilua_turso_stmt* stmt, int idx);
]]

---@class verilua.utils.Turso.db
---@field exec fun(self: verilua.utils.Turso.db, sql: string): integer
---@field errmsg fun(self: verilua.utils.Turso.db): string
---@field prepare_v2 fun(self: verilua.utils.Turso.db, sql: string): integer, verilua.utils.Turso.stmt?
---@field close fun(self: verilua.utils.Turso.db): integer

---@class verilua.utils.Turso.stmt
---@field bind_int fun(self: verilua.utils.Turso.stmt, idx: integer, value: integer): integer
---@field bind_text fun(self: verilua.utils.Turso.stmt, idx: integer, text: string): integer
---@field step fun(self: verilua.utils.Turso.stmt): integer
---@field reset fun(self: verilua.utils.Turso.stmt): integer
---@field finalize fun(self: verilua.utils.Turso.stmt): integer
---@field column_int fun(self: verilua.utils.Turso.stmt, idx: integer): integer
---@field column_text fun(self: verilua.utils.Turso.stmt, idx: integer): string

---@class (exact) verilua.utils.Turso.init.params
---@field lib_path? string Full path to libturso_ffi.so. Default: $VERILUA_HOME/shared/libturso_ffi.so

---@class verilua.utils.Turso
---@field clib ffi.namespace*
local Turso = {
    OK = 0,
    ROW = 100,
    DONE = 101,
    ERR = 1,
}

---@type ffi.namespace*
local clib

--- Load libturso_ffi.so. Idempotent: the first call decides the library path.
---@param params? verilua.utils.Turso.init.params
---@return verilua.utils.Turso
function Turso.init(params)
    if clib then
        return Turso
    end

    local lib_path = params and params.lib_path
    if not lib_path then
        local verilua_home = assert(
            os.getenv("VERILUA_HOME"),
            "[Turso] VERILUA_HOME is not set, cannot locate libturso_ffi.so"
        )
        lib_path = verilua_home .. "/shared/libturso_ffi.so"
    end

    clib = ffi.load(lib_path)
    Turso.clib = clib

    ffi.metatype("verilua_turso_db", {
        __index = {
            exec = function(db, sql)
                return clib.turso_ffi_exec(db, sql)
            end,
            errmsg = function(db)
                return ffi.string(clib.turso_ffi_errmsg(db))
            end,
            prepare_v2 = function(db, sql)
                local out = ffi.new("verilua_turso_stmt*[1]") --[[@as table<integer, verilua.utils.Turso.stmt>]]
                local code = clib.turso_ffi_prepare(db, sql, out)
                if code == Turso.OK then
                    return code, out[0]
                end
                return code, nil
            end,
            close = function(db)
                return clib.turso_ffi_close(db)
            end,
        }
    })

    ffi.metatype("verilua_turso_stmt", {
        __index = {
            bind_int = function(stmt, idx, value)
                return clib.turso_ffi_bind_int(stmt, idx, value)
            end,
            bind_text = function(stmt, idx, text)
                return clib.turso_ffi_bind_text(stmt, idx, text, #text)
            end,
            step = function(stmt)
                return clib.turso_ffi_step(stmt)
            end,
            reset = function(stmt)
                return clib.turso_ffi_reset(stmt)
            end,
            finalize = function(stmt)
                return clib.turso_ffi_finalize(stmt)
            end,
            column_int = function(stmt, idx)
                return clib.turso_ffi_column_int(stmt, idx)
            end,
            column_text = function(stmt, idx)
                return ffi.string(clib.turso_ffi_column_text(stmt, idx))
            end,
        }
    })

    return Turso
end

--- Same contract as thirdparty_lib.sqlite3 `open`: returns `code, db`.
--- On failure the returned handle only carries `errmsg` (real error from turso).
---@param filename string
---@return integer code
---@return verilua.utils.Turso.db db
function Turso.open(filename)
    assert(clib, "[Turso] Turso.init() must be called before Turso.open()")
    local out = ffi.new("verilua_turso_db*[1]") --[[@as table<integer, verilua.utils.Turso.db>]]
    local code = clib.turso_ffi_open(filename, out)
    if code == Turso.OK then
        return code, out[0]
    end
    -- Null db: turso_ffi_errmsg(NULL) returns the last global error.
    local err_db = {
        errmsg = function()
            return ffi.string(clib.turso_ffi_errmsg(nil))
        end
    }
    return code, err_db --[[@as verilua.utils.Turso.db]]
end

return Turso

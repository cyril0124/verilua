-- Minimal functional + insert throughput check for LuaDataBaseV2 turso backend.
-- Compares sqlite3 vs turso insert throughput under the same V2 API.

_G.verilua_debug = function() end
_G.enable_verilua_debug = false
_G.final = function(_tasks) end

local warnings = {}
_G.verilua_warning = function(msg) warnings[#warnings + 1] = msg end

local os = require "os"
---@diagnostic disable-next-line: unresolved-require
local lfs = require "lfs"
---@diagnostic disable-next-line: unresolved-require
local path = require "pl.path"
local LuaDB = require "verilua.utils.LuaDataBaseV2"

local workdir = os.tmpname()
os.remove(workdir)
assert(lfs.mkdir(workdir))

local function make_db(backend, file_name, save_cnt_max, no_check_bind_value)
    return LuaDB {
        table_name = "t",
        elements = {
            "id => INTEGER",
            "msg => TEXT",
        },
        path = workdir,
        file_name = file_name,
        save_cnt_max = save_cnt_max or 1000,
        backend = backend,
        no_check_bind_value = no_check_bind_value,
        verbose = false,
    }
end

local function close_db(db)
    -- save_cnt is the next free slot (starts at 1); commit only when data is pending.
    -- With the commit-bounds fix an unconditional commit would also be safe.
    if db.save_cnt and db.save_cnt > 1 then
        db:commit()
    end
    if db.db and db.db.close then
        db.db:close()
    end
    db.finished = true
end

local function turso_count(db_path)
    local Turso = require("verilua.utils.Turso").init {}
    local rc, db = Turso.open(db_path)
    assert(rc == Turso.OK, "turso open for readback failed: " .. db:errmsg())
    local code, st = db:prepare_v2("SELECT COUNT(*) FROM t")
    assert(code == Turso.OK, db:errmsg())
    assert(st, "nil stmt")
    local step = st:step()
    assert(step == Turso.ROW, "expected ROW, got " .. tostring(step))
    local n = tonumber(st:column_int(0))
    st:finalize()
    db:close()
    return n
end

-- Functional: turso write path (205 = non-multiple of batch, exercises partial-batch commit)
do
    local db = make_db("turso", "func_turso.db", 100)
    for i = 1, 205 do
        db:save(i, "row-" .. i)
    end
    close_db(db)
    local n = turso_count(path.join(workdir, "func_turso.db"))
    assert(n == 205, "turso readback count " .. tostring(n))
    print("[ok] turso functional save/commit/readback")
end

-- backend = "auto": unusable libsqlite3 => loud warning + fallback to turso.
-- NOTE: must run before anything loads a healthy sqlite3, because
-- thirdparty_lib.sqlite3 caches the first successfully loaded clib process-wide.
do
    local db = LuaDB {
        table_name = "t",
        elements = { "id => INTEGER", "msg => TEXT" },
        path = workdir,
        file_name = "func_auto_turso.db",
        save_cnt_max = 100,
        backend = "auto",
        lib_name = "nonexistent_sqlite3_lib_for_test",
    }
    assert(db.backend == "turso", "auto should fall back to turso, got " .. tostring(db.backend))
    assert(#warnings == 1 and warnings[1]:find("falling back", 1, true), "expected fallback warning")
    for i = 1, 10 do
        db:save(i, "row-" .. i)
    end
    close_db(db)
    local n = turso_count(path.join(workdir, "func_auto_turso.db"))
    assert(n == 10, "auto-turso readback count " .. tostring(n))
    print("[ok] auto backend falls back to turso with loud warning")
end

-- backend = "auto": healthy libsqlite3 => resolves to sqlite3, no new warning
warnings = {}
do
    local db = LuaDB {
        table_name = "t",
        elements = { "id => INTEGER", "msg => TEXT" },
        path = workdir,
        file_name = "func_auto_sqlite.db",
        save_cnt_max = 100,
        backend = "auto",
    }
    assert(db.backend == "sqlite3", "auto should resolve to sqlite3, got " .. tostring(db.backend))
    assert(#warnings == 0, "no warning expected, got: " .. tostring(warnings[1]))
    db:save(1, "x")
    close_db(db)
    print("[ok] auto backend resolves to sqlite3 when healthy")
end

-- Functional: turso no_check_bind_value fast path (turso-specific bind codegen)
do
    local db = make_db("turso", "func_turso_nocheck.db", 50, true)
    for i = 1, 100 do
        db:save(i, "row-" .. i)
    end
    close_db(db)
    local n = turso_count(path.join(workdir, "func_turso_nocheck.db"))
    assert(n == 100, "turso no_check readback count " .. tostring(n))
    print("[ok] turso no_check_bind_value save/commit/readback")
end

local function bench(backend, nrows, batch)
    local file = string.format("bench_%s_%d.db", backend, nrows)
    local t0 = os.clock()
    local db = make_db(backend, file, batch)
    for i = 1, nrows do
        db:save(i, "x" .. i)
    end
    close_db(db)
    local elapsed = os.clock() - t0
    return elapsed, nrows / elapsed
end

local cases = {
    { nrows = 1000,  batch = 100 },
    { nrows = 10000, batch = 1000 },
    { nrows = 50000, batch = 5000 },
}

print("\n=== insert throughput: sqlite3 vs turso ===")
print(string.format("%-8s %-8s %-12s %-12s %-12s %-12s %-10s",
    "nrows", "batch", "sqlite_s", "sqlite_rps", "turso_s", "turso_rps", "ratio"))

for _, c in ipairs(cases) do
    local s_elapsed, s_rps = bench("sqlite3", c.nrows, c.batch)
    local t_elapsed, t_rps = bench("turso", c.nrows, c.batch)
    local ratio = t_rps / s_rps
    print(string.format("%-8d %-8d %-12.4f %-12.0f %-12.4f %-12.0f %-10.2fx",
        c.nrows, c.batch, s_elapsed, s_rps, t_elapsed, t_rps, ratio))
end

print("\nworkdir: " .. workdir)
print("ALL PASS")

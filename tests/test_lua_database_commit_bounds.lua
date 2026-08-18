-- Regressions for LuaDataBase (alias of LuaDataBaseV2) and LuaDataBaseV2:
-- 1) Manual commit()/finalization after a partial batch must write exactly the
--    saved rows (historically it rewrote one stale row: save() kept save_cnt at
--    the last filled slot while commit() flushed 1..save_cnt).
-- 2) Number binding must be exact above 2^31 (historically the sqlite3 checked
--    path used sqlite3_bind_int, a 32-bit C int).

_G.verilua_debug = function() end
_G.enable_verilua_debug = false
_G.verilua_warning = function() end

local final_cbs = {}
_G.final = function(tasks)
    for _, fn in ipairs(tasks) do
        final_cbs[#final_cbs + 1] = fn
    end
end

local os = require "os"
---@diagnostic disable-next-line: unresolved-require
local lfs = require "lfs"
---@diagnostic disable-next-line: unresolved-require
local path = require "pl.path"

local workdir = os.tmpname()
os.remove(workdir)
assert(lfs.mkdir(workdir))

local function sqlite_scalar(db_path, sql)
    ---@diagnostic disable-next-line: unresolved-require
    local sqlite3 = require "lsqlite3"
    local db = sqlite3.open(db_path)
    local n
    for row in db:urows(sql) do
        n = row
    end
    db:close()
    return n
end

local function sqlite_count(db_path, table_name)
    return sqlite_scalar(db_path, "SELECT COUNT(*) FROM " .. table_name)
end

local params = function(file_name)
    return {
        table_name = "t",
        elements = { "id => INTEGER", "msg => TEXT" },
        path = workdir,
        file_name = file_name,
        save_cnt_max = 5,
    }
end

-- LuaDataBase (alias of V2): 7 saves with batch 5 => auto-commit(5) + manual
-- commit(2); extra commit is a no-op. Also proves the alias require path is a
-- drop-in for the old lsqlite3-based implementation.
do
    local LuaDB = require "verilua.utils.LuaDataBase"
    local db = LuaDB(params("v1.db"))
    for i = 1, 7 do
        db:save(i, "row-" .. i)
    end
    db:commit()
    db:commit()   -- empty commit must not add rows
    ---@diagnostic disable-next-line: access-invisible
    db.db:close() -- release EXCLUSIVE lock for readback
    local n = sqlite_count(path.join(workdir, "v1.db"), "t")
    assert(n == 7, "V1 expected 7 rows, got " .. tostring(n))
    print("[ok] V1 partial-batch commit writes exact rows")
end

-- V2 (sqlite3 backend): same shape, plus the finalization commit path
final_cbs = {}
do
    local LuaDB = require "verilua.utils.LuaDataBaseV2"
    local db = LuaDB(params("v2.db"))
    for i = 1, 7 do
        db:save(i, "row-" .. i)
    end
    db:commit()
    for _, fn in ipairs(final_cbs) do -- clean_up commits again; must be a no-op
        fn()
    end
    ---@diagnostic disable-next-line: access-invisible
    db.db:close() -- release EXCLUSIVE lock for readback
    local n = sqlite_count(path.join(workdir, "v2.db"), "t")
    assert(n == 7, "V2 expected 7 rows, got " .. tostring(n))
    print("[ok] V2 partial-batch commit + finalization writes exact rows")
end

-- V2 sqlite3: numbers above 2^31 must survive exactly (bind_double, not bind_int)
do
    local LuaDB = require "verilua.utils.LuaDataBaseV2"
    local db = LuaDB(params("v2_big.db"))
    local big = 2 ^ 40 + 12345
    db:save(big, "big")
    db:commit()
    ---@diagnostic disable-next-line: access-invisible
    db.db:close()
    local got = sqlite_scalar(path.join(workdir, "v2_big.db"), "SELECT id FROM t")
    assert(got == big, "expected " .. big .. ", got " .. tostring(got))
    print("[ok] V2 sqlite3 binds >2^31 numbers exactly")
end

print("ALL PASS")

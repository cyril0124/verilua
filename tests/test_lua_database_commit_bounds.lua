-- Regression: manual commit()/finalization after a partial batch must write
-- exactly the saved rows (historically it rewrote one stale row: save() kept
-- save_cnt at the last filled slot while commit() flushed 1..save_cnt).

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

local function sqlite_count(db_path, table_name)
    ---@diagnostic disable-next-line: unresolved-require
    local sqlite3 = require "lsqlite3"
    local db = sqlite3.open(db_path)
    local n
    for row in db:urows("SELECT COUNT(*) FROM " .. table_name) do
        n = row
    end
    db:close()
    return n
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

-- V1: 7 saves with batch 5 => auto-commit(5) + manual commit(2); extra commit is a no-op
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

print("ALL PASS")

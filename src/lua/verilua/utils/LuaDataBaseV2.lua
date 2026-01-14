---@diagnostic disable: unnecessary-assert

local io = require "io"
local os = require "os"
local ffi = require "ffi"
local lfs = require "lfs"
local path = require "pl.path"
local class = require "pl.class"
local utils = require "LuaUtils"
local texpect = require "TypeExpect"
local table_new = require "table.new"
local subst = require("pl.template").substitute

---@type any
local sqlite3
---@type any
local sqlite3_clib

---@type verilua.utils.duckdb
local duckdb

local DB_OK = 0
local DB_ERR = 1

local print = print
local pairs = pairs
local string = string
local assert = assert
local ipairs = ipairs
local f = string.format
local table_insert = table.insert

local verilua_debug = _G.verilua_debug

ffi.cdef [[
    typedef int pid_t;
    pid_t getpid(void);
]]

local function sqlite3_bind_values(stmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        local t = type(v)
        if t == "number" then
            stmt:bind_int(i, v)
        elseif t == "string" then
            stmt:bind_text(i, v)
        else
            assert(false, "[LuaDataBaseV2.sqlite3_bind_values] Unsupported data type: " .. t)
        end
    end
end

---@alias verilua.utils.LuaDataBase.elements.type "integer" | "text" | "INTEGER" | "TEXT"

---@class verilua.utils.LuaDataBase.elements.entry
---@field name string
---@field type verilua.utils.LuaDataBase.elements.type

---@class verilua.utils.LuaDataBase.pragmas
---@field journal_mode? "MEMORY" | "DELETE" | "TRUNCATE" | "PERSIST" | "WAL" | "OFF" Default: OFF
---@field synchronous? "OFF" | "FULL" | "NORMAL" Default: OFF
---@field locking_mode? "NORMAL" | "EXCLUSIVE" Default: EXCLUSIVE
---@field foreign_keys? "ON" | "OFF" Default: OFF
---@field cache_size? string Default: -1000000(1GB)

---@class (exact) verilua.utils.LuaDataBase.params
---@field table_name string
---@field elements string[] | verilua.utils.LuaDataBase.elements.entry[]
---@field path? string
---@field file_name string
---@field save_cnt_max? integer Default: 10000
---@field size_limit? integer Default: nil, in bytes
---@field table_cnt_max? integer Default: nil
---@field verbose? boolean Default: false
---@field no_check_bind_value? boolean Default: false, the caller is responsible for the data to be bound, good for performance
---@field backend? "sqlite3" | "duckdb"
---@field lib_name? string Default: sqlite3/duckdb
---@field lib_path? string Default: nil
---@field pragmas? verilua.utils.LuaDataBase.pragmas

---@class (exact) verilua.utils.LuaDataBase
---@overload fun(params: verilua.utils.LuaDataBase.params): verilua.utils.LuaDataBase
---@field private db any
---@field private duckdb_config verilua.utils.duckdb.duckdb_config
---@field private duckdb_conn verilua.utils.duckdb.duckdb_connection
---@field private duckdb_appd verilua.utils.duckdb.duckdb_appender
---@field private backend "sqlite3" | "duckdb"
---@field private size_limit? integer
---@field private file_count integer
---@field private path_name string
---@field private file_name string
---@field private table_name string
---@field private table_name_template string
---@field private fullpath_name string
---@field private available_files table<integer, string>
---@field private entries verilua.utils.LuaDataBase.elements.entry[]
---@field private stmt any
---@field private finished boolean
---@field private verbose boolean
---@field __type string
---@field elements string[]
---@field private pid integer
---@field private create_table_cmd_template string
---@field private create_table_cmd string
---@field private prepare_cmd_template string
---@field private prepare_cmd string
---@field private pragma_cmd string
---@field private save_cnt_max integer Call `<verilua.utils.LuaDataBase>:commit()` when the `save_cnt` exceeds this value
---@field private save_cnt integer The count of data saved without calling commit
---@field private table_cnt_max? integer Default: nil, the max count of table entries, once the table count exceeds this value, new table will be created
---@field private table_cnt integer
---@field private table_idx integer
---@field private cache table
---@field private _log fun(self: verilua.utils.LuaDataBase, ...)
---@field private create_db fun(self: verilua.utils.LuaDataBase)
---@field private create_table fun(self: verilua.utils.LuaDataBase)
---@field save  fun(self: verilua.utils.LuaDataBase, ...)
---@field commit fun(self: verilua.utils.LuaDataBase,...)
local LuaDataBaseV2 = class()

--- e.g.
--- ```lua
---      local LuaDB = require "verilua.utils.LuaDataBaseV2"
---      local db = LuaDB {
---          table_name = "a_table",
---          elements = {
---                "val_1 => INTEGER",
---                "val_2 => INTEGER",
---                "val_3 => integer", -- case insensitive
---                "others => TEXT",
---          },
---          path = "./db",
---          file_name = "test.db",
---          save_cnt_max = 1000,
---          verbose = true
---      }
---
---      -- or
---      local db = LuaDB {
---          table_name = "a_table",
---          elements = {
---                { name = "val_1", type = "INTEGER" },
---                { name = "val_2", type = "INTEGER" },
---                { name = "val_3", type = "integer" }, -- case insensitive
---                { name = "others", type = "TEXT" },
---          },
---          path = "./db",
---          file_name = "test.db",
---          save_cnt_max = 1000,
---          verbose = true
---      }
---
---      db:save(123, 456, 789, "hello") -- Notice: parametes passed into this function should hold the `same order` and same number as the elements in the table
--- ```

---@param params verilua.utils.LuaDataBase.params
function LuaDataBaseV2:_init(params)
    texpect.expect_table(params, "LuaDataBaseV2::_init::params", {
        "table_name",
        "elements",
        "path",
        "file_name",
        "save_cnt_max",
        "size_limit",
        "table_cnt_max",
        "verbose",
        "no_check_bind_value",
        "backend",
        "lib_name",
        "lib_path",
        "pragmas",
    })

    local save_cnt_max  = params.save_cnt_max or 10000
    local table_cnt_max = params.table_cnt_max
    local verbose       = params.verbose or false
    local table_name    = params.table_name
    local elements      = params.elements
    local file_name     = params.file_name
    local path_name     = params.path
    local size_limit    = params.size_limit -- Size in bytes
    local pragmas       = params.pragmas or {} --[[@as verilua.utils.LuaDataBase.pragmas]]

    local backend       = params.backend or "sqlite3"
    self.backend        = backend

    if backend == "sqlite3" then
        local lib_name = params.lib_name or "sqlite3"
        local lib_path = params.lib_path
        do
            sqlite3 = require("thirdparty_lib.sqlite3") {
                name = lib_name,
                path = lib_path,
            }
            sqlite3_clib = sqlite3.clib
        end
    else
        assert(backend == "duckdb", "Unsupported backend: " .. backend)
        local lib_name = params.lib_name or "duckdb"
        local lib_path = params.lib_path
        do
            duckdb = require("verilua.utils.DuckDB")
            duckdb:init {
                name = lib_name,
                path = lib_path,
            }
        end
    end

    local no_check_bind_value = params.no_check_bind_value

    texpect.expect_string(table_name, "table_name")
    texpect.expect_table(elements, "elements")
    texpect.expect_string(file_name, "file_name")
    texpect.expect_table(pragmas, "pragmas", {
        "cache_size",
        "journal_mode",
        "synchronous",
        "locking_mode",
        "foreign_keys",
    })

    self.size_limit = size_limit
    self.file_count = 0

    self.table_name = table_name
    self.table_name_template = "%s"
    self.path_name = path_name
    self.file_name = file_name
    self.fullpath_name = ""
    self.available_files = {}

    self.entries = {}
    self.create_table_cmd = ""
    self.stmt = nil
    self.finished = false
    self.verbose = verbose or false

    -- Used for type check(TypeExpect)
    self.__type = "LuaDataBase"
    self.elements = {}

    -- This is used when `LightSSS` is enabled.
    -- If the pid of each LuaDataBaseV2 instance is different, then the database will not be committed
    self.pid = ffi.C.getpid()

    if path_name ~= nil then
        self.path_name = path_name
        self.file_name = path.basename(path.join(path_name, file_name))
    else
        self.path_name = path.dirname(file_name)
        self.file_name = path.basename(file_name)
    end

    if self.size_limit then
        self.fullpath_name = path.join(self.path_name, self.file_count .. "__" .. self.file_name)
    else
        self.fullpath_name = path.join(self.path_name, self.file_name)
    end

    local pre_alloc_entry = {}
    local entry_names = table_new(#elements, 0)
    local pattern_table = table_new(#elements, 0)
    for i, kv_str in ipairs(elements) do
        local key, data_type
        local t = type(kv_str)
        if t == "table" then
            ---@cast kv_str verilua.utils.LuaDataBase.elements.entry
            key = kv_str.name
            data_type = kv_str.type
        elseif t == "string" then
            ---@cast kv_str string
            texpect.expect_string(kv_str, "kv_str")

            key, data_type = kv_str:match("([^%s=>]+)%s*=>%s*([^%s]+)")
        else
            assert(false, "[LuaDataBaseV2] Unsupported type: " .. t)
        end

        ---@cast data_type string

        data_type = data_type:upper()
        assert(data_type == "INTEGER" or data_type == "TEXT", "[LuaDataBaseV2] Unsupported data type: " .. data_type)

        if data_type == "INTEGER" then
            table_insert(pre_alloc_entry, 0)
        else
            table_insert(pre_alloc_entry, "")
        end

        if backend == "duckdb" then
            if data_type == "INTEGER" then
                data_type = "BIGINT"
            else
                data_type = "VARCHAR"
            end
        end

        self.elements[#self.elements + 1] = key .. "=>" .. data_type
        self.entries[#self.entries + 1] = { name = key, type = data_type }
        entry_names[i] = key
        pattern_table[i] = key .. " " .. data_type
    end

    self.table_cnt_max = table_cnt_max
    self.table_cnt = 0
    self.table_idx = 0
    if self.table_cnt_max then
        texpect.expect_number(self.table_cnt_max, "table_cnt_max")
        self.table_name_template = "_%04d_" .. table_name
        self.table_name = f(self.table_name_template, 0)
    end

    if backend == "duckdb" then
        self.create_table_cmd_template = subst(
            "CREATE OR REPLACE TABLE %s \n( $(pattern_str) );",
            { pattern_str = table.concat(pattern_table, ", ") }
        )
    else
        self.create_table_cmd_template = subst(
            "CREATE TABLE %s \n( $(pattern_str) );",
            { pattern_str = table.concat(pattern_table, ", ") }
        )
    end
    self.create_table_cmd = f(self.create_table_cmd_template, self.table_name)

    -- Create prepare cmd for stmt
    local tmp_table = {}
    for _, _ in pairs(self.entries) do
        table.insert(tmp_table, "?")
    end
    self.prepare_cmd_template = subst(
        "INSERT INTO %s ($(entry_names)) VALUES ($(entry_values))",
        {
            entry_names = table.concat(entry_names, ", "),
            entry_values = table.concat(tmp_table, ", ")
        }
    )
    self.prepare_cmd = f(self.prepare_cmd_template, self.table_name)

    -- Create pragma cmd
    self.pragma_cmd = ""
    if backend == "duckdb" then
        local ret, config = duckdb.new_config()
        assert(ret == DB_OK, "duckdb.new_config failed")
        config:set_and_check("default_order", "DESC")

        self.duckdb_config = config
    else
        if pragmas.cache_size then
            texpect.expect_string(pragmas.cache_size, "pragmas.cache_size")
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA cache_size = " .. pragmas.cache_size .. ";"
        else
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA cache_size = -1000000;"
        end
        if pragmas.journal_mode then
            texpect.expect_string(pragmas.journal_mode, "pragmas.journal_mode")
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA journal_mode = " .. pragmas.journal_mode .. ";"
        else
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA journal_mode = OFF;"
        end
        if pragmas.synchronous then
            texpect.expect_string(pragmas.synchronous, "pragmas.synchronous")
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA synchronous = " .. pragmas.synchronous .. ";"
        else
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA synchronous = OFF;"
        end
        if pragmas.locking_mode then
            texpect.expect_string(pragmas.locking_mode, "pragmas.locking_mode")
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA locking_mode = " .. pragmas.locking_mode .. ";"
        else
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA locking_mode = EXCLUSIVE;"
        end
        if pragmas.foreign_keys then
            texpect.expect_string(pragmas.foreign_keys, "pragmas.foreign_keys")
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA foreign_keys = " .. pragmas.foreign_keys .. ";"
        else
            self.pragma_cmd = self.pragma_cmd .. "PRAGMA foreign_keys = OFF;"
        end
    end

    verilua_debug(f(
        "[LuaDataBaseV2] table_name: %s file_name: %s prepare_cmd: %s",
        table_name,
        file_name,
        self.prepare_cmd
    ))

    -- Pre-allocate memory
    self.save_cnt_max = save_cnt_max
    self.save_cnt = 1
    self.cache = table_new(save_cnt_max, 0) -- TODO: using FFI data structure
    for _ = 1, save_cnt_max do
        table_insert(self.cache, pre_alloc_entry)
    end

    -- Create path folder if not exist
    local attributes, err = lfs.attributes(self.path_name .. "/")
    if attributes == nil then
        local success, message = lfs.mkdir(self.path_name .. "/")
        if not success then
            assert(false, "[LuaDataBaseV2] Cannot create folder: " .. self.path_name .. " err: " .. message)
        end
    end

    local create_table_code = subst([[
            return function (this)
|> if backend == "duckdb" then
                local code, errmsg = this.duckdb_conn:exec(this.create_table_cmd)
|> else
                local code = this.db:exec(this.create_table_cmd)
|> end
                if code ~= $(DB_OK) then
|> if backend == "duckdb" then
                    assert(false, string.format("[LuaDataBase] [%s] $(backend) error: %s", this.fullpath_name, errmsg))
|> else
                    assert(false, string.format("[LuaDataBase] [%s] $(backend) error: %s", this.fullpath_name, this.db:errmsg()))
|> end
                else
                    if this.table_cnt_max then
                        this.table_cnt = 0
                    end
|> if enable_verilua_debug then
                    verilua_debug("[LuaDataBaseV2] cmd execute success! cmd => " .. this.create_table_cmd)
|> end
                end

|> if backend == "duckdb" then
                local ret, appd = this.duckdb_conn:new_appender(this.table_name)
                if ret ~= $(DB_OK) then
                    assert(false, string.format("[LuaDataBase] [%s] $(backend) failed to create appender", this.fullpath_name))
                end
                this.duckdb_appd = appd
|> end
            end
    ]],
        {
            _escape = "|>",
            enable_verilua_debug = _G.enable_verilua_debug,
            backend = backend,
            DB_OK = DB_OK
        }
    )
    self.create_table = utils.loadcode(create_table_code)

    -- Create database
    self:create_db()

    -- This is a tricky way to remove `table.unpack` which cannot be JIT-compiled by LuaJIT
    local narg = #elements
    local args_table = table_new(narg, 0)
    local commit_data_unpack_items = table_new(narg, 0)
    for i = 1, narg do
        args_table[i] = "v" .. i
        commit_data_unpack_items[i] = "__cache_value[" .. i .. "]"
    end

    local bind_values_code
    if self.backend == "duckdb" then
        if no_check_bind_value then
            local t = {}
            for i, entry in ipairs(self.entries) do
                if entry.type == "BIGINT" then
                    t[#t + 1] = subst([[
                        local __cache_value__$(n) = __cache_value[$(i)]
                        this.duckdb_appd:append_uint64(__cache_value__$(n)) ]],
                        { i = i, n = entry.name }
                    )
                elseif entry.type == "VARCHAR" then
                    t[#t + 1] = subst([[
                        local __cache_value__$(n) = __cache_value[$(i)]
                        this.duckdb_appd:append_string(__cache_value__$(n)) ]],
                        { i = i, n = entry.name }
                    )
                else
                    assert(false, "[LuaDataBaseV2] Unsupported data type: " .. entry.type)
                end
            end
            bind_values_code = table.concat(t, "\n\n")
        else
            bind_values_code = subst(
                "this.duckdb_appd:append_values($(commit))",
                {
                    commit = table.concat(commit_data_unpack_items, ", ")
                }
            )
        end
    else
        if no_check_bind_value then
            local t = {}
            for i, entry in ipairs(self.entries) do
                if entry.type == "INTEGER" then
                    t[#t + 1] = subst([[
                        local __cache_value__$(n) = __cache_value[$(i)]
                        sqlite3_clib.sqlite3_bind_double(stmt, $(i), __cache_value__$(n)) ]],
                        { i = i, n = entry.name }
                    )
                elseif entry.type == "TEXT" then
                    t[#t + 1] = subst([[
                        local __cache_value__$(n) = __cache_value[$(i)]
                        sqlite3_clib.sqlite3_bind_text(stmt, $(i), __cache_value__$(n), #__cache_value__$(n), nil) ]],
                        { i = i, n = entry.name }
                    )
                else
                    assert(false, "[LuaDataBaseV2] Unsupported data type: " .. entry.type)
                end
            end
            bind_values_code = table.concat(t, "\n\n")
        else
            bind_values_code = subst(
                "sqlite3_bind_values(stmt, $(commit))",
                {
                    commit = table.concat(commit_data_unpack_items, ", ")
                }
            )
        end
    end

    --
    -- e.g.
    --      save = function (this, v1, v2, v3)
    --          local save_cnt = this.save_cnt
    --          this.cache[save_cnt] = {v1, v2, v3}
    --          if save_cnt >= 1000 then
    --              this:commit()
    --          else
    --              this.save_cnt = save_cnt + 1
    --          end
    --      end
    --
    local save_func_code = subst([[
        return function(this, $(args))
            local save_cnt = this.save_cnt
            this.cache[save_cnt] = {$(args)}
            if save_cnt >= $(save_cnt_max) then
                this:commit()
            else
                this.save_cnt = save_cnt + 1
            end
        end
    ]], {
        args = table.concat(args_table, ", "),
        save_cnt_max = self.save_cnt_max
    })

    local _perpare_cmd = self.table_cnt_max and "this.prepare_cmd" or "\"" .. self.prepare_cmd .. "\""
    local size_limit_check_code = ""
    local table_cnt_check_code = ""
    if self.size_limit then
        size_limit_check_code = subst([[
            if this.finished then
                return
            end

            -- Size in bytes
            local size = lfs_attributes(this.fullpath_name, "size")
            if size > $(size_limit) then
                -- Close older database
                this.db:close()

                -- Create new database
                this.file_count = this.file_count + 1
                this.fullpath_name = path_join(this.path_name, this.file_count .. "__" .. this.file_name)
                this:create_db()
            end
        ]], { size_limit = self.size_limit })
    end
    if self.table_cnt_max then
        table_cnt_check_code = subst([[
            this.table_cnt = this.table_cnt + 1
            if this.table_cnt >= $(table_cnt_max) then
|> if backend == "duckdb" then
                this.duckdb_appd:flush()
|> else
                stmt:finalize()
                this.db:exec("COMMIT")
|> end

                local table_idx = this.table_idx
                local new_table_name = f(this.table_name_template, table_idx + 1)

                this.create_table_cmd = f(this.create_table_cmd_template, new_table_name)
|> if backend == "duckdb" then
                this.table_name = new_table_name
|> else
                this.prepare_cmd = f(this.prepare_cmd_template, new_table_name)
|> end
                this:create_table()

                this.table_idx = table_idx + 1
                this.table_cnt = 0

|> if backend ~= "duckdb" then
                this.db:exec("BEGIN TRANSACTION")
                code, stmt = this.db:prepare_v2($(prepare))
                if code ~= $(sqlite3_ok) then
                    assert(false, "[LuaDataBaseV2] [commit] SQLite3 error: " .. this.db:errmsg())
                end
|> end
            end
        ]], {
            _escape = "|>",
            backend = self.backend,
            table_cnt_max = self.table_cnt_max,
            prepare = _perpare_cmd,
            sqlite3_ok = DB_OK
        })
    end
    local commit_func_code = subst([[
        return function(this)
            -- This is used when `LightSSS` is enabled.
            -- If the pid of each LuaDataBaseV2 instance is different, then the database will not be committed
            if ffi.C.getpid() ~= $(pid) then
                this.save_cnt = 1
                return
            end

|> if backend == "duckdb" then
            for cnt = 1, this.save_cnt do
                local __cache_value = this.cache[cnt]
                $(bind_values_code)
                this.duckdb_appd:end_row()
                $(table_cnt_check)
            end
            -- Do flush in clean up function
            -- this.duckdb_appd:flush()
|> else
            -- Notice: parametes passed into this function should hold the same order as the elements in the table
            this.db:exec("BEGIN TRANSACTION") -- Start transaction(improve db performance)
            local code, stmt = this.db:prepare_v2($(prepare))
            if code ~= $(sqlite3_ok) then
                assert(false, "[LuaDataBaseV2] [commit] SQLite3 error: " .. this.db:errmsg())
            end

            for cnt = 1, this.save_cnt do
                local __cache_value = this.cache[cnt]
                $(bind_values_code)
                stmt:step()
                stmt:reset()

                $(table_cnt_check)
            end

            stmt:finalize()
            this.db:exec("COMMIT")
|> end

            this.save_cnt = 1

            $(verbose_print)

            $(size_limit_check)
        end
    ]], {
        _escape = "|>",
        backend = self.backend,
        pid = self.pid,
        prepare = _perpare_cmd,
        bind_values_code = bind_values_code,
        sqlite3_ok = DB_OK,
        verbose_print = self.verbose and "this:_log('commit!')" or "",
        size_limit_check = size_limit_check_code,
        table_cnt_check = table_cnt_check_code,
    })

    -- try to remove `table.unpack` which cannot be jit compiled by LuaJIT
    self.save = utils.loadcode(save_func_code, nil, "LuaDataBaseV2:save()")
    self.commit = utils.loadcode(
        commit_func_code,
        {
            ffi = ffi,
            lfs = lfs,
            assert = assert,
            f = string.format,
            sqlite3_bind_values = sqlite3_bind_values,
            lfs_attributes = lfs.attributes,
            sqlite3_clib = sqlite3_clib,
            print = print,
            path_join = path.join
        },
        "LuaDataBaseV2:commit()"
    )

    final {
        function()
            -- Mark as finished
            self.finished = true

            -- Do clean up
            self:clean_up()

            if self.size_limit then
                -- Save available files
                local avail_file = self.path_name .. "/" .. self.file_name .. ".available_files"
                local file = io.open(avail_file, "w")
                assert(file, "[LuaDataBaseV2] Cannot open file: " .. avail_file)
                file:write(table.concat(self.available_files, "\n"))
                file:close()
            end
        end
    }
end

function LuaDataBaseV2:_log(...)
    print(f("[LuaDataBaseV2] [%s]", self.file_name), ...)
    io.flush()
end

function LuaDataBaseV2:create_db()
    -- Remove data base before create it
    local ret, err_msg = os.remove(self.fullpath_name)
    if ret then
        verilua_debug(f("[LuaDataBaseV2] Remove %s success!\n", self.fullpath_name))
    else
        verilua_debug(f("[LuaDataBaseV2] Remove %s failed! => %s\n", self.fullpath_name, err_msg))
    end

    local backend_db = sqlite3
    local is_duckdb = self.backend == "duckdb"
    if is_duckdb then
        backend_db = duckdb
    end

    -- Open database
    if is_duckdb then
        local code, db = backend_db.open(self.fullpath_name, self.duckdb_config)
        if code ~= DB_OK then
            assert(false, f("[LuaDataBaseV2] [%s] Cannot open %s => %s", self.backend, self.fullpath_name, db:errmsg()))
        end

        ---@cast db verilua.utils.duckdb.duckdb_database
        self.db = db

        local ret2, conn = self.db:new_conn()
        assert(ret2 == DB_OK)
        self.duckdb_conn = conn
    else
        local code, db = backend_db.open(self.fullpath_name)
        if code ~= DB_OK then
            assert(false, f("[LuaDataBaseV2] [%s] Cannot open %s => %s", self.backend, self.fullpath_name, db:errmsg()))
        end

        self.db = db

        code = db:exec(self.pragma_cmd)
        if code ~= DB_OK then
            assert(
                false,
                f(
                    "[LuaDataBaseV2] [%s] Cannot set cache size %s => %s",
                    self.backend,
                    self.fullpath_name,
                    db:errmsg()
                )
            )
        end
    end

    -- Add to available files
    table_insert(self.available_files, self.fullpath_name)

    if self.table_cnt_max then
        self.table_idx = 0
        self.table_cnt = 0

        local new_table_name = f(self.table_name_template, 0)
        self.create_table_cmd = f(self.create_table_cmd_template, new_table_name)
        self.prepare_cmd = f(self.prepare_cmd_template, new_table_name)
    end

    self:create_table()
end

function LuaDataBaseV2:clean_up()
    local path = require "pl.path"
    print(f(
        "[LuaDataBaseV2] [%s] [%s => %s] [%s] clean up...\n",
        self.table_name,
        self.fullpath_name,
        path.abspath(self.fullpath_name),
        self.backend
    ))

    self:commit()

    if self.backend == "duckdb" then
        print(f(
            "[LuaDataBaseV2] [%s] [%s => %s] [%s] flush appender...\n",
            self.table_name,
            self.fullpath_name,
            path.abspath(self.fullpath_name),
            self.backend
        ))
        local ret = self.duckdb_appd:flush()
        assert(ret == DB_OK, "[LuaDataBaseV2] [duckdb] Cannot flush appender")
    end
end

return LuaDataBaseV2

local io = require "io"
local os = require "os"
local ffi = require "ffi"
local lfs = require "lfs"
local path = require "pl.path"
local class = require "pl.class"
local sqlite3 = require "lsqlite3"
local texpect = require "TypeExpect"
local table_new = require "table.new"
local subst = require 'pl.template'.substitute

local load = load
local print = print
local pairs = pairs
local printf = printf
local string = string
local assert = assert
local ipairs = ipairs
local f = string.format
local table_insert = table.insert

local verilua_debug = _G.verilua_debug

ffi.cdef[[
    typedef int pid_t;
    pid_t getpid(void);
]]

---@class LuaDataBase.params
---@field table_name string
---@field elements table<string>
---@field path string
---@field file_name string
---@field save_cnt_max? number
---@field verbose? boolean
---@field size_limit? number

---@class LuaDataBase
---@overload fun(params: LuaDataBase.params): LuaDataBase
---@field size_limit number
---@field file_count number
---@field path_name string
---@field file_name string
---@field table_name string
---@field fullpath_name string
---@field available_files table<string>
---@field entries table<string, string>
---@field create_db_cmd string
---@field stmt any
---@field finished boolean
---@field verbose boolean
---@field __type string
---@field elements table<string>
---@field pid number
---@field prepare_cmd string
---@field save_cnt_max number
---@field save_cnt number
---@field cache table
---@field _log fun(self: LuaDataBase, ...)
---@field create_db fun(self: LuaDataBase)
---@field save  fun(self: LuaDataBase, ...)
---@field commit fun(self: LuaDataBase,...)
local LuaDataBase = class()

-- 
-- Example:
--      local LuaDB = require "verilua.utils.LuaDataBase"
--      local db = LuaDB {
--          table_name = "a_table",
--          elements = {
--                "val_1 => INTEGER",
--                "val_2 => INTEGER",
--                "val_3 => INTEGER",
--                "others => TEXT",
--          },
--          path = "./db",
--          file_name = "test.db",
--          save_cnt_max = 1000,
--          verbose = true
--      }
-- 
--      db:save(123, 456, 789, "hello") -- Notice: parametes passed into this function should hold the same order and same number as the elements in the table
-- 

---@param self LuaDataBase
---@param params LuaDataBase.params
function LuaDataBase:_init(params)
    texpect.expect_table(params, "init_tbl")

    local save_cnt_max = params.save_cnt_max or 10000
    local verbose      = params.verbose or false
    local table_name   = params.table_name
    local elements     = params.elements
    local file_name    = params.file_name
    local path_name    = params.path
    local size_limit   = params.size_limit -- Size in bytes

    texpect.expect_string(table_name, "table_name")
    texpect.expect_table(elements, "elements")
    texpect.expect_string(file_name, "file_name")

    -- ---@cast self LuaDataBase
    -- local self = self

    self.size_limit1 = size_limit
    self.file_count = 0

    self.path_name = path_name
    self.file_name = file_name
    self.fullpath_name = ""
    self.available_files = {}

    self.entries = {}
    self.create_db_cmd = ""
    self.stmt = nil
    self.finished = false
    self.verbose = verbose or false

    -- Used for type check(TypeExpect)
    self.__type = "LuaDataBase"
    self.elements = elements

    -- This is used when `LightSSS` is enabled.
    -- If the pid of each LuaDataBase instance is different, then the database will not be committed
    self.pid = ffi.C.getpid()

    if path_name then
        self.path_name = path_name
        self.file_name = path.basename(path_name .. "/" .. file_name)
    else
        self.path_name = path.dirname(file_name)
        self.file_name = path.basename(file_name)
    end

    if self.size_limit then
        self.fullpath_name = self.path_name .. "/" .. self.file_count .. "__" .. self.file_name
    else
        self.fullpath_name = self.path_name .. "/" .. self.file_name
    end

    local pre_alloc_entry = {}
    local entry_names = table_new(#elements, 0)
    local pattern_table = table_new(#elements, 0)
    for i, kv_str in ipairs(elements) do
        texpect.expect_string(kv_str, "kv_str")

        local key, data_type = kv_str:match("([^%s=>]+)%s*=>%s*([^%s]+)")
        assert(data_type == "INTEGER"  or data_type == "TEXT", "[LuaDataBase] Unsupported data type: " .. data_type)

        if data_type == "INTEGER" then
            table_insert(pre_alloc_entry, 0)
        else
            table_insert(pre_alloc_entry, "")
        end

        self.entries[key] = data_type
        entry_names[i] = key
        pattern_table[i] = key .. " " .. data_type
    end

    self.create_db_cmd = f("CREATE TABLE %s \n( %s );", table_name, table.concat(pattern_table, ", "))

    -- Create prepare cmd for stmt
    local tmp_table = {}
    for _, _ in pairs(self.entries) do
        table.insert(tmp_table, "?")
    end
    self.prepare_cmd = subst("INSERT INTO $(table_name) ($(entry_names)) VALUES ($(entry_values))", { table_name = table_name, entry_names = table.concat(entry_names, ", "), entry_values = table.concat(tmp_table, ", ") })

    verilua_debug(f("[LuaDataBase] table_name: %s file_name: %s prepare_cmd: %s", table_name, file_name, self.prepare_cmd))

    -- Pre-allocate memory
    self.save_cnt_max = save_cnt_max
    self.save_cnt = 1
    self.cache = table_new(save_cnt_max, 0) -- TODO: using FFI data structure
    for i = 1, save_cnt_max do
        table_insert(self.cache, pre_alloc_entry)
    end

    -- Create path folder if not exist
    local attributes, err = lfs.attributes(self.path_name .. "/")
    if attributes == nil then
        local success, message = lfs.mkdir(self.path_name .. "/")
        if not success then
            assert(false, "[LuaDataBase] Cannot create folder: " .. self.path_name .. " err: " .. message)
        end
    end

    -- Create database
    self:create_db()

    -- This is a tricky way to remove `table.unpack` which cannot be JIT-compiled by LuaJIT 
    local narg = #self.elements
    local args_table = table_new(narg, 0)
    local commit_data_unpack_items = table_new(narg, 0)
    for i = 1, narg do
        args_table[i] = "v" .. i
        commit_data_unpack_items[i] = "this.cache[i][" .. i .. "]"
    end

    local save_func_str, _, _ = subst([[
    local assert = assert
    local table_insert = table.insert
        
    local func = function(this, $(args))
        this.cache[this.save_cnt] = {$(args)}
        if this.save_cnt >= $(save_cnt_max) then
            this:commit()
        else
            this.save_cnt = this.save_cnt + 1
        end
    end

    return func
    ]], {
        args = table.concat(args_table, ", "),
        save_cnt_max = self.save_cnt_max
    })


    local commit_func_str, _, _ = subst([[
    local assert = assert
    local lfs = require "lfs"

    local func = function(this)
        if this.save_cnt == 1 then
            return
        end

        -- This is used when `LightSSS` is enabled.
        -- If the pid of each LuaDataBase instance is different, then the database will not be committed
        if ffi.C.getpid() ~= $(pid) then
            this.save_cnt = 1
            return
        end

        -- Notice: parametes passed into this function should hold the same order as the elements in the table
        this.db:exec("BEGIN TRANSACTION") -- Start transaction(improve db performance)
        local stmt = assert(this.db:prepare("$(prepare)"), "[commit] stmt is nil")

        for i = 1, this.save_cnt do
            stmt:bind_values($(commit))
            stmt:step()
            stmt:reset()
        end

        stmt:finalize()
        this.db:exec("COMMIT")

        this.save_cnt = 1

        $(verbose_print)

        $(size_limit_check)
    end
    return func
    ]], {
        pid = self.pid, 
        prepare = self.prepare_cmd,
        commit = table.concat(commit_data_unpack_items, ", "),
        verbose_print = self.verbose and "this:_log('commit!')" or "",
        size_limit_check = self.size_limit and [[
            if this.finished then
                return
            end

            -- Size in bytes
            local size = lfs.attributes(this.fullpath_name, "size")
            if size > this.size_limit then
                -- Close older database
                this.db:close()
                
                -- Create new database
                this.file_count = this.file_count + 1
                this.fullpath_name = this.path_name .. "/" .. this.file_count .. "__" .. this.file_name
                this:create_db()
            end
        ]] or ""
    })

    -- try to remove `table.unpack` which cannot be jit compiled by LuaJIT
    self.save = load(save_func_str)()
    self.commit = load(commit_func_str)()

    final {
        function ()
            -- Mark as finished
            self.finished = true

            -- Do clean up
            self:clean_up()

            if self.size_limit then
                -- Save available files
                local file = io.open(self.path_name .. "/" .. self.file_name .. ".available_files", "w")
                assert(file, "[LuaDataBase] Cannot open file: " .. self.path_name .. "/" .. self.file_name .. ".available_files")
                file:write(table.concat(self.available_files, "\n"))
                file:close()
            end
        end
    }
end

function LuaDataBase:_log(...)
    print(f("[LuaDataBase] [%s]", self.file_name), ...)
    io.flush()
end

function LuaDataBase:create_db()
    -- Remove data base before create it
    local ret, err_msg = os.remove(self.fullpath_name)
    if ret then
        verilua_debug(f("[LuaDataBase] Remove %s success!\n", self.fullpath_name))
    else
        verilua_debug(f("[LuaDataBase] Remove %s failed! => %s\n", self.fullpath_name, err_msg))
    end

    -- Open database
    self.db, err_msg = sqlite3.open(self.fullpath_name)
    if not self.db then
        assert(false,  f("[LuaDataBase] Cannot open %s => %s", self.fullpath_name, err_msg))
    end

    -- Add to available files
    table_insert(self.available_files, self.fullpath_name)

    local result_code = self.db:exec(self.create_db_cmd)
    if result_code ~= sqlite3.OK then
        local err_msg = self.db:errmsg()
        assert(false, "[LuaDataBase] SQLite3 error: " .. err_msg)
    else
        verilua_debug("[LuaDataBase] cmd execute success! cmd => " .. self.create_db_cmd)
    end
end

function LuaDataBase:clean_up()
    local path = require "pl.path"
    printf("[LuaDataBase] [%s] [%s => %s] clean up...\n", self.table_name, self.fullpath_name, path.abspath(self.fullpath_name))

    self:commit()
end

return LuaDataBase

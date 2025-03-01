local io = require "io"
local os = require "os"
local ffi = require "ffi"
local lfs = require "lfs"
local class = require "pl.class"
local sqlite3 = require "lsqlite3"
local texpect = require "TypeExpect"
local table_new = require "table.new"

local type = type
local load = load
local print = print
local pairs = pairs
local printf = printf
local string = string
local assert = assert
local ipairs = ipairs
local f = string.format
local table_insert = table.insert
local table_unpack = table.unpack

local verilua = _G.verilua
local verilua_debug = _G.verilua_debug

ffi.cdef[[
    typedef int pid_t;
    pid_t getpid(void);
]]


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
--      db:save(123, 456, 789, "hello") -- Notice: parametes passed into this function should hold the same order as the elements in the table
-- 
function LuaDataBase:_init(init_tbl)
    texpect.expect_table(init_tbl, "init_tbl")    

    local save_cnt_max = init_tbl.save_cnt_max or 10000
    local verbose      = init_tbl.verbose or false
    local table_name   = init_tbl.table_name
    local elements     = init_tbl.elements
    local file_name    = init_tbl.file_name
    local path         = init_tbl.path

    texpect.expect_string(table_name, "table_name")
    texpect.expect_table(elements, "elements")
    texpect.expect_string(file_name, "file_name")
    texpect.expect_string(path, "path")

    self.path = path
    self.file_name = file_name
    self.fullpath_name = path .. "/" .. file_name
    self.entries = {}
    self.stmt = nil
    self.verbose = verbose or false

    -- Used for type check(TypeExpect)
    self.__type = "LuaDataBase"
    self.elements = elements

    -- This is used when lightsss is enabled.
    -- If the pid of each LuaDataBase instance is different, then the database will not be committed
    self.pid = ffi.C.getpid()

    local pre_alloc_entry = {}
    local pattern_str = ""
    for _, kv_str in pairs(elements) do
        texpect.expect_string(kv_str, "kv_str")

        local key, data_type = kv_str:match("([^%s=>]+)%s*=>%s*([^%s]+)")
        assert(data_type == "INTEGER"  or data_type == "TEXT", "[LuaDataBase] Unsupported data type: " .. data_type)

        if data_type == "INTEGER" then
            table_insert(pre_alloc_entry, 0)
        else
            table_insert(pre_alloc_entry, "")
        end

        pattern_str = pattern_str .. key .. " " .. data_type .. ",\n"
    end
    pattern_str = pattern_str:sub(1, #pattern_str - 2) -- remove trailing ",\n"

    -- Pre-allocate memory
    self.save_cnt_max = save_cnt_max
    self.save_cnt = 1
    self.cache = table_new(save_cnt_max, 0) -- TODO: using FFI data structure
    for i = 1, save_cnt_max do
        table_insert(self.cache, pre_alloc_entry)
    end

    -- create path folder if not exist
    local attributes, err = lfs.attributes(path .. "/")
    if attributes == nil then
        local success, message = lfs.mkdir(path .. "/")
        if not success then
            assert(false, "[LuaDataBase] Cannot create folder: " .. path .. " err: " .. message)
        end
    end

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
        assert(false,  "[LuaDataBase] " .. err_msg)
    end

    local cmd = f("CREATE TABLE %s \n( %s );", table_name, pattern_str)
    local result_code = self.db:exec(cmd)
    if result_code ~= sqlite3.OK then
        local err_msg = self.db:errmsg()
        assert(false, "[LuaDataBase] SQLite3 error: " .. err_msg)
    else
        verilua_debug("[LuaDataBase] cmd execute success! cmd => " .. cmd)
    end

    self.db = sqlite3.open(self.fullpath_name)
    assert(self.db ~= nil)

    -- Create prepare cmd for stmt
    self.prepare_cmd = "INSERT INTO " .. table_name .. " ("
    for key, value in string.gmatch(pattern_str, '([%w_]+)%s+(%w+)') do
        self.entries[key] = value
        self.prepare_cmd = self.prepare_cmd .. key .. ","
    end

    self.prepare_cmd = string.sub(self.prepare_cmd, 1, -2) -- recude ","
    self.prepare_cmd = self.prepare_cmd .. ") " .. "VALUES ("
    for _, _ in pairs(self.entries) do
        self.prepare_cmd = self.prepare_cmd .. "?" .. ","
    end
    self.prepare_cmd = string.sub(self.prepare_cmd, 1, -2) -- recude ","
    self.prepare_cmd = self.prepare_cmd .. ")"
    verilua_debug(f("[LuaDataBase] file_name: " .. file_name .. " prepare_cmd: " .. self.prepare_cmd))
    io.flush()

    --
    -- This is a tricky way to remove `table.unpack` which cannot be JIT-compiled by LuaJIT 
    --
    local narg = #self.elements
    local narg_str = ""
    local save_func_str = "local table_insert = table.insert\nlocal assert = assert\nlocal func = function(this, "
    local commit_func_str = "local assert = assert\nlocal func = function(this)\n"
    local commit_data_unpack_str = ""
    for i = 1, narg do
        local t = "v" .. i .. ","
        narg_str = narg_str .. t
        save_func_str = save_func_str .. t
        commit_data_unpack_str = commit_data_unpack_str .. "this.cache[i][" .. i .. "],"
    end
    
    commit_data_unpack_str = commit_data_unpack_str:sub(1, -2)
    save_func_str = save_func_str:sub(1, -2) .. ")"
    save_func_str = save_func_str .. f([[
        this.cache[this.save_cnt] = {%s}
        if this.save_cnt >= %d then
            this:commit()
        else
            this.save_cnt = this.save_cnt + 1
        end
    end
    
    return func 
    ]], narg_str, self.save_cnt_max)

    commit_func_str = commit_func_str .. f([[
        if this.save_cnt == 1 then
            return
        end

        -- This is used when `LightSSS` is enabled.
        -- If the pid of each LuaDataBase instance is different, then the database will not be committed
        if ffi.C.getpid() ~= %s then
            this.save_cnt = 1
            return
        end

        -- Notice: parametes passed into this function should hold the same order as the elements in the table
        this.db:exec("BEGIN TRANSACTION") -- Start transaction(improve db performance)
        local stmt = assert(this.db:prepare(%s), "[commit] stmt is nil")

        for i = 1, this.save_cnt do
            stmt:bind_values(%s)
            stmt:step()
            stmt:reset()
        end

        stmt:finalize()
        this.db:exec("COMMIT")

        this.save_cnt = 1

        %s
    end
    return func
    ]], self.pid, '\"' .. self.prepare_cmd .. '\"', commit_data_unpack_str, self.verbose and "this:_log('commit!')" or "")

    -- try to remove `table.unpack` which cannot be jit compiled by LuaJIT
    self.save = load(save_func_str)()
    self.commit = load(commit_func_str)()
    
    verilua "appendFinishTasks" {
        function ()
            self:clean_up()
        end
    }
end

function LuaDataBase:_log(...)
    print(f("[LuaDataBase] [%s]", self.file_name), ...)
    io.flush()
end

-- function LuaDataBase:save(...)
--     table_insert(self.cache, {...})

--     if self.save_cnt >= self.save_cnt_max then
--         self:commit()
--     else
--         self.save_cnt = self.save_cnt + 1
--     end
-- end

-- function LuaDataBase:commit()
--     if self.save_cnt == 1 then
--         return
--     end

--     -- This is used when `LightSSS` is enabled.
--     -- If the pid of each LuaDataBase instance is different, then the database will not be committed
--     if ffi.C.getpid() ~= self.pid then
--         self.save_cnt = 1
--         self.cache = {} -- enable garbage collection
--         return
--     end

--     self.db:exec("BEGIN TRANSACTION") -- Start transaction(improve db performance)
--     local stmt = assert(self.db:prepare(self.prepare_cmd), "[commit] stmt is nil")

--     for i = 1, self.save_cnt do
--         stmt:bind_values(table_unpack(self.cache[i]))
--         stmt:step()
--         stmt:reset()
--     end

--     stmt:finalize()
--     self.db:exec("COMMIT")

--     self.save_cnt = 1

--     if self.verbose then self:_log("commit!") end
-- end

function LuaDataBase:clean_up()
    local path = require "pl.path"
    printf("[LuaDataBase] [%s => %s] clean up...\n", self.fullpath_name, path.abspath(self.fullpath_name))

    self:commit()
end

return LuaDataBase

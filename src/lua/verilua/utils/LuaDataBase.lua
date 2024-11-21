local sqlite3 = require "lsqlite3"
local class = require "pl.class"
local lfs = require "lfs"
local texpect = require "TypeExpect"

local assert = assert
local ipairs = ipairs
local print = print
local printf = printf
local string = string
local type = type
local pairs = pairs
local f = string.format
local table_insert = table.insert
local table_unpack = table.unpack

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
    self.save_cnt_max = save_cnt_max
    self.save_cnt = 0
    self.cache = {}
    self.entries = {}
    self.stmt = nil
    self.verbose = verbose or false

    -- Used for type check(TypeExpect)
    self.__type = "LuaDataBase"
    self.elements = elements

    local pattern_str = ""
    for _, kv_str in pairs(elements) do
        texpect.expect_string(kv_str, "kv_str")

        local key, data_type = kv_str:match("([^%s=>]+)%s*=>%s*([^%s]+)")
        assert(data_type == "INTEGER"  or data_type == "TEXT", "[LuaDataBase] Unsupported data type: " .. data_type)

        pattern_str = pattern_str .. key .. " " .. data_type .. ",\n"
    end

    pattern_str = pattern_str:sub(1, #pattern_str - 2) -- remove trailing ",\n"

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
        printf("[LuaDataBase] Remove %s success!\n", self.fullpath_name)
    else
        printf("[LuaDataBase] Remove %s failed! => %s\n", self.fullpath_name, err_msg)
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
        print("[LuaDataBase] cmd execute success! cmd => " .. cmd)
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
    print("[LuaDataBase] file_name: " .. file_name .. " prepare_cmd: " .. self.prepare_cmd)
    io.flush()

    verilua "appendFinishTasks" {
        function ()
            self:clean_up()
        end
    }
end

function LuaDataBase:_log(...)
    print(f("[LuaDataBase] [%s]", self.file_name), ...)
end

function LuaDataBase:save(...)
    -- Notice: parametes passed into this function should hold the same order as the elements in the table
    if self.save_cnt == 0 then
        self.db:exec("BEGIN TRANSACTION") -- Start transaction(improve db performance)
        self.stmt = self.db:prepare(self.prepare_cmd)
        assert(self.stmt ~= nil)
    end

    table_insert(self.cache, {...})

    self.save_cnt = self.save_cnt + 1
    if self.save_cnt >= self.save_cnt_max then
        if self.verbose then self:_log("commit!") end
        self:commit()
    end
end

function LuaDataBase:commit()
    assert(self.stmt ~= nil)

    for i, data in ipairs(self.cache) do
        self.stmt:bind_values(table_unpack(data))
        self.stmt:step()
        self.stmt:reset()
    end

    self.stmt:finalize()

    self.db:exec("COMMIT")

    self.stmt = nil
    self.save_cnt = 0
    self.cache = {} -- enable garbage collection
end

function LuaDataBase:clean_up()
    local count = 0
    for i, data in ipairs(self.cache) do
        count = count + 1
    end

    if self.stmt ~= nil and count > 0 then
        if self.verbose then self:_log("stmt exist...") end
        self:commit()
    end

    printf("[LuaDataBase] [%s] clean up...\n", self.fullpath_name)
end

return LuaDataBase

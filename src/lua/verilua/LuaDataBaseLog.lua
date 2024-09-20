local sqlite3 = require "lsqlite3"
local class = require "pl.class"
local lfs = require "lfs"

local assert, debug_print, ipairs, print = assert, debug_print, ipairs, print
local string, format = string, string.format
local tinsert, tunpack = table.insert, table.unpack
local LuaDataBase = class()

-- local pp = require "pp"

-- 
-- Example:
--      local LuaDB = require "LuaDataBase"
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
    assert(type(init_tbl) ~= nil)
    
    local save_cnt_max = init_tbl.save_cnt_max or 10000
    local verbose = init_tbl.verbose or false
    local table_name = init_tbl.table_name
    local elements = init_tbl.elements
    local file_name = init_tbl.file_name
    local path = init_tbl.path

    assert(type(table_name) == "string")
    assert(type(elements) == "table")
    assert(type(file_name) == "string")
    assert(type(path) == "string")

    self.path = path
    self.file_name = file_name
    self.fullpath_name = path .. "/" .. file_name
    self.save_cnt_max = save_cnt_max
    self.save_cnt = 0
    self.cache = {}
    self.entries = {}
    self.stmt = nil
    self.verbose = verbose or false

    local pattern_str = ""
    local dblog_str = ""
    for _, kv_str in pairs(elements) do
        assert(type(kv_str) == "string")
        local key, data_type = kv_str:match("([^%s=>]+)%s*=>%s*([^%s]+)")
        assert(data_type == "INTEGER"  or data_type == "TEXT", "Unsupported data type: " .. data_type)
        pattern_str = pattern_str .. key .. " " .. data_type .. ",\n"
        -- dblog_str = dblog_str .. key .. "       "
        dblog_str = dblog_str .. string.format("%16s",key)
    end

    pattern_str = pattern_str:sub(1, #pattern_str - 2) -- remove trailing ",\n"

    -- 
    -- create path folder if not exist
    -- 
    local attributes, err = lfs.attributes(path .. "/")
    if attributes == nil then
        local success, message = lfs.mkdir(path .. "/")
        if not success then
            assert(false, "cannot create folder: " .. path .. " err: " .. message)
        end
    end

    -- 
    -- Remove data base before create it
    -- 
    local ret, err_msg = os.remove(self.fullpath_name)
    if ret then
        debug_print(format("Remove %s success!", self.fullpath_name))
    else
        debug_print(format("Remove %s failed! => %s", self.fullpath_name, err_msg))
    end

    -- 
    -- Open database
    -- 
    self.db, err_msg = sqlite3.open(self.fullpath_name)
    assert(self.db ~= nil, err_msg)

    local cmd = format("CREATE TABLE %s ( %s );", table_name, pattern_str)
    local result_code = self.db:exec(cmd)
    if result_code ~= sqlite3.OK then
        local err_msg = self.db:errmsg()
        assert(false, "SQLite3 error: "..err_msg)
    else
        debug_print("cmd execute success! cmd => "..cmd)
    end

    self.db = sqlite3.open(self.fullpath_name)
    assert(self.db ~= nil)

    -- 
    -- Create prepare cmd for stmt
    -- 
    self.prepare_cmd = "INSERT INTO "..table_name.." ("
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
    debug_print(file_name.." prepare_cmd: "..self.prepare_cmd)


    self.dblog_path = self.fullpath_name .. ".log"
    self.dblog = io.open(self.dblog_path,"w")
    if self.dblog then
        -- self.dblog:write("这是日志信息\n")
        -- self.dblog:close()
    else
        assert(false,"can not open dblog")
    end
    -- print("---------",unpack(elements))
    print(dblog_str)
    self.dblog:write(dblog_str.."\n")
    -- for _, _ in pairs(self.entries) do
    --     self.prepare_cmd = self.prepare_cmd .. "?" .. ","
    -- end
    -- assert(false)


    verilua "appendFinishTasks" {
        function ()
            self:clean_up()
        end
    }
end

function LuaDataBase:_log(...)
    print(format("[%s]", self.file_name), ...)
end

function LuaDataBase:_save(...)
    tinsert(self.cache, {...})
end

function LuaDataBase:save(...)
    -- Notice: parametes passed into this function should hold the same order as the elements in the table
    if self.save_cnt == 0 then
        self.db:exec("BEGIN TRANSACTION") -- Start transaction(improve db performance)
        self.stmt = self.db:prepare(self.prepare_cmd)
        assert(self.stmt ~= nil)
    end

    self:_save(...)

    -- -- dubug
    -- print("save:  ",...)
    -- for i,data in pairs(...) do
    --     print(data)
    -- end
    -- assert(false)

    self.save_cnt = self.save_cnt + 1
    if self.save_cnt >= self.save_cnt_max then
        if self.verbose then self:_log("commit!") end
        self:commit()
    end
end

function LuaDataBase:commit()
    assert(self.stmt ~= nil)

    for i, data in ipairs(self.cache) do
        -- database
        -- self.stmt:bind_values(tunpack(data))
        -- self.stmt:step()
        -- self.stmt:reset()

        -- databaselog, used for uvm
        local log_str = ""
        -- print(tunpack(data))
        for k,idata in pairs(data) do
            if #tostring(idata) > 8 then
                log_str = log_str .. string.format("%16s",idata)
            else
                log_str = log_str .. string.format("%16s",idata)
            end
        end
        self.dblog:write(log_str .. "\n")

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

    print(("[%s] clean up..."):format(self.fullpath_name))
end

return LuaDataBase

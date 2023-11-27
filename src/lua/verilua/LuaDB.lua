local sqlite3 = require("lsqlite3")
local class = require("pl.class")

LuaDB = class()

--------------------------------
-- Example
--------------------------------
-- local LuaDB = require("LuaDB")
-- test_db = LuaDB( -- Initialize you database
--     "a_table",         -- table_name
--     [[
--         val1 INTEGER,
--         val2 INTEGER,
--         val3 INTEGER,
--         others TEXT
--     ]],                -- pattern_str
--     "./db",            -- path
--     "test.db",         -- name
--     10000              -- save_cnt_max(Optional, defalut=50000)
-- )

-- test_db:save( -- Same order as your table pattern
--     1,            -- val1
--     222,          -- val2
--     3,            -- val3
--     "hello world" -- others
-- )

-- test_db:clean_up() -- Doing clean up when you terminate the whole program
-------------------------------


function LuaDB:_init(table_name, pattern_str, path, name, save_cnt_max, verbose)
    -- Sanity check
    assert(table_name ~= nil)
    assert(pattern_str ~= nil)
    assert(path ~= nil)
    assert(name ~= nil)
    
    self.name = name
    self.fullpath_name = path .. "/" .. name
    self.save_cnt_max = save_cnt_max or 50000
    self.save_cnt = 0
    self.cache = {}
    self.entries = {}
    self.stmt = nil
    self.verbose = verbose or false
    
    -- Remove data base before create it
    local ret, err_msg = os.remove(self.fullpath_name)
    if ret then
        print(string.format("Remove %s success!", self.fullpath_name))
    else
        print(string.format("Remove %s failed! => %s", self.fullpath_name, err_msg))
    end

    -- Open database
    self.db = sqlite3.open(self.fullpath_name)
    assert(self.db ~= nil)

    local cmd = string.format("CREATE TABLE %s ( %s );", table_name, pattern_str)
    -- print(cmd)

    self.db:exec(cmd)
    self.db = sqlite3.open(self.fullpath_name)
    assert(self.db ~= nil)


    -- Create prepare cmd for stmt
    self.prepare_cmd = "INSERT INTO "..table_name.." ("
    for key, value in string.gmatch(pattern_str, '([%w_]+)%s+(%w+)') do
        self.entries[key] = value
        self.prepare_cmd = self.prepare_cmd .. key .. ","
        -- print(key, value, #self.entries)
    end
    self.prepare_cmd = string.sub(self.prepare_cmd, 1, -2) -- recude ","
    self.prepare_cmd = self.prepare_cmd .. ") " .. "VALUES ("
    for _ in pairs(self.entries) do
        self.prepare_cmd = self.prepare_cmd .. "?" .. ","
    end
    self.prepare_cmd = string.sub(self.prepare_cmd, 1, -2) -- recude ","
    self.prepare_cmd = self.prepare_cmd .. ")"
    print(name.." prepare_cmd: "..self.prepare_cmd)
end

function LuaDB:_log(...)
    print(string.format("[%s]", self.name), ...)
end

function LuaDB:_save(...)
    table.insert(self.cache, {...})
end

function LuaDB:save(...)
    if self.save_cnt == 0 then
        self.db:exec("BEGIN TRANSACTION") -- Start transaction(improve db performance)
        self.stmt = self.db:prepare(self.prepare_cmd)
        assert(self.stmt ~= nil)
    end

    self:_save(...)

    self.save_cnt = self.save_cnt + 1
    if self.save_cnt >= self.save_cnt_max then
        if self.verbose == true then print(self.name, "commit!") end
        self:commit()
    end
end

function LuaDB:commit()
    assert(self.stmt ~= nil)

    for _, data in ipairs(self.cache) do
        self.stmt:bind_values(table.unpack(data))
        self.stmt:step()
        self.stmt:reset()
    end

    self.stmt:finalize()

    self.db:exec("COMMIT")

    self.stmt = nil
    self.save_cnt = 0
    self.cache = {} -- enable garbage collection
end

function LuaDB:clean_up()
    local count = 0
    for _ in pairs(self.cache) do
        count = count + 1
    end

    if self.stmt ~= nil and count > 0 then
        local _ = self.verbose and self:_log("stmt exist...")
        self:commit()
    end

    local _ = self.verbose and self:_log("Doing clean up...")
end

return LuaDB

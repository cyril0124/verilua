local lester = require "lester"
local texpect = require "verilua.TypeExpect"

local describe, it, expect = lester.describe, lester.it, lester.expect

-- Mocking some objects for testing
local function mock_chdl(width)
    local chdl = {
        __type = "CallableHDL",
        get_width = function() return width end,
        fullpath = "top.sig",
        hdl = {} -- dummy hdl handle
    }
    ---@cast chdl verilua.handles.CallableHDL
    return chdl
end

local function mock_bdl()
    local bdl = { __type = "Bundle" }
    ---@cast bdl verilua.handles.Bundle
    return bdl
end

local function mock_abdl(signals)
    local abdl = { __type = "AliasBundle" }
    for name, sig in pairs(signals) do
        abdl[name] = sig
    end
    ---@cast abdl verilua.handles.AliasBundle
    return abdl
end

local function mock_db(elements)
    local db = {
        __type = "LuaDataBase",
        elements = elements
    }
    ---@cast db verilua.utils.LuaDataBase
    return db
end

local function mock_cg()
    return { __type = "CoverGroup" }
end

local function strip_ansi(s)
    return s:gsub("\27%[[0-9;]*m", "")
end

describe("TypeExpect test", function()
    it("should work for expect_string", function()
        texpect.expect_string("hello", "var1")
        local status, err = pcall(function() texpect.expect_string(123, "var1") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_string", 1, true))
        expect.truthy(err:find("Expected: string", 1, true))
        expect.truthy(err:find("Received: number", 1, true))
        expect.truthy(err:find("stack traceback:", 1, true))
    end)

    it("should work for expect_number", function()
        texpect.expect_number(123, "var2")
        local status, err = pcall(function() texpect.expect_number("123", "var2") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_number", 1, true))
    end)

    it("should work for expect_integer", function()
        texpect.expect_integer(123, "var_int")
        local status, err = pcall(function() texpect.expect_integer("123", "var_int") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_integer", 1, true))

        -- Test LuaJIT LL and ULL support
        local ffi = require "ffi"
        local ll_value = 123LL
        local ull_value = 456ULL
        texpect.expect_integer(ll_value, "var_ll")
        texpect.expect_integer(ull_value, "var_ull")

        -- Test that invalid cdata types are rejected
        local invalid_cdata = ffi.new("struct { int x; }")
        status, err = pcall(function() texpect.expect_integer(invalid_cdata, "var_invalid") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_integer", 1, true))
    end)

    it("should work for expect_boolean", function()
        texpect.expect_boolean(true, "var3")
        local status, err = pcall(function() texpect.expect_boolean(1, "var3") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_boolean", 1, true))
    end)

    it("should work for expect_table", function()
        texpect.expect_table({}, "var_table")
        local status, err = pcall(function() texpect.expect_table(1, "var_table") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_table", 1, true))

        -- Test with table_keys whitelist - valid case
        texpect.expect_table({ a = 1, b = 2 }, "valid_table", { "a", "b" })

        -- Test with table_keys whitelist - empty table
        texpect.expect_table({}, "empty_table", { "a", "b" })

        -- Test with table_keys whitelist - single invalid key
        status, err = pcall(function()
            texpect.expect_table({ a = 1, b = 2, c = 3 }, "invalid_table", { "a", "b" })
        end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("unexpected keys", 1, true))
        expect.truthy(err:find("c", 1, true))

        -- Test with table_keys whitelist - multiple invalid keys
        status, err = pcall(function()
            texpect.expect_table({ a = 1, x = 2, y = 3, z = 4 }, "multi_invalid_table", { "a", "b" })
        end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("unexpected keys", 1, true))
        expect.truthy(err:find("x", 1, true))
        expect.truthy(err:find("y", 1, true))
        expect.truthy(err:find("z", 1, true))
    end)

    it("should work for expect_function", function()
        texpect.expect_function(function() end, "var_func")
        local status, err = pcall(function() texpect.expect_function(1, "var_func") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_function", 1, true))
    end)

    it("should work for expect_thread", function()
        local co = coroutine.create(function() end)
        texpect.expect_thread(co, "var_thread")
        local status, err = pcall(function() texpect.expect_thread(1, "var_thread") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_thread", 1, true))
    end)

    it("should work for expect_userdata", function()
        -- In LuaJIT, we can get a userdata via io.stdout or similar
        texpect.expect_userdata(io.stdout, "var_userdata")
        local status, err = pcall(function() texpect.expect_userdata(1, "var_userdata") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_userdata", 1, true))
    end)

    it("should work for expect_struct", function()
        local ffi = require "ffi"
        local struct = ffi.new("struct { int x; }")
        texpect.expect_struct(struct, "var_struct")
        local status, err = pcall(function() texpect.expect_struct(1, "var_struct") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_struct", 1, true))
    end)

    it("should work for expect_chdl", function()
        local chdl = mock_chdl(32)
        texpect.expect_chdl(chdl, "my_chdl")
        texpect.expect_chdl(chdl, "my_chdl", 32)
        texpect.expect_chdl(chdl, "my_chdl", 16, 64)

        local status, err = pcall(function() texpect.expect_chdl({}, "my_chdl") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_chdl", 1, true))

        status, err = pcall(function() texpect.expect_chdl(chdl, "my_chdl", 16) end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("width 16", 1, true))

        status, err = pcall(function() texpect.expect_chdl(chdl, "my_chdl", 64, 128) end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("width in [64, 128]", 1, true))
    end)

    it("should work for expect_bdl", function()
        local bdl = mock_bdl()
        texpect.expect_bdl(bdl, "my_bdl")
        local status, err = pcall(function() texpect.expect_bdl({}, "my_bdl") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_bdl", 1, true))
    end)

    it("should work for expect_abdl", function()
        local sig1 = mock_chdl(10)
        local sig2 = mock_chdl(32)
        local abdl = mock_abdl({ s1 = sig1, s2 = sig2, s1_alias = sig1 })

        -- Basic usage
        texpect.expect_abdl(abdl, "my_abdl", {
            { name = "s1", width = 10 },
            { name = "s2", width_min = 16, width_max = 64 },
            "s1"
        })

        -- Test names (aliases)
        texpect.expect_abdl(abdl, "my_abdl", {
            { names = { "s1", "s1_alias" }, width = 10 }
        })

        -- Test width_min only
        texpect.expect_abdl(abdl, "my_abdl", {
            { name = "s1", width_min = 5 }
        })

        -- Test width_max only
        texpect.expect_abdl(abdl, "my_abdl", {
            { name = "s1", width_max = 15 }
        })

        -- Error: width mismatch
        local status, err = pcall(function()
            texpect.expect_abdl(abdl, "my_abdl", { { name = "s1", width = 32 } })
        end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("width is 10, but expected 32", 1, true))

        -- Error: names but different signals
        local status, err = pcall(function()
            texpect.expect_abdl(abdl, "my_abdl", {
                { names = { "s1", "s2" } }
            })
        end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("are not the same signal", 1, true))

        -- Error: invalid params item
        local status, err = pcall(function()
            texpect.expect_abdl(abdl, "my_abdl", { 123 })
        end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("must be a `table` or a `string`"))

        -- Error: params item missing name/names
        local status, err = pcall(function()
            texpect.expect_abdl(abdl, "my_abdl", { {} })
        end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("must have `name` or `names` field"))
    end)

    it("should work for expect_database", function()
        local db = mock_db({ "col1 TEXT", "col2 INTEGER" })
        texpect.expect_database(db, "my_db", { "col1 TEXT", "col2 INTEGER" })

        -- Test duckdb mapping
        local duckdb = mock_db({ "col1 VARCHAR", "col2 BIGINT" })
        duckdb.backend = "duckdb"
        texpect.expect_database(duckdb, "my_duckdb", { "col1 TEXT", "col2 INTEGER" })

        local status, err = pcall(function()
            texpect.expect_database(db, "my_db", { "col1 TEXT" })
        end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("elements_table is not equal", 1, true))
    end)

    it("should work for expect_covergroup", function()
        local cg = mock_cg()
        texpect.expect_covergroup(cg, "my_cg")
        local status, err = pcall(function() texpect.expect_covergroup({}, "my_cg") end)
        expect.equal(status, false)
        err = strip_ansi(err)
        expect.truthy(err:find("expect_covergroup", 1, true))
    end)
end)

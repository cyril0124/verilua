---@diagnostic disable: unnecessary-assert, unresolved-require

local lester = require "lester"
local path = require "pl.path"
local file = require "pl.file"
local dir = require "pl.dir"

local describe, it, expect = lester.describe, lester.it, lester.expect

lester.parse_args()

local bundle_to_bc = require("verilua.utils.BundleToVlbc").bundle_to_bc

---@type string[]
local roots = {}

local function make_root()
    local tmp = os.tmpname()
    os.remove(tmp)
    local root = tmp .. "_btb"
    dir.makepath(root)
    roots[#roots + 1] = root
    return root
end

---@param root string
---@param rel string
---@param src string
local function write_mod(root, rel, src)
    local full = path.join(root, rel)
    dir.makepath(path.dirname(full))
    assert(file.write(full, src))
end

---@param names string[]
local function unload(names)
    for i = 1, #names do
        local name = names[i]
        package.loaded[name] = nil
        package.preload[name] = nil
    end
end

lester.after(function()
    for i = 1, #roots do
        local root = roots[i]
        if path.isdir(root) then
            dir.rmtree(root)
        end
    end
    roots = {}
end)

describe("BundleToVlbc.bundle_to_bc", function()
    it("bundles recursive require and runs after sources are deleted", function()
        local root = make_root()
        write_mod(root, "btb_rec/util.lua", [[
return { tag = "util" }
]])
        write_mod(root, "btb_rec/inner.lua", [[
local util = require("btb_rec.util")
return {
    ping = function()
        return "pong-" .. util.tag
    end,
}
]])
        write_mod(root, "btb_rec/agent.lua", [[
local inner = require("btb_rec.inner")
local M = {}
function M.go()
    return inner.ping()
end
return M
]])

        local search = path.join(root, "?.lua")
        local bc = bundle_to_bc("btb_rec.agent", { path = search })
        dir.rmtree(root)

        unload({ "btb_rec.agent", "btb_rec.inner", "btb_rec.util" })
        local agent = assert(load(bc))()
        expect.equal(agent.go(), "pong-util")
        unload({ "btb_rec.agent", "btb_rec.inner", "btb_rec.util" })
    end)

    it("does not bundle verilua / pl / stdlib by default", function()
        local root = make_root()
        write_mod(root, "btb_skip.lua", [[
local inspect = require("inspect")
local utils = require("verilua.LuaUtils")
local path = require("pl.path")
return {
    inspect_type = type(inspect),
    has_to_hex = type(utils.to_hex_str) == "function",
    path_type = type(path),
}
]])

        local bc = bundle_to_bc("btb_skip", { path = path.join(root, "?.lua") })
        dir.rmtree(root)

        unload({ "btb_skip" })
        local m = assert(load(bc))()
        expect.equal(m.inspect_type, "table")
        expect.equal(m.has_to_hex, true)
        expect.equal(m.path_type, "table")
        expect.equal(package.preload["inspect"] == nil, true)
        expect.equal(package.preload["verilua.LuaUtils"] == nil, true)
        expect.equal(package.preload["pl.path"] == nil, true)
        unload({ "btb_skip" })
    end)

    it("handles cyclic require without looping", function()
        local root = make_root()
        write_mod(root, "btb_cyc/a.lua", [[
local M = { name = "a" }
function M.other()
    return require("btb_cyc.b").name
end
return M
]])
        write_mod(root, "btb_cyc/b.lua", [[
local a = require("btb_cyc.a")
return { name = "b", from_a = a.name }
]])

        local bc = bundle_to_bc("btb_cyc.a", { path = path.join(root, "?.lua") })
        dir.rmtree(root)

        unload({ "btb_cyc.a", "btb_cyc.b" })
        local a = assert(load(bc))()
        expect.equal(a.name, "a")
        expect.equal(a.other(), "b")
        unload({ "btb_cyc.a", "btb_cyc.b" })
    end)

    it("errors at bundle time when a required module is missing", function()
        local root = make_root()
        write_mod(root, "btb_miss.lua", [[
return require("btb_miss_child")
]])

        local ok, err = pcall(bundle_to_bc, "btb_miss", { path = path.join(root, "?.lua") })
        expect.equal(ok, false)
        assert(tostring(err):find("btb_miss_child", 1, true))
    end)

    it("honors opts.skip and leaves that module to runtime require", function()
        local root = make_root()
        write_mod(root, "btb_opt/keep.lua", [[
return { v = 7 }
]])
        write_mod(root, "btb_opt/agent.lua", [[
local keep = require("btb_opt.keep")
return { v = keep.v }
]])

        local search = path.join(root, "?.lua")
        local bc = bundle_to_bc("btb_opt.agent", {
            path = search,
            skip = { ["btb_opt.keep"] = true },
        })

        file.delete(path.join(root, "btb_opt/agent.lua"))
        unload({ "btb_opt.agent", "btb_opt.keep" })
        local old_path = package.path
        package.path = search .. ";" .. package.path
        local ok, m = pcall(function()
            return assert(load(bc))()
        end)
        package.path = old_path
        assert(ok, m)
        expect.equal(m.v, 7)
        expect.equal(package.preload["btb_opt.keep"] == nil, true)
        unload({ "btb_opt.agent", "btb_opt.keep" })
    end)

    it("honors opts.path instead of package.path", function()
        local root = make_root()
        write_mod(root, "btb_path.lua", "return { ok = true }\n")

        local ok, err = pcall(bundle_to_bc, "btb_path")
        expect.equal(ok, false)
        assert(tostring(err):find("btb_path", 1, true))

        local bc = bundle_to_bc("btb_path", { path = path.join(root, "?.lua") })
        dir.rmtree(root)
        unload({ "btb_path" })
        local m = assert(load(bc))()
        expect.equal(m.ok, true)
        unload({ "btb_path" })
    end)

    it("ignores require() names that only appear in comments", function()
        local root = make_root()
        write_mod(root, "btb_cmt.lua", [=[
-- require("btb_cmt_secret")
--[[ require("btb_cmt_hidden") ]]
return { ok = true }
]=])

        local bc = bundle_to_bc("btb_cmt", { path = path.join(root, "?.lua") })
        dir.rmtree(root)
        unload({ "btb_cmt" })
        local m = assert(load(bc))()
        expect.equal(m.ok, true)
        unload({ "btb_cmt" })
    end)

    it("skips native modules found only on package.cpath", function()
        local root = make_root()
        write_mod(root, "btb_native.lua", [[
require("btb_only_so")
return { ok = true }
]])
        local so_dir = path.join(root, "c")
        dir.makepath(so_dir)
        assert(file.write(path.join(so_dir, "btb_only_so.so"), "not a real so"))

        local old_cpath = package.cpath
        package.cpath = path.join(so_dir, "?.so")
        local ok, bc_or_err = pcall(bundle_to_bc, "btb_native", { path = path.join(root, "?.lua") })
        package.cpath = old_cpath
        expect.equal(ok, true)
        assert(ok)

        dir.rmtree(root)
        unload({ "btb_native", "btb_only_so" })
        -- The bundled chunk should not try to load the dummy .so at require time.
        -- require("btb_only_so") stays as a runtime call; we only assert bundle succeeded
        -- and the dummy name is not installed as preload.
        local chunk = assert(load(bc_or_err))
        package.preload["btb_only_so"] = function()
            return true
        end
        local m = chunk()
        expect.equal(m.ok, true)
        unload({ "btb_native", "btb_only_so" })
    end)

    it("shares one instance when two bundles require the same module", function()
        local root = make_root()
        write_mod(root, "btb_share/common.lua", [[
local M = { n = 0 }
function M.inc()
    M.n = M.n + 1
    return M.n
end
return M
]])
        write_mod(root, "btb_share/agent.lua", [[
local common = require("btb_share.common")
return {
    inc = function() return common.inc() end,
    get = function() return common.n end,
}
]])
        write_mod(root, "btb_share/monitor.lua", [[
local common = require("btb_share.common")
return {
    inc = function() return common.inc() end,
    get = function() return common.n end,
}
]])

        local search = path.join(root, "?.lua")
        local bc_agent = bundle_to_bc("btb_share.agent", { path = search })
        local bc_mon = bundle_to_bc("btb_share.monitor", { path = search })
        dir.rmtree(root)

        local names = { "btb_share.agent", "btb_share.monitor", "btb_share.common" }
        unload(names)
        local agent = assert(load(bc_agent))()
        local mon = assert(load(bc_mon))()
        expect.equal(agent.inc(), 1)
        expect.equal(mon.inc(), 2)
        expect.equal(agent.get(), 2)
        expect.equal(mon.get(), 2)
        expect.equal(agent.inc(), 3)
        expect.equal(mon.get(), 3)
        expect.equal(mon.inc(), 4)
        expect.equal(agent.get(), 4)
        unload(names)
    end)
end)

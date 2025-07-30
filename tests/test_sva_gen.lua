---@diagnostic disable: invisible

local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect

local ctx = require "SVAContext"

lester.parse_args()

describe("SVAContext test", function()
    it("can add cover/assert", function()
        local ret = ctx:add "cover" {
            name = "test",
            expr = "test + $(a) + $(bb)",
            envs = { a = 123, bb = 456 }
        }
        expect.equal(ret, nil)
        expect.equal(tostring(ctx), [[
// 1/1
test: cover property (test + 123 + 456);

]])

        -- Clean context
        ctx:clean()
        expect.equal(tostring(ctx), "")

        -- `cat` is a helper function to concatenate multiple tables
        ret = ctx:add "cover" {
            name = "test1",
            expr = "test1 + $(a) + $(bb)",
            envs = cat({ a = 123 }) + cat({ bb = 456 })
        }
        expect.equal(ret, nil)
        -- SVAContext:generate() is equal to tostring(SVAContext)
        expect.equal(ctx:generate(), [[
// 1/1
test1: cover property (test1 + 123 + 456);

]])

        -- `cat` is not available outside of `SVAContext:add`
        expect.equal(cat, nil)

        -- Clean context
        ctx:clean()
        expect.equal(tostring(ctx), "")

        ret = ctx:add "assert" {
            name = "test2",
            expr = "test2 + $(a) + $(bb) + $(c)",
            envs = { a = 123, bb = "456", c = true }
        }
        expect.equal(ret, nil)
        expect.equal(tostring(ctx), [[
// 1/1
test2: assert property (test2 + 123 + 456 + true);

]])

        -- Clean context
        ctx:clean()
        expect.equal(tostring(ctx), "")
    end)

    it("can change cover type", function()
        ctx:add "cover" {
            name = "test",
            cov_type = "sequence", -- It is `property` by default
            expr = "test + $(a) + $(bb)",
            envs = { a = 123, bb = 456 }
        }
        expect.equal(tostring(ctx), [[
// 1/1
test: cover sequence (test + 123 + 456);

]])

        ctx:clean()
    end)

    it("has SVAContext:with_global_envs", function()
        ctx:with_global_envs { a = 123, bb = 456 }

        local ret = ctx:add "cover" {
            name = "test",
            expr = "test + $(a) + $(bb)",
        }
        expect.equal(ret, nil)
        expect.equal(tostring(ctx), [[
// 1/1
test: cover property (test + 123 + 456);

]])

        ret = ctx:add "cover" {
            name = "test1",
            expr = "test1 + $(a) + $(bb)",
        }
        expect.equal(ret, nil)
        expect.equal(tostring(ctx), [[
// 1/2
test: cover property (test + 123 + 456);

// 2/2
test1: cover property (test1 + 123 + 456);

]])

        ctx:clean()
    end)

    it("can add sequence/property", function()
        local ret = ctx:add "sequence" {
            name = "test",
            expr = "test + $(a) + $(bb)",
            envs = { a = 123, bb = 456 }
        }
        ---@cast ret SVAContext.sequence
        expect.equal(ret.__type, "Sequence")
        expect.equal(ret.name, "test")
        expect.equal(tostring(ctx), [[
sequence test() test + 123 + 456; endsequence

]])

        local ret1 = ctx:add "property" {
            name = "test1",
            expr = "test + $(a) + $(bb)",
            envs = { a = 123, bb = 456 }
        }
        ---@cast ret1 SVAContext.property
        expect.equal(ret1.__type, "Property")
        expect.equal(ret1.name, "test1")
        expect.equal(tostring(ctx), [[
sequence test() test + 123 + 456; endsequence

property test1() test + 123 + 456; endproperty

]])

        -- Sequence and Property will automatically add to global envs
        expect.equal(ctx.global_envs.test, ret)
        expect.equal(ctx.global_envs.test1, ret1)
        ctx:add("cover")({
            name = "test2",
            expr = "test2 + $(test) + $(test1)",
        })
        expect.equal(tostring(ctx), [[
sequence test() test + 123 + 456; endsequence

property test1() test + 123 + 456; endproperty

// 1/1
test2: cover property (test2 + test + test1);

]])

        -- Clean context
        ctx:clean()
        expect.equal(tostring(ctx), "")
    end)

    it("work with CallableHDL", function()
        local make_fake_chdl = function(fullpath)
            return {
                __type = "CallableHDL",
                fullpath = fullpath
            }
        end

        local c1 = make_fake_chdl("path.to.c1")
        local c2 = make_fake_chdl("path.to.c2")
        ctx:add "cover" {
            name = "test",
            expr = "test + $(c1) + $(c2)",
            envs = { c1 = c1, c2 = c2 }
        }
        expect.equal(tostring(ctx), [[
// 1/1
test: cover property (test + path.to.c1 + path.to.c2);

]])

        ctx:clean()
    end)

    it("work with ProxyTableHandle", function()
        local make_fake_pt = function(fullpath)
            return {
                __type = "ProxyTableHandle",
                chdl = function(t)
                    return {
                        __type = "CallableHDL",
                        fullpath = fullpath
                    }
                end
            }
        end

        local c1 = make_fake_pt("path.to.c1")
        local c2 = make_fake_pt("path.to.c2")
        ctx:add "cover" {
            name = "test",
            expr = "test + $(c1) + $(c2)",
            envs = { c1 = c1, c2 = c2 }
        }
        expect.equal(tostring(ctx), [[
// 1/1
test: cover property (test + path.to.c1 + path.to.c2);

]])

        ctx:clean()
    end)

    it("has a built-in template engine", function()
        ctx:add "cover" {
            name = "test",
            -- lines starting with # are Lua
            expr = [[
# for i = 1, 3 do
    $(i)
# end
]]
        }
        expect.equal(tostring(ctx), [[
// 1/1
test: cover property (    1
    2
    3
);

]])
        ctx:clean()

        -- Change `Lua` code identifier
        ctx:add "cover" {
            name = "test",
            -- lines starting with # are Lua
            expr = [[
% for i = 1, 3 do
%   if i == 2 then
    $(i)
%   end
% end
]],
            envs = { _escape = "%" }
        }
        expect.equal(tostring(ctx), [[
// 1/1
test: cover property (    2
);

]])

        ctx:clean()
    end)

    it("can handle table recursively", function()
        ctx:add "cover" {
            name = "test",
            expr = "$(a.b) $(a.c) $(a.d.e) $(a.d.f)",
            envs = {
                a = {
                    b = 123,
                    c = 456,
                    d = {
                        e = 789,
                        f = {
                            __type = "CallableHDL",
                            fullpath = "path.to.f"
                        }
                    }
                }
            }
        }
        expect.equal(tostring(ctx), [[
// 1/1
test: cover property (123 456 789 path.to.f);

]])
    end)
end)

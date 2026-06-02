---@diagnostic disable: invisible, access-invisible, assign-type-mismatch

local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect

local ctx = require "verilua.sva.SVAContext"

-- Disable lint for most tests since they use synthetic/fake data (bare
-- identifiers like `test`, `123`) that would trigger undeclared-identifier
-- errors in slang. Lint-specific tests re-enable it explicitly.
ctx:set_lint(false)

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
property _GEN_test_PROPERTY(); test + 123 + 456; endproperty
test: cover property (_GEN_test_PROPERTY);

]])

        -- Clean context
        ctx:clean()
        expect.equal(tostring(ctx), "")

        -- envs is a plain table
        ret = ctx:add "cover" {
            name = "test1",
            expr = "test1 + $(a) + $(bb)",
            envs = { a = 123, bb = 456 }
        }
        expect.equal(ret, nil)
        -- SVAContext:generate() is equal to tostring(SVAContext)
        expect.equal(ctx:generate(), [[
// 1/1
property _GEN_test1_PROPERTY(); test1 + 123 + 456; endproperty
test1: cover property (_GEN_test1_PROPERTY);

]])

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
property _GEN_test2_PROPERTY(); test2 + 123 + 456 + true; endproperty
test2: assert property (_GEN_test2_PROPERTY);

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
sequence _GEN_test_SEQUENCE(); test + 123 + 456; endsequence
test: cover sequence (_GEN_test_SEQUENCE);

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
property _GEN_test_PROPERTY(); test + 123 + 456; endproperty
test: cover property (_GEN_test_PROPERTY);

]])

        ret = ctx:add "cover" {
            name = "test1",
            expr = "test1 + $(a) + $(bb)",
        }
        expect.equal(ret, nil)
        expect.equal(tostring(ctx), [[
// 1/2
property _GEN_test_PROPERTY(); test + 123 + 456; endproperty
test: cover property (_GEN_test_PROPERTY);

// 2/2
property _GEN_test1_PROPERTY(); test1 + 123 + 456; endproperty
test1: cover property (_GEN_test1_PROPERTY);

]])

        ctx:clean()
    end)

    it("can add sequence/property", function()
        local ret = ctx:add "sequence" {
            name = "test",
            expr = "test + $(a) + $(bb)",
            envs = { a = 123, bb = 456 }
        }
        ---@cast ret verilua.sva.SVAContext.sequence
        expect.equal(ret.__type, "Sequence")
        expect.equal(ret.name, "test")
        expect.equal(tostring(ctx), [[
sequence test(); test + 123 + 456; endsequence

]])

        local ret1 = ctx:add "property" {
            name = "test1",
            expr = "test + $(a) + $(bb)",
            envs = { a = 123, bb = 456 }
        }
        ---@cast ret1 verilua.sva.SVAContext.property
        expect.equal(ret1.__type, "Property")
        expect.equal(ret1.name, "test1")
        expect.equal(tostring(ctx), [[
sequence test(); test + 123 + 456; endsequence

property test1(); test + 123 + 456; endproperty

]])

        -- Sequence and Property are reachable only through the seq:/prop:
        -- namespaces, never as a flat env name.
        expect.equal(ctx.seq_envs.test, ret)
        expect.equal(ctx.prop_envs.test1, ret1)
        expect.equal(ctx.global_envs.test, nil)
        expect.equal(ctx.global_envs.test1, nil)
        ctx:add("cover")({
            name = "test2",
            expr = "test2 + $(seq:test) + $(prop:test1)",
        })
        expect.equal(tostring(ctx), [[
sequence test(); test + 123 + 456; endsequence

property test1(); test + 123 + 456; endproperty

// 1/1
property _GEN_test2_PROPERTY(); test2 + test + test1; endproperty
test2: cover property (_GEN_test2_PROPERTY);

]])

        -- Clean context
        ctx:clean()
        expect.equal(tostring(ctx), "")
    end)

    it("can reference sequence/property via seq:/prop: namespace", function()
        ctx:add "sequence" {
            name = "handshake",
            expr = "req ##1 ack",
        }
        ctx:add "property" {
            name = "no_overflow",
            expr = "!ovf",
        }

        -- `$(seq:name)` / `$(prop:name)` are the only way to reference
        -- previously added sequences and properties.
        ctx:add "assert" {
            name = "chk",
            expr = "$(seq:handshake) |-> $(prop:no_overflow)",
        }
        expect.equal(tostring(ctx), [[
sequence handshake(); req ##1 ack; endsequence

property no_overflow(); !ovf; endproperty

// 1/1
property _GEN_chk_PROPERTY(); handshake |-> no_overflow; endproperty
chk: assert property (_GEN_chk_PROPERTY);

]])

        ctx:clean()
    end)

    it("requires seq:/prop: prefix to reference sequence/property", function()
        ctx:add "sequence" { name = "handshake", expr = "req ##1 ack" }
        ctx:add "property" { name = "no_overflow", expr = "!ovf" }

        -- A bare `$(handshake)` no longer resolves to the sequence; it fails
        -- with a hint pointing at the required `seq:` prefix.
        local ok, err = pcall(function()
            ctx:add "assert" { name = "bad_seq", expr = "x |-> $(handshake)" }
        end)
        expect.equal(ok, false)
        local err_str = tostring(err)
        assert(
            err_str:find(
                "[SVAContext] cannot reference sequence `handshake` as a flat `$(handshake)`; use the `seq:` prefix, e.g. `$(seq:handshake)`",
                1, true
            ),
            "expected seq prefix hint in error, got: " .. err_str
        )

        -- Same for a flat reference to a property.
        ok, err = pcall(function()
            ctx:add "assert" { name = "bad_prop", expr = "$(no_overflow)" }
        end)
        expect.equal(ok, false)
        err_str = tostring(err)
        assert(
            err_str:find(
                "[SVAContext] cannot reference property `no_overflow` as a flat `$(no_overflow)`; use the `prop:` prefix, e.g. `$(prop:no_overflow)`",
                1, true
            ),
            "expected prop prefix hint in error, got: " .. err_str
        )

        -- A real env that happens to share the name still wins over the hint.
        ctx:add "cover" { name = "ok", expr = "$(handshake)", envs = { handshake = "REAL" } }
        expect.truthy(tostring(ctx):find("REAL", 1, true))

        ctx:clean()
    end)

    it("rewrites seq:/prop: under custom escape and brackets", function()
        ctx:add "sequence" {
            name = "hs2",
            expr = "a ##1 b",
        }
        ctx:add "cover" {
            name = "cov2",
            expr = "@{seq:hs2}",
            envs = { _inline_escape = "@", _brackets = "{}" },
        }
        expect.equal(tostring(ctx), [[
sequence hs2(); a ##1 b; endsequence

// 1/1
property _GEN_cov2_PROPERTY(); hs2; endproperty
cov2: cover property (_GEN_cov2_PROPERTY);

]])

        ctx:clean()
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
property _GEN_test_PROPERTY(); test + path.to.c1 + path.to.c2; endproperty
test: cover property (_GEN_test_PROPERTY);

]])

        ctx:clean()
    end)

    it("work with ProxyTableHandle", function()
        local make_fake_pt = function(fullpath)
            return {
                __type = "ProxyTableHandle",
                chdl = function(_t)
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
property _GEN_test_PROPERTY(); test + path.to.c1 + path.to.c2; endproperty
test: cover property (_GEN_test_PROPERTY);

]])

        ctx:clean()
    end)

    it("has a built-in template engine", function()
        ctx:add "cover" {
            name = "test",
            -- lines starting with # are Lua code
            expr = [[
# for i = 1, 3 do
    $(i)
# end
]]
        }
        expect.equal(tostring(ctx), [[
// 1/1
property _GEN_test_PROPERTY(); 1 2 3; endproperty
test: cover property (_GEN_test_PROPERTY);

]])
        ctx:clean()

        -- Change `Lua` coded identifier
        ctx:add "cover" {
            name = "test",
            -- lines starting with % are Lua code
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
property _GEN_test_PROPERTY(); 2; endproperty
test: cover property (_GEN_test_PROPERTY);

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
property _GEN_test_PROPERTY(); 123 456 789 path.to.f; endproperty
test: cover property (_GEN_test_PROPERTY);

]])

        ctx:clean()
    end)

    it("can add default clocking", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "path.to.clock",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")
        expect.equal(tostring(ctx), [[
default clocking @(posedge path.to.clock); endclocking

]])

        ctx:clean()

        local clock_dut_signal = {
            __type = "ProxyTableHandle",
            chdl = function(_t)
                return clock_signal
            end
        }
        ---@cast clock_dut_signal verilua.handles.ProxyTableHandle
        ctx:default_clocking(clock_dut_signal, "negedge")
        expect.equal(tostring(ctx), [[
default clocking @(negedge path.to.clock); endclocking

]])

        local ok = pcall(function()
            ctx:default_clocking(clock_dut_signal, "posedge")
        end)
        assert(not ok)

        ok = pcall(function()
            ctx:default_clocking(clock_dut_signal, "posedge", true)
        end)
        assert(ok)

        ctx:clean()
    end)

    it("sv_lint catches syntax errors", function()
        ctx:set_lint(true)

        -- Valid SVA with XMR paths passes lint
        local ok, err = pcall(function()
            ctx:add "sequence" { name = "s_ok", expr = "top.dut.req ##1 top.dut.ack" }
        end)
        expect.equal(ok, true)
        ctx:clean()

        -- Syntax error: missing semicolons / malformed expression
        ok, err = pcall(function()
            ctx:add "sequence" { name = "s_bad", expr = "top.dut.req ##" }
        end)
        expect.equal(ok, false)
        local err_str = tostring(err)
        assert(
            err_str:find("[SVAContext] lint error in 's_bad'", 1, true),
            "expected lint error for s_bad, got: " .. err_str
        )
        ctx:clean()

        ctx:set_lint(false)
    end)

    it("sv_lint catches semantic errors", function()
        ctx:set_lint(true)

        -- Semantic error: range reversed ##[5:2]
        local ok, err = pcall(function()
            ctx:add "sequence" { name = "s_range", expr = "top.dut.a ##[5:2] top.dut.b" }
        end)
        expect.equal(ok, false)
        local err_str = tostring(err)
        assert(
            err_str:find("[SVAContext] lint error in 's_range'", 1, true),
            "expected lint error for s_range, got: " .. err_str
        )
        assert(
            err_str:find("sequence range minimum", 1, true),
            "expected 'sequence range minimum' in error, got: " .. err_str
        )
        ctx:clean()

        ctx:set_lint(false)
    end)

    it("sv_lint respects set_lint(false)", function()
        ctx:set_lint(false)

        -- This would fail lint (bare identifier) but lint is off
        local ok = pcall(function()
            ctx:add "sequence" { name = "s_nolint", expr = "bare_signal ##1 another" }
        end)
        expect.equal(ok, true)

        ctx:clean()
    end)

    it("sv_lint validates cross-statement references", function()
        ctx:set_lint(true)

        -- Define a sequence, then reference it in a property
        ctx:add "sequence" { name = "hs", expr = "top.dut.req ##1 top.dut.ack" }
        local ok, err = pcall(function()
            ctx:add "assert" { name = "chk", expr = "$(seq:hs) |-> top.dut.valid" }
        end)
        expect.equal(ok, true)
        ctx:clean()

        -- Reference a non-existent sequence -> undeclared identifier
        ok, err = pcall(function()
            ctx:add "assert" { name = "chk2", expr = "nonexist_seq |-> top.dut.valid" }
        end)
        expect.equal(ok, false)
        local err_str = tostring(err)
        assert(
            err_str:find("[SVAContext] lint error in 'chk2'", 1, true),
            "expected lint error for chk2, got: " .. err_str
        )
        ctx:clean()

        ctx:set_lint(false)
    end)
end)

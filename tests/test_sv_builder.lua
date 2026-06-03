---@diagnostic disable: invisible, access-invisible, assign-type-mismatch

local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect

local ctx = require "verilua.sv.SVBuilder"

-- Disable lint for most tests since they use synthetic/fake data (bare
-- identifiers like `test`, `123`) that would trigger undeclared-identifier
-- errors in slang. Lint-specific tests re-enable it explicitly.
ctx:set_lint(false)

lester.parse_args()

describe("SVBuilder test", function()
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
        -- SVBuilder:generate() is equal to tostring(SVBuilder)
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

    it("has SVBuilder:with_global_envs", function()
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
        ---@cast ret verilua.sv.SVBuilder.sequence
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
        ---@cast ret1 verilua.sv.SVBuilder.property
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
                "[SVBuilder] cannot reference sequence `handshake` as a flat `$(handshake)`; use the `seq:` prefix, e.g. `$(seq:handshake)`",
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
                "[SVBuilder] cannot reference property `no_overflow` as a flat `$(no_overflow)`; use the `prop:` prefix, e.g. `$(prop:no_overflow)`",
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
            err_str:find("[SVBuilder] lint error in 's_bad'", 1, true),
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
            err_str:find("[SVBuilder] lint error in 's_range'", 1, true),
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
            err_str:find("[SVBuilder] lint error in 'chk2'", 1, true),
            "expected lint error for chk2, got: " .. err_str
        )
        ctx:clean()

        ctx:set_lint(false)
    end)

    -- Covergroup tests
    it("can add covergroup", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        ctx:add "covergroup" {
            name = "cg_basic",
            expr = [[
    coverpoint $(sig) {
        bins low  = {[0:3]};
        bins high = {[4:7]};
    }]],
            envs = { sig = { __type = "CallableHDL", fullpath = "top.dut.data" } }
        }

        local result = tostring(ctx)
        -- Should contain covergroup definition
        assert(result:find("covergroup cg_basic @(posedge top.dut.clk);", 1, true),
            "expected covergroup header, got: " .. result)
        -- Should contain coverpoint with resolved XMR
        assert(result:find("coverpoint top.dut.data", 1, true),
            "expected resolved XMR in coverpoint, got: " .. result)
        -- Should contain endgroup
        assert(result:find("endgroup", 1, true),
            "expected endgroup, got: " .. result)
        -- Should contain instantiation
        assert(result:find("cg_basic _GEN_cg_basic_inst = new;", 1, true),
            "expected instantiation, got: " .. result)
        -- Should contain final block with coverage report
        assert(result:find("final begin", 1, true),
            "expected final block, got: " .. result)
        assert(result:find('[COVERAGE] cg_basic', 1, true),
            "expected coverage display, got: " .. result)
        assert(result:find("_GEN_cg_basic_inst.get_inst_coverage()", 1, true),
            "expected get_inst_coverage call, got: " .. result)

        ctx:clean()
    end)

    it("covergroup uses per-covergroup sample_event override", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        ctx:add "covergroup" {
            name = "cg_alt",
            sample_event = "negedge top.dut.alt_clk",
            expr = [[
    coverpoint top.dut.sig {
        bins b1 = {0};
    }]],
        }

        local result = tostring(ctx)
        -- Should use the override, not default_clocking
        assert(result:find("covergroup cg_alt @(negedge top.dut.alt_clk);", 1, true),
            "expected alt clock in covergroup, got: " .. result)

        ctx:clean()
    end)

    it("covergroup fails without sampling event", function()
        -- No default_clocking set, no sample_event provided
        local ok, err = pcall(function()
            ctx:add "covergroup" {
                name = "cg_no_clk",
                expr = "coverpoint x { bins b = {0}; }",
            }
        end)
        expect.equal(ok, false)
        local err_str = tostring(err)
        assert(
            err_str:find("[SVBuilder] covergroup error: no sampling event", 1, true),
            "expected no sampling event error, got: " .. err_str
        )

        ctx:clean()
    end)

    it("set_coverage_report(false) disables final block", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")
        ctx:set_coverage_report(false)

        ctx:add "covergroup" {
            name = "cg_noreport",
            expr = "coverpoint top.dut.x { bins b = {0}; }",
        }

        local result = tostring(ctx)
        -- Should NOT contain final block
        assert(not result:find("final begin", 1, true),
            "expected no final block, got: " .. result)
        -- Should still contain the covergroup itself
        assert(result:find("covergroup cg_noreport", 1, true),
            "expected covergroup definition, got: " .. result)

        ctx:set_coverage_report(true)
        ctx:clean()
    end)

    it("multiple covergroups generate multiple coverage reports", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        ctx:add "covergroup" {
            name = "cg_a",
            expr = "coverpoint top.dut.a { bins b = {0}; }",
        }
        ctx:add "covergroup" {
            name = "cg_b",
            expr = "coverpoint top.dut.b { bins b = {1}; }",
        }

        local result = tostring(ctx)
        -- Should have both covergroups
        assert(result:find("covergroup cg_a", 1, true), "expected cg_a")
        assert(result:find("covergroup cg_b", 1, true), "expected cg_b")
        -- Final block should report both
        assert(result:find("[COVERAGE] cg_a", 1, true), "expected cg_a in final")
        assert(result:find("[COVERAGE] cg_b", 1, true), "expected cg_b in final")

        ctx:clean()
    end)

    it("covergroup with template engine", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        ctx:add "covergroup" {
            name = "cg_tmpl",
            expr = [[
# for i = 0, 2 do
    coverpoint top.dut.ch$(i) {
        bins low  = {[0:3]};
        bins high = {[4:7]};
    }
# end]],
        }

        local result = tostring(ctx)
        assert(result:find("coverpoint top.dut.ch0", 1, true), "expected ch0")
        assert(result:find("coverpoint top.dut.ch1", 1, true), "expected ch1")
        assert(result:find("coverpoint top.dut.ch2", 1, true), "expected ch2")

        ctx:clean()
    end)

    it("covergroup appears after SVA content in output", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        ctx:add "sequence" { name = "s1", expr = "top.dut.a ##1 top.dut.b" }
        ctx:add "assert" { name = "a1", expr = "$(seq:s1) |-> top.dut.c" }
        ctx:add "covergroup" {
            name = "cg_order",
            expr = "coverpoint top.dut.d { bins b = {0}; }",
        }

        local result = tostring(ctx)
        local seq_pos = result:find("sequence s1", 1, true)
        local assert_pos = result:find("a1: assert", 1, true)
        local cg_pos = result:find("covergroup cg_order", 1, true)
        local final_pos = result:find("final begin", 1, true)

        -- Verify ordering: sequence < assert < covergroup < final
        assert(seq_pos < assert_pos, "sequence should come before assert")
        assert(assert_pos < cg_pos, "assert should come before covergroup")
        assert(cg_pos < final_pos, "covergroup should come before final block")

        ctx:clean()
    end)

    it("sv_lint catches covergroup syntax errors", function()
        ctx:set_lint(true)

        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        -- Valid covergroup passes lint
        local ok, err = pcall(function()
            ctx:add "covergroup" {
                name = "cg_lint_ok",
                expr = [[
    coverpoint top.dut.data {
        bins low  = {[0:3]};
        bins high = {[4:7]};
    }]],
            }
        end)
        expect.equal(ok, true)
        ctx:clean()

        -- Syntax error: missing semicolon in bins
        ctx:default_clocking(clock_signal, "posedge")
        ok, err = pcall(function()
            ctx:add "covergroup" {
                name = "cg_lint_bad",
                expr = [[
    coverpoint top.dut.data {
        bins low  = {[0:3]
    }]],
            }
        end)
        expect.equal(ok, false)
        local err_str = tostring(err)
        assert(
            err_str:find("[SVBuilder] lint error in 'cg_lint_bad'", 1, true),
            "expected lint error for cg_lint_bad, got: " .. err_str
        )
        ctx:clean()

        -- Missing coverpoint expression
        ctx:default_clocking(clock_signal, "posedge")
        ok, err = pcall(function()
            ctx:add "covergroup" {
                name = "cg_lint_no_expr",
                expr = [[
    coverpoint { bins b = {0}; }]],
            }
        end)
        expect.equal(ok, false)
        err_str = tostring(err)
        assert(
            err_str:find("[SVBuilder] lint error in 'cg_lint_no_expr'", 1, true),
            "expected lint error for cg_lint_no_expr, got: " .. err_str
        )
        ctx:clean()

        ctx:set_lint(false)
    end)

    it("sv_lint catches covergroup semantic errors", function()
        ctx:set_lint(true)

        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        -- Cross referencing non-existent coverpoint
        local ok, err = pcall(function()
            ctx:add "covergroup" {
                name = "cg_lint_bad_cross",
                expr = [[
    coverpoint top.dut.a { bins b = {0}; }
    cross nonexist_cp, top.dut.a;]],
            }
        end)
        expect.equal(ok, false)
        local err_str = tostring(err)
        assert(
            err_str:find("[SVBuilder] lint error in 'cg_lint_bad_cross'", 1, true),
            "expected lint error for cg_lint_bad_cross, got: " .. err_str
        )
        ctx:clean()

        ctx:set_lint(false)
    end)

    it("sample_event supports template expansion", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        -- sample_event with $(var) template
        ctx:add "covergroup" {
            name = "cg_tmpl_event",
            sample_event = "posedge $(my_clk)",
            expr = "coverpoint top.dut.data { bins b = {0}; }",
            envs = { my_clk = { __type = "CallableHDL", fullpath = "top.dut.fast_clk" } },
        }

        local result = tostring(ctx)
        assert(result:find("covergroup cg_tmpl_event @(posedge top.dut.fast_clk);", 1, true),
            "expected expanded sample_event, got: " .. result)

        ctx:clean()
    end)

    it("sample_event with 'with function sample' syntax", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        ctx:add "covergroup" {
            name = "cg_with_sample",
            sample_event = "with function sample(bit [7:0] cmd)",
            expr = [[
    coverpoint cmd {
        bins read  = {0};
        bins write = {1};
    }]],
        }

        local result = tostring(ctx)
        assert(result:find("covergroup cg_with_sample with function sample(bit [7:0] cmd);", 1, true),
            "expected 'with function sample' header, got: " .. result)
        -- The covergroup header should NOT have @()
        assert(not result:find("covergroup cg_with_sample @(", 1, true),
            "should not contain @() in covergroup header when using 'with' syntax, got: " .. result)

        ctx:clean()
    end)

    it("sample_event with leading whitespace before 'with'", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        ctx:add "covergroup" {
            name = "cg_with_space",
            sample_event = "  with function sample(bit en)",
            expr = "coverpoint en { bins on = {1}; }",
        }

        local result = tostring(ctx)
        assert(result:find("covergroup cg_with_space with function sample(bit en);", 1, true),
            "expected trimmed 'with' header, got: " .. result)

        ctx:clean()
    end)

    it("sample_event is rejected for non-covergroup types", function()
        local clock_signal = {
            __type = "CallableHDL",
            fullpath = "top.dut.clk",
            get_width = function() return 1 end
        }
        ---@cast clock_signal verilua.handles.CallableHDL
        ctx:default_clocking(clock_signal, "posedge")

        -- cover
        local ok, err = pcall(function()
            ctx:add "cover" { name = "bad1", expr = "x", sample_event = "posedge clk" }
        end)
        expect.equal(ok, false)
        assert(tostring(err):find("sample_event.*only valid for.*covergroup", 1, false),
            "expected rejection for cover, got: " .. tostring(err))

        -- sequence
        ok, err = pcall(function()
            ctx:add "sequence" { name = "bad2", expr = "x", sample_event = "posedge clk" }
        end)
        expect.equal(ok, false)
        assert(tostring(err):find("sample_event.*only valid for.*covergroup", 1, false),
            "expected rejection for sequence, got: " .. tostring(err))

        ctx:clean()
    end)
end)

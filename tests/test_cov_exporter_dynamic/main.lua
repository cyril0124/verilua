-- main.lua — Dynamic verification of cond-path coverage using CoverageGetter.
--
-- Drives the DUT through 7 stimulus phases. After every phase we call
-- CoverageGetter:get_coverage_count() and assert the cond-path covered count
-- grows as expected.

local CoverageGetter = require "verilua.utils.CoverageGetter"

local clock          = dut.clock:chdl()
local reset          = dut.reset:chdl()
local a              = dut.a:chdl()
local b              = dut.b:chdl()
local c              = dut.c:chdl()
local d              = dut.d:chdl()
local e              = dut.e:chdl()

local EXPECTED_TOTAL = 8
local HIER           = "tb_top.u_cond_path_top"

local function check_cond_covered(phase_name, expected_covered)
    local _, bin_expr_count = CoverageGetter:get_coverage_count(HIER)
    assert(
        bin_expr_count == expected_covered,
        string.format("[%s] FAILED: covered=%d expected=%d (total=%d)",
            phase_name, bin_expr_count, expected_covered, EXPECTED_TOTAL)
    )
    print(string.format("[cond_path] PASS %s: covered=%d/%d", phase_name, bin_expr_count, EXPECTED_TOTAL))
end

fork {
    function()
        -- Initialize all inputs to 0.
        reset:set_imm(0)
        a:set_imm(0)
        b:set_imm(0)
        c:set_imm(0)
        d:set_imm(0)
        e:set_imm(0)

        clock:posedge()
        check_cond_covered("phase0_idle", 0)

        -- Phase 1: assert reset -> exercises the reset branch (path 0).
        -- The synchronous always also runs and hits the explicit else (path 5)
        -- because a=b=d=0.
        reset:set_imm(1)
        clock:posedge()
        reset:set_imm(0)
        check_cond_covered("phase1_reset", 2)

        -- Phase 2: a=1 -> exercises the `if (a)` branch.
        a:set_imm(1)
        clock:posedge()
        a:set_imm(0)
        check_cond_covered("phase2_a", 3)

        -- Phase 3: b=1, c=0 -> exercises `else if (b)` without entering inner if.
        b:set_imm(1)
        c:set_imm(0)
        clock:posedge()
        check_cond_covered("phase3_b_only", 4)

        -- Phase 4: b=1, c=1 -> additionally hits the nested `if (c)`.
        c:set_imm(1)
        clock:posedge()
        b:set_imm(0)
        c:set_imm(0)
        check_cond_covered("phase4_b_and_c", 5)

        -- Phase 5: d=1 -> exercises `else if (d)`.
        d:set_imm(1)
        clock:posedge()
        d:set_imm(0)
        check_cond_covered("phase5_d", 6)

        -- Phase 6: e=1 -> exercises the standalone `if (e)`. The outer `else`
        -- branch (path 5) was already covered in phase 1.
        e:set_imm(1)
        clock:posedge()
        e:set_imm(0)
        check_cond_covered("phase6_e", 7)

        -- Phase 7: a=1, e=1 -> exercises the `if (a & e)` inside the for-loop.
        -- Also re-hits `if (a)` (already covered).
        a:set_imm(1)
        e:set_imm(1)
        clock:posedge()
        a:set_imm(0)
        e:set_imm(0)
        check_cond_covered("phase7_a_and_e", 8)

        -- All paths covered: verify cond_coverage ratio == 1.0.
        local cond_cov = CoverageGetter:get_cond_coverage(HIER)
        assert(
            cond_cov == 1.0,
            string.format("[phase_all_covered] FAILED: cond_coverage=%.4f expected=1.0", cond_cov)
        )
        print(string.format("[cond_path] PASS phase_all_covered: cond_coverage=%.4f", cond_cov))

        -- Disable coverage, drive new stimulus, assert covered count does NOT change.
        CoverageGetter:disable_coverage(HIER)
        a:set_imm(1)
        clock:posedge()
        a:set_imm(0)
        local _, count_after_disable = CoverageGetter:get_coverage_count(HIER)
        assert(
            count_after_disable == 8,
            string.format("[disable_coverage] FAILED: count changed to %d after disable", count_after_disable)
        )
        print("[cond_path] PASS disable_coverage: count unchanged")

        -- Re-enable coverage, reset counters, drive stimulus, assert it counts again.
        CoverageGetter:enable_coverage(HIER)
        CoverageGetter:reset_coverage(HIER)
        local _, count_after_reset = CoverageGetter:get_coverage_count(HIER)
        assert(
            count_after_reset == 0,
            string.format("[enable_coverage] FAILED: count=%d after reset, expected 0", count_after_reset)
        )
        -- Drive a=1 to hit path 1 again.
        a:set_imm(1)
        clock:posedge()
        a:set_imm(0)
        local _, count_after_enable = CoverageGetter:get_coverage_count(HIER)
        assert(
            count_after_enable > 0,
            string.format("[enable_coverage] FAILED: count=%d after re-enable, expected > 0", count_after_enable)
        )
        print(string.format("[cond_path] PASS enable_coverage: count=%d after re-enable", count_after_enable))

        -- Show final coverage report.
        CoverageGetter:show_cond_coverage(HIER)

        print("[cond_path] ALL PHASES PASSED")
        sim.finish()
    end
}

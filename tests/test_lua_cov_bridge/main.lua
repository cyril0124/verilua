local SymbolHelper   = require "verilua.utils.SymbolHelper"

-- DPI exports injected into tb_top (see cov_bridge.sv). SymbolHelper resolves the
-- symbols in the running simulator binary.
local cov_sample     = SymbolHelper.try_ffi_cast("void verilua_cov_sample(unsigned int cov_id);")
local cov_hit_count  = SymbolHelper.try_ffi_cast("int verilua_cov_hit_count();")

-- Bins of the covergroup, with the counter range each one covers. Tags must match
-- the bins in cov_bridge.sv.
local COVERAGE_BINS  = {
    { tag = 0,   name = "count_zero",   min_value = 0,   max_value = 0 },
    { tag = 1,   name = "count_small",  min_value = 1,   max_value = 63 },
    { tag = 64,  name = "count_medium", min_value = 64,  max_value = 127 },
    { tag = 128, name = "count_large",  min_value = 128, max_value = 255 },
}

-- The observed counter is 8 bits wide, so it returns to its start after this many
-- clock edges.
local COUNTER_PERIOD = 256

local clock          = dut.clock:chdl()
local count          = dut.u_top.count:chdl()

local sampled_tags   = {}

local function set_testbench_scope()
    -- A DPI export is called in the scope of the module that declares it, and the
    -- scope is reset across scheduler yields, so set it before every call.
    sim.set_dpi_scope()
end

local function sample(bin)
    if sampled_tags[bin.tag] then
        return
    end

    set_testbench_scope()
    cov_sample(bin.tag)

    sampled_tags[bin.tag] = true
    print(string.format("[lua_cov_bridge] sampled tag=%d (%s)", bin.tag, bin.name))
end

local function bin_of_count(value)
    for _, bin in ipairs(COVERAGE_BINS) do
        if value >= bin.min_value and value <= bin.max_value then
            return bin
        end
    end

    return nil
end

local function all_bins_sampled()
    for _, bin in ipairs(COVERAGE_BINS) do
        if not sampled_tags[bin.tag] then
            return false
        end
    end

    return true
end

fork {
    function()
        -- Sampling starts on the first clock edge, because a DPI export call made
        -- before the simulator finishes initializing is silently dropped by
        -- Verilator.
        clock:posedge()

        -- One clock edge per iteration. One full counter period visits every bin.
        --
        -- clock:posedge() is used rather than await_rd(): back-to-back await_rd()
        -- calls stall on VCS, because the second cbReadOnlySynch callback is
        -- registered from inside the read-only region and VCS drops it.
        for _ = 1, COUNTER_PERIOD do
            local bin = bin_of_count(tonumber(count:get()) or 0)
            if bin ~= nil then
                sample(bin)
            end

            if all_bins_sampled() then
                break
            end

            clock:posedge()
        end

        for _, bin in ipairs(COVERAGE_BINS) do
            assert(sampled_tags[bin.tag], string.format("[lua_cov_bridge] bin %s was never sampled", bin.name))
        end

        -- The SV side counts the samples it received, so this checks that the
        -- covergroup ran, not only that the call returned.
        set_testbench_scope()
        local sv_sample_count = cov_hit_count()
        print(string.format("[lua_cov_bridge] SV side received %d samples", sv_sample_count))
        assert(sv_sample_count == #COVERAGE_BINS,
            string.format("[lua_cov_bridge] expected %d samples on the SV side, got %d", #COVERAGE_BINS,
                sv_sample_count))

        print("[lua_cov_bridge] PASS: every coverage bin sampled")
        sim.finish()
    end
}

-- Issue #11 reproduction: set() after value-change callback timing inconsistency
--
-- Expected: edge_write:set(1) should produce a posedge observable at the SAME
-- simulation time regardless of whether the triggering source edge comes from
-- RTL (sv_driven_reg) or from Verilua's own set() (verilua_driven_reg).
--
-- Actual (broken): When source is Verilua-driven, the edge_write posedge is
-- delayed to the next timestep.

local clock = dut.clock:chdl()
local verilua_driven_reg = dut.u_top.verilua_driven_reg:chdl()
local sv_driven_reg = dut.u_top.sv_driven_reg:chdl()
local edge_write_from_verilua_src = dut.u_top.edge_write_from_verilua_src:chdl()
local edge_write_from_sv_src = dut.u_top.edge_write_from_sv_src:chdl()

-- Results collected by each sub-test
local sv_src_time = nil ---@type integer?
local sv_observe_time = nil ---@type integer?
local vl_src_time = nil ---@type integer?
local vl_observe_time = nil ---@type integer?

fork {
    -- Test A: driver that observes SV-driven posedge and writes target
    sv_main = function()
        sv_driven_reg:posedge()
        sv_src_time = sim.get_sim_time()
        print(string.format("[Test A] sv_driven_reg posedge observed at t=%d", sv_src_time))
        edge_write_from_sv_src:set(1)
    end,

    -- Test A: observer of the target signal
    sv_observer = function()
        edge_write_from_sv_src:posedge()
        sv_observe_time = sim.get_sim_time()
        print(string.format("[Test A] edge_write_from_sv_src posedge observed at t=%d", sv_observe_time))
    end,

    -- Test B: reg_driver toggles verilua_driven_reg every clock
    vl_reg_driver = function()
        while true do
            clock:posedge()
            verilua_driven_reg:set(1 - verilua_driven_reg:get())
        end
    end,

    -- Test B: driver that observes Verilua-driven posedge and writes target
    vl_main = function()
        verilua_driven_reg:posedge()
        vl_src_time = sim.get_sim_time()
        print(string.format("[Test B] verilua_driven_reg posedge observed at t=%d", vl_src_time))
        edge_write_from_verilua_src:set(1)
    end,

    -- Test B: observer of the target signal
    vl_observer = function()
        edge_write_from_verilua_src:posedge()
        vl_observe_time = sim.get_sim_time()
        print(string.format("[Test B] edge_write_from_verilua_src posedge observed at t=%d", vl_observe_time))
    end,

    -- Watchdog: wait for all edge observations, then verify and finish
    watchdog = function()
        clock:posedge(50)

        -- Report and check
        print(string.format("[Test A] SV-driven source:      src_time=%s, observe_time=%s", tostring(sv_src_time),
            tostring(sv_observe_time)))
        print(string.format("[Test B] Verilua-driven source: src_time=%s, observe_time=%s", tostring(vl_src_time),
            tostring(vl_observe_time)))

        assert(sv_src_time ~= nil, "Test A: sv_src_time was never set (sv_driven_reg posedge not observed)")
        assert(sv_observe_time ~= nil,
            "Test A: sv_observe_time was never set (edge_write_from_sv_src posedge not observed)")
        assert(vl_src_time ~= nil, "Test B: vl_src_time was never set (verilua_driven_reg posedge not observed)")
        assert(vl_observe_time ~= nil,
            "Test B: vl_observe_time was never set (edge_write_from_verilua_src posedge not observed)")

        -- Core check: source edge should be same-time observable regardless of origin
        assert(sv_src_time == sv_observe_time,
            string.format("Test A FAILED: SV-driven src_time=%d but observe_time=%d (expected same)", sv_src_time,
                sv_observe_time))
        assert(vl_src_time == vl_observe_time,
            string.format("Test B FAILED: Verilua-driven src_time=%d but observe_time=%d (expected same)", vl_src_time,
                vl_observe_time))

        -- Cross-consistency: both paths should behave identically
        local sv_delta = sv_observe_time - sv_src_time
        local vl_delta = vl_observe_time - vl_src_time
        assert(sv_delta == vl_delta,
            string.format("INCONSISTENCY: SV path delta=%d, Verilua path delta=%d (expected equal)", sv_delta, vl_delta))

        print("[PASS] set() after edge callback is consistent regardless of edge source")
        sim.finish()
    end,
}

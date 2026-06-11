local clock = dut.clock:chdl()

local no_internal_clock = os.getenv("NO_INTERNAL_CLOCK")
if no_internal_clock then
    fork {
        function()
            while true do
                clock:set(1)
                await_time_ns(10)
                clock:set(0)
                await_time_ns(10)
            end
        end
    }
end

local test_ok = false
fork {
    function()
        sim.dump_wave()

        dut.reset:set(1)
        clock:posedge(1)
        dut.reset:set(0)
        clock:posedge()

        fork {
            function()
                local prev_cycles = 0
                while true do
                    clock:posedge()
                    dut.valid:set(1)
                    print(dut.u_top.cycles:get(), "set valid", "ready: " .. dut.ready:get())

                    prev_cycles = dut.cycles:get()

                    await_time(1) -- Wait for combinational logic to settle
                    print(dut.u_top.cycles:get(), "[After] set valid", "ready: " .. dut.ready:get())

                    if dut.ready:is(0) then
                        -- Cocotb reference (cocotb-driven clock on all simulators):
                        --   cycles=3, prev_cycles=2
                        --
                        -- Verilua behavior differs by simulator due to cbReadWriteSynch
                        -- re-entry support:
                        -- - Verilator: the re-registered cbReadWriteSynch fires within the
                        --   same timestep, causing an extra eval round. This makes valid=1
                        --   visible one eval earlier → cycles=4, prev_cycles=3.
                        -- - iverilog/VCS: the re-registered cbReadWriteSynch defers to the
                        --   next timestep (same as cocotb) → cycles=3, prev_cycles=2.
                        --
                        -- Both results are functionally correct (ready goes low due to the
                        -- same causal chain). The difference is only observational timing
                        -- of the cycles counter, not signal correctness.
                        if no_internal_clock and (cfg.simulator == "iverilog" or cfg.simulator == "vcs") then
                            dut.cycles:expect(3)
                            assert(prev_cycles == 2)
                        else
                            dut.cycles:expect(4)
                            assert(prev_cycles == 3)
                        end
                        dut.valid:set(0)

                        fork {
                            function()
                                clock:negedge()
                                if no_internal_clock and (cfg.simulator == "iverilog" or cfg.simulator == "vcs") then
                                    dut.cycles:expect(3)
                                else
                                    dut.cycles:expect(4)
                                end
                                dut.valid:expect(0)
                            end
                        }

                        test_ok = true
                        break
                    end
                end
            end
        }

        clock:posedge(10)
        sim.finish()
    end
}

final {
    function()
        assert(test_ok, "Test did not complete successfully")
    end
}

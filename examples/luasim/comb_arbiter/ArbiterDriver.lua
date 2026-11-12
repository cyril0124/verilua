---@param input0 CombArbiterPort
---@param input1 CombArbiterPort
---@param output CombArbiterPort
local function run(input0, input1, output)
    local trace = assert(io.open("comb_trace.csv", "w"))
    trace:write("case,time,valid0,data0,valid1,data1,ready,valid,data,ready0,ready1\n")

    final {
        function()
            trace:close()
        end,
    }

    ---@param valid0 integer
    ---@param data0 integer
    ---@param valid1 integer
    ---@param data1 integer
    ---@param ready integer
    local function drive(valid0, data0, valid1, data1, ready)
        input0.valid:set(valid0)
        input0.data:set(data0)
        input1.valid:set(valid1)
        input1.data:set(data1)
        output.ready:set(ready)
    end

    ---@param label string
    ---@param expected_valid integer
    ---@param expected_data integer
    ---@param expected_ready0 integer
    ---@param expected_ready1 integer
    local function settle_and_check(label, expected_valid, expected_data, expected_ready0, expected_ready1)
        local time_before = sim.get_sim_time()
        await_rw()

        output.valid:expect(expected_valid)
        output.data:expect(expected_data)
        input0.ready:expect(expected_ready0)
        input1.ready:expect(expected_ready1)
        assert(sim.get_sim_time() == time_before, "combinational settling advanced simulation time")

        trace:write(string.format("%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
            label, time_before,
            input0.valid:get(), input0.data:get(),
            input1.valid:get(), input1.data:get(), output.ready:get(),
            output.valid:get(), output.data:get(), input0.ready:get(), input1.ready:get()))

        print(string.format("CHECK %s time=%d valid=%d data=0x%08x ready0=%d ready1=%d",
            label, time_before, expected_valid, expected_data, expected_ready0, expected_ready1))
    end

    fork {
        test = function()
            if cfg.simulator ~= "luasim" then
                sim.dump_wave("comb_arbiter.vcd")
            end

            drive(0, 0x11223344, 0, 0x55667788, 0)
            settle_and_check("idle_stalled", 0, 0, 0, 0)

            await_time_ns(10)
            drive(0, 0x11223344, 0, 0x55667788, 1)
            settle_and_check("idle_ready", 0, 0, 1, 1)

            await_time_ns(10)
            drive(0, 0x11223344, 1, 0x55667788, 1)
            settle_and_check("input1_only", 1, 0x55667788, 1, 1)

            await_time_ns(10)
            input1.data:set(0xdeadbeef)
            settle_and_check("input1_data_only", 1, 0xdeadbeef, 1, 1)

            input1.data:set(0x89abcdef)
            settle_and_check("same_time_data_change", 1, 0x89abcdef, 1, 1)
            input1.data:set(0xdeadbeef)
            settle_and_check("same_time_data_restore", 1, 0xdeadbeef, 1, 1)

            await_time_ns(10)
            input0.valid:set(1)
            settle_and_check("both_valid_input0_wins", 1, 0x11223344, 1, 0)

            await_time_ns(10)
            output.ready:set(0)
            settle_and_check("output_backpressure", 1, 0x11223344, 0, 0)

            await_time_ns(10)
            input0.valid:set(0)
            settle_and_check("selection_changes_while_stalled", 1, 0xdeadbeef, 0, 0)

            await_time_ns(10)
            input0.data:set(0xffffffff)
            settle_and_check("unselected_data_change", 1, 0xdeadbeef, 0, 0)

            await_time_ns(10)
            drive(1, 0xffffffff, 0, 0xdeadbeef, 0)
            settle_and_check("input0_only_stalled", 1, 0xffffffff, 0, 0)

            await_time_ns(10)
            output.ready:set(1)
            settle_and_check("input0_only_ready", 1, 0xffffffff, 1, 0)

            await_time_ns(10)
            input0.valid:set(0)
            settle_and_check("return_to_idle", 0, 0, 1, 1)

            print("PASS: clockless priority arbitration, data changes, backpressure and zero-time settling")
            sim.finish()
        end,

        watchdog = function()
            await_time_ns(1000)
            error("combinational arbiter example timed out")
        end,
    }
end

return run

local wctrl = require "verilua.utils.WaveVpiCtrl"

local clock = dut.clock:chdl()
local wtype = os.getenv("WTYPE") or "fsdb"
local final_cycles = wtype == "fsdb" and 111 or 112

local function tc_start(tc_name)
    print()
    print(string.rep("=", 50))
    print("START: " .. tc_name)
    print(string.rep("=", 50))
end

local function tc_finish()
    print()
    print(string.rep("=", 50))
    print("FINISH")
    print(string.rep("=", 50))
    sim.finish()
end

local tc_name = os.getenv("TC_NAME")
assert(tc_name, "TC_NAME is not set")

tc_start(tc_name)

if tc_name == "basic" then
    fork {
        function()
            dut.cycles:expect(0)
            dut.reset:expect(1)

            clock:posedge(10, function()
                -- Reset is always `1`
                dut.u_top.count:expect(0)
            end)
            dut.cycles:expect(10)
            dut.reset:expect(1)

            clock:posedge()
            dut.reset:expect(0)

            dut.u_top.count:expect(0)

            clock:posedge(100, function(c)
                dut.u_top.count:expect(c - 1)
            end)
            dut.cycles:expect(111)

            tc_finish()
        end
    }
elseif tc_name == "to_end" then
    fork {
        function()
            wctrl:to_end()
            dut.cycles:expect(final_cycles)
            tc_finish()
        end
    }
elseif tc_name == "to_end_1" then
    fork {
        function()
            fork {
                function()
                    while true do
                        clock:posedge()
                    end
                end
            }

            clock:posedge(10)
            wctrl:to_end(true)
            dut.cycles:expect(final_cycles)

            tc_finish()
        end
    }
elseif tc_name == "to_end_2" then
    fork {
        main_task = function()
            local cnt = 0
            fork {
                acc_task = function()
                    while true do
                        clock:posedge()
                        cnt = cnt + 1
                    end
                end
            }

            clock:posedge(10)

            assert(#scheduler:get_running_tasks() == 2)
            wctrl:to_end(true)
            assert(cnt == 10)
            dut.cycles:expect(final_cycles)
            assert(#scheduler:get_running_tasks() == 1)
            assert(scheduler:get_running_tasks()[1].name == "main_task")

            wctrl:to_percent(0, true)
            dut.cycles:expect(0)

            clock:posedge(11)

            dut.cycles:expect(11)
            assert(cnt == 10)

            wctrl:to_percent(50, true)
            dut.cycles:expect(56)

            fork {
                acc_task = function()
                    while true do
                        clock:posedge()
                        cnt = cnt + 1
                    end
                end
            }
            clock:posedge(10)
            assert(cnt == 20)

            wctrl:to_percent(50, true)
            clock:posedge(10)
            assert(cnt == 20)

            wctrl:to_end(true)
            dut.cycles:expect(final_cycles)

            tc_finish()
        end
    }
elseif tc_name == "set_cursor_time" then
    fork {
        function()
            local max_time = tonumber(wctrl:get_max_cursor_time()) --[[@as integer]]
            assert(max_time > 0, "max_time should be positive")

            local half_time = math.floor(max_time / 2)
            wctrl:set_cursor_time(half_time, nil, false)

            local half_cycles = wtype == "fsdb" and 56 or 57
            dut.cycles:expect(half_cycles)

            wctrl:set_cursor_time(max_time, nil, true)
            dut.cycles:expect(final_cycles)

            tc_finish()
        end
    }
elseif tc_name == "get_max_cursor_time_unit" then
    fork {
        function()
            local function approx_eq(a, b, msg)
                local eps = 1e-9
                local diff = math.abs(a - b)
                local scale = math.max(math.abs(a), math.abs(b), 1)
                assert(diff / scale < eps, msg .. string.format(" (got %g vs %g)", a, b))
            end

            -- Raw step value
            local max_time_step = tonumber(wctrl:get_max_cursor_time()) --[[@as number]]
            assert(max_time_step > 0, "max_time should be positive")

            -- Default (nil) should equal step
            local max_time_default = tonumber(wctrl:get_max_cursor_time(nil)) --[[@as number]]
            assert(max_time_step == max_time_default, "nil unit should return same as no argument")

            -- "step" should equal raw
            local max_time_step_explicit = tonumber(wctrl:get_max_cursor_time("step")) --[[@as number]]
            assert(max_time_step == max_time_step_explicit, '"step" unit should return same as raw')

            -- Different units should all be positive
            local max_time_ns = tonumber(wctrl:get_max_cursor_time("ns")) --[[@as number]]
            local max_time_ps = tonumber(wctrl:get_max_cursor_time("ps")) --[[@as number]]
            local max_time_fs = tonumber(wctrl:get_max_cursor_time("fs")) --[[@as number]]
            local max_time_us = tonumber(wctrl:get_max_cursor_time("us")) --[[@as number]]
            assert(max_time_ns > 0, "max_time_ns should be positive")
            assert(max_time_ps > 0, "max_time_ps should be positive")
            assert(max_time_fs > 0, "max_time_fs should be positive")
            assert(max_time_us > 0, "max_time_us should be positive")

            -- Verify unit conversion relationships: larger unit => smaller numeric value
            assert(max_time_fs > max_time_ps, "fs value should be > ps value")
            assert(max_time_ps > max_time_ns, "ps value should be > ns value")
            assert(max_time_ns > max_time_us, "ns value should be > us value")

            -- Verify conversion ratio consistency (use approx_eq for floating point)
            approx_eq(max_time_fs, max_time_ps * 1000, "fs should be 1000x ps")
            approx_eq(max_time_ps, max_time_ns * 1000, "ps should be 1000x ns")
            approx_eq(max_time_ns, max_time_us * 1000, "ns should be 1000x us")

            tc_finish()
        end
    }
elseif tc_name == "set_cursor_time_unit" then
    fork {
        function()
            -- Get max time in different units
            local max_time_step = tonumber(wctrl:get_max_cursor_time()) --[[@as number]]
            local max_time_ps = tonumber(wctrl:get_max_cursor_time("ps")) --[[@as number]]
            assert(max_time_step > 0, "max_time should be positive")
            assert(max_time_ps > 0, "max_time_ps should be positive")

            -- set_cursor_time with ps unit should work the same as raw steps
            local half_time_ps = math.floor(max_time_ps / 2)
            wctrl:set_cursor_time(half_time_ps, "ps", false)

            local half_cycles = wtype == "fsdb" and 56 or 57
            dut.cycles:expect(half_cycles)

            -- set_cursor_time with raw steps (no unit) should still work
            wctrl:set_cursor_time(max_time_step, nil, true)
            dut.cycles:expect(final_cycles)

            -- set_cursor_time with "step" unit should be same as no unit
            wctrl:to_percent(0, true)
            dut.cycles:expect(0)

            local half_time_step = math.floor(max_time_step / 2)
            wctrl:set_cursor_time(half_time_step, "step", false)
            dut.cycles:expect(half_cycles)

            tc_finish()
        end
    }
else
    verilua_error("unknown test case: " .. tc_name)
end

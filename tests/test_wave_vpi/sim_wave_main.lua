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
            wctrl:set_cursor_time(half_time, false)

            local half_cycles = wtype == "fsdb" and 56 or 57
            dut.cycles:expect(half_cycles)

            wctrl:set_cursor_time(max_time, true)
            dut.cycles:expect(final_cycles)

            tc_finish()
        end
    }
else
    verilua_error("unknown test case: " .. tc_name)
end

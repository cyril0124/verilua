local clock = dut.clock:chdl()
local clock1 = dut.clock1:chdl()
local clock2 = dut.clock2:chdl()
local clock3 = dut.clock3:chdl()
local clock4 = dut.clock4:chdl()

local reset = dut.reset:chdl() --[[@as CallableHDL]]
local reset1 = dut.reset1:chdl()
local reset2 = dut.reset2:chdl()

local count = dut.count:chdl()
local count1 = dut.count1:chdl()
local count2 = dut.count2:chdl()
local count3 = dut.count3:chdl()
local count4 = dut.count4:chdl()

local is_verilator = cfg.simulator == "verilator"
local no_inertial_put = os.getenv("CFG_USE_INERTIAL_PUT") == "0"
local is_inertial_put = not no_inertial_put

---@param clock CallableHDL
---@return TaskFunction
local gen_clock = function(clock, period)
    return function()
        while true do
            clock.value = 1
            await_time(period)
            clock.value = 0
            await_time(period)
        end
    end
end

fork {
    gen_clock(clock, 2),
    gen_clock(clock1, 3),
    gen_clock(clock2, 4),

    function()
        if os.getenv("DUMP") then
            sim.dump_wave()
        end

        clock:posedge()

        local test_posedge = function()
            local e = jfork {
                function()
                    reset.value = 1
                    clock:posedge()
                    reset.value = 0
                    clock:posedge()

                    if is_verilator then
                        count:expect(0)
                        clock:posedge(10)
                        count:expect(10)
                    else
                        count:expect(1)
                        clock:posedge(10)
                        count:expect(11)
                    end

                    reset.value = 1
                    clock:posedge()
                    reset.value = 0
                    clock:posedge()

                    if is_verilator then
                        count:expect(0)
                        clock:posedge(100)
                        count:expect(100)
                    else
                        count:expect(1)
                        clock:posedge(100)
                        count:expect(101)
                    end

                    print("test clock done")
                end
            }

            local e1 = jfork {
                function()
                    clock1:posedge(5)

                    if is_verilator and is_inertial_put then
                        count:expect(5)
                        count1:expect(5)
                        count2:expect(4)
                    else
                        count:expect(6)
                        count1:expect(5)
                        count2:expect(4)
                    end

                    clock1:posedge(100)

                    reset1:set(1)
                    clock1:posedge()
                    reset1:set(0)
                    clock1:posedge()

                    if is_verilator then
                        count1:expect(0)
                        count2:expect_not(0)
                        count:expect_not(0)
                    else
                        count1:expect(1)
                        count2:expect_not(0)
                        count:expect_not(0)
                    end

                    print("test clock1 done")
                end
            }

            local e2 = jfork {
                function()
                    clock2:posedge(5)

                    if is_verilator and is_inertial_put then
                        count:expect(7)
                        count1:expect(7)
                        count2:expect(5)
                    else
                        count:expect(8)
                        count1:expect(7)
                        count2:expect(5)
                    end

                    clock2:posedge(100)

                    reset2:set(1)
                    clock2:posedge()
                    reset2:set(0)
                    clock2:posedge()

                    if is_verilator then
                        count2:expect(0)
                        count1:expect_not(0)
                        count:expect_not(0)
                    else
                        count2:expect(1)
                        count1:expect_not(0)
                        count:expect_not(0)
                    end

                    print("test clock2 done")
                end
            }

            join({ e, e1, e2 })
        end

        test_posedge()

        -- TODO: negedge

        -- Clock dependency test
        -- clock -> clock3 -> clock4
        fork {
            function()
                clock:posedge()
                while true do
                    clock3:set(1)
                    clock:posedge()
                    clock3:set(0)
                    clock:posedge()
                end
            end,
            function()
                clock3:posedge()
                while true do
                    clock4:set(1)
                    clock3:posedge()
                    clock4:set(0)
                    clock3:posedge()
                end
            end,
            function()
                clock3:posedge(10)
                count3:expect(9)
            end
        }

        local eclock = jfork {
            function()
                clock4:posedge(10)
                count4:expect(9)
            end,
        }

        join(eclock)

        sim.finish()
    end
}

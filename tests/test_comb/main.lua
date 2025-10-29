local clock = dut.clock:chdl()

local rvalid = dut.rvalid:chdl()
local rdata = dut.rdata:chdl()
local rresp = dut.rresp:chdl()
local step = dut.raddr:chdl()

if os.getenv("NO_INTERNAL_CLOCK") then
    fork {
        function()
            while true do
                clock:set(1)
                await_time(1)
                clock:set(0)
                await_time(1)
            end
        end
    }
end

fork {
    function()
        -- sim.dump_wave()

        dut.reset:set(1)
        clock:posedge(1)
        dut.reset:set(0)
        clock:posedge()

        fork {
            function()
                while true do
                    if rvalid:is(1) then
                        if step:is(2) then
                            rresp:set_imm(1)
                            rdata:set_imm(10)
                            clock:posedge()
                            rresp:set_imm(0)
                        end

                        if step:is(4) then
                            rresp:set_imm(1)
                            rdata:set_imm(20)
                            clock:posedge(2)
                            rresp:set_imm(0)
                        end
                    end

                    clock:posedge()
                    await_rw()
                end
            end
        }

        clock:posedge(10)
        sim.finish()
    end
}

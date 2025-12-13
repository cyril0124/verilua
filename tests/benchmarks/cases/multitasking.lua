if os.getenv("JIT_V") == "off" then
    jit.off()
end

local clock = dut.clock:chdl()

fork {
    function()
        clock:posedge()

        local cycles = 10000 * 10
        local _nr_task = os.getenv("NR_TASK") or "100"
        local nr_task = tonumber(_nr_task)

        for _ = 1, nr_task do
            fork {
                function()
                    while true do
                        clock:posedge()
                    end
                end
            }
        end

        clock:posedge(cycles)
        sim.finish()
    end
}

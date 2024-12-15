-- 
-- This is a pretty simple example, just read the signal values and print them.
-- 

fork {
    function()
        local clock = dut.clk:chdl()
        local count0 = dut.uut.count0:chdl()
        local count1 = dut.uut.count1:chdl()
        local count2 = dut.uut.count2:chdl()
        
        for i = 1, 100 do
            printf("count0: %d, count1: %d, count2: %d\n", count0:get(), count1:get(), count2:get())

            clock:posedge()
        end

        sim.finish()
    end
}
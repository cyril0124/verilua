local Monitor = require "Monitor"

verilua "appendTasks" {
    function ()
        -- Notice: be aware that signals are READ-ONLY when using @wave_vpi backend
        --         so we can't use the following code to reset the dut
        -- reset the dut
        -- dut.reset = 1
        -- dut.clock:posedge(10)
        -- dut.reset = 0
        dut.clock:posedge(10)

        -- create a monitor for monitoring the dut.count signal
        -- this monitor has been reused
        local monitor = Monitor("MonitorForWave", dut.count:chdl())
        monitor:start()

        -- run the simulation for 100 clock cycles
        dut.clock:posedge(100)

        -- finish the simulation
        sim.finish()
    end
}
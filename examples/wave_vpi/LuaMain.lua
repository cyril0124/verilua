local Monitor = require "Monitor"

verilua "appendTasks" {
    function ()
        -- dump wave file
        sim.dump_wave("./wave/test.vcd") -- wave file is stored in ./build/<simulator>/Counter/wave/test.vcd

        -- reset the dut
        dut.reset = 1
        dut.clock:posedge(10)
        dut.reset = 0

        -- create a monitor for monitoring the dut.count signal
        -- this Monitor will be reused when we simulate the generated wave file using @wave_vpi backend 
        local monitor = Monitor("MonitorForGenWave", dut.count:chdl())
        monitor:start()

        -- run the simulation for 100 clock cycles
        dut.clock:posedge(100)

        -- finish the simulation
        sim.finish()
    end
}
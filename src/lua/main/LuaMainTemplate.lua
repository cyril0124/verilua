--------------------------------
-- Setup package path
--------------------------------
local vl = require("Verilua")

--------------------------------
-- Required package
--------------------------------
require("LuaScheduler")
require("LuaDut")
require("LuaBundle")
require("LuaUtils")


--------------------------------
-- Initialization
--------------------------------
-- ...


--------------------------------
-- Print with cycles info (this will increase simulation time)
--------------------------------
local old_print = print
local print = function(...)
    old_print("[LuaMain] ", ...)
end


--------------------------------
-- Main body
--------------------------------
local function lua_main()
    await_posedge(dut.clock)

    dut.reset = 1
    for i=1, 20 do
        await_posedge(dut.clock)
    end
    dut.reset = 0

    await_posedge(dut.clock)

    local cycles = 0
    local clock_hdl = dut.clock:hdl()
    local loop = function()
        print("from main task cycles:" .. cycles)



        if cycles % 1000 == 0 and cycles ~= 0 then
            print(cycles, "Running...", os.clock())
            io.flush()
        end

        -- await_posedge(dut.clock)
        await_posedge_hdl(clock_hdl) -- higher performance
        cycles = cycles + 1
    end

    if cfg.enable_shutdown then
        for i = 0, cfg.shutdown_cycles do loop() end
    else
        while true do loop() end
    end

    print("Finish")
    sim.simulator_control(sim.SimCtrl.FINISH)
end

local function another_task() 


end

--------------------------------
-- Initialize scheduler task table
--------------------------------
vl.register_main_task(lua_main)
vl.register_tasks(
    {
        {"another_task", another_task, {}}
    }
)


--------------------------------
-- Lua side initialize
--------------------------------
vl.register_start_callback(
    function ()
        
    end
)


--------------------------------
-- Simulation finish callback
--------------------------------
vl.register_finish_callback(
    function ()

    end
)


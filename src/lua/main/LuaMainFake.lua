--------------------------------
-- Setup package path
--------------------------------
local vl = require("Verilua")


--------------------------------
-- Main body
--------------------------------
local function lua_main()

end


--------------------------------
-- Initialize scheduler task table
--------------------------------
vl.register_main_task(lua_main)


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

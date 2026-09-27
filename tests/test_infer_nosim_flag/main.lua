-- Build-only test targets: `main.lua` exists because the verilua rule requires
-- `verilua.lua_main`, but these targets are never run.
fork {
    function()
        sim.finish()
    end
}

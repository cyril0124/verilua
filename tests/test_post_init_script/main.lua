-- Assert VL_POST_INIT_SCRIPT ran before this main script was loaded.
do
    local order = rawget(_G, "__vl_boot_order")
    assert(type(order) == "table", "VL_POST_INIT_SCRIPT did not run before VL_LUA_SCRIPT")
    assert(order[1] == "post_init", "expected post_init first, got: " .. tostring(order[1]))
    table.insert(order, "main")
    assert(order[2] == "main")
    print("[test_post_init_script] boot order ok: post_init -> main")
end

fork {
    function()
        sim.finish()
    end,
}

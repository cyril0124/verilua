-- Assert VL_POST_INIT_SCRIPT ran before this main script was loaded.
do
    local order = rawget(_G, "__vl_boot_order")
    assert(type(order) == "table", "VL_POST_INIT_SCRIPT did not run before VL_LUA_SCRIPT")
    assert(order[1] == "post_init", "expected post_init first, got: " .. tostring(order[1]))
    table.insert(order, "main")
    assert(order[2] == "main")
    print("[test_post_init_script] boot order ok: post_init -> main")

    -- verilua xmake rule exports target name + build dir into runenvs.
    local target_name = os.getenv("VL_TARGET_NAME")
    assert(
        target_name == "test" or target_name == "test_code",
        "unexpected VL_TARGET_NAME: " .. tostring(target_name)
    )
    local build_dir = os.getenv("VL_BUILD_DIR")
    assert(type(build_dir) == "string" and build_dir ~= "", "VL_BUILD_DIR not set")
    assert(build_dir:find("/build/", 1, true), "unexpected VL_BUILD_DIR: " .. build_dir)
    print("[test_post_init_script] VL_TARGET_NAME=" .. target_name)
    print("[test_post_init_script] VL_BUILD_DIR=" .. build_dir)
end

fork {
    function()
        sim.finish()
    end,
}

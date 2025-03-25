target("test_counter")
    add_rules("verilua")
    add_toolchains("@verilator")

    add_files("env.lua")
    add_files("Counter.v")

    set_values("cfg.lua_main", "./test_counter.lua")
    set_values("cfg.top", "Counter")
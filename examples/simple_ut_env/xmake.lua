---@diagnostic disable: undefined-global, undefined-field

target("test_counter", function()
    add_rules("verilua")
    if os.getenv("SIM") == "iverilog" then
        add_toolchains("@iverilog")
    elseif os.getenv("SIM") == "vcs" then
        add_toolchains("@vcs")
    else
        add_toolchains("@verilator")
    end

    add_files("env.lua")
    add_files("Counter.v")

    set_values("cfg.lua_main", "./test_counter.lua")
    set_values("cfg.top", "Counter")
end)

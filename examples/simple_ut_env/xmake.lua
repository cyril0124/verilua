---@diagnostic disable: undefined-global, undefined-field

target("test_counter", function()
    add_rules("verilua")

    local sim = os.getenv("SIM") or "verilator"
    if sim == "iverilog" then
        add_toolchains("@iverilog")
    elseif sim == "vcs" then
        add_toolchains("@vcs")
    elseif sim == "xcelium" then
        add_toolchains("@xcelium")
    else
        add_toolchains("@verilator")
    end

    add_files("env.lua")
    add_files("Counter.v")

    set_values("cfg.lua_main", "./test_counter.lua")
    set_values("cfg.top", "Counter")
end)

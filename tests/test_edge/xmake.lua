target("top")
    add_rules("verilua")

    if os.getenv("SIM") == "vcs" then
        add_toolchains("@vcs")
    elseif os.getenv("SIM") == "iverilog" then
        add_toolchains("@iverilog")
    else
        add_toolchains("@verilator")
    end

    add_files("top.v")
    
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "./main.lua")

    set_values("verilator.flags", "--trace", "--no-trace-top")

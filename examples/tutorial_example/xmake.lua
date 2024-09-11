target("TestDesign")
    -- 1. add `veriluua` rule
    add_rules("verilua")

    -- 2. set toolchains, you can choose one of the following
    set_toolchains("@iverilog")
    -- set_toolchains("@verilator")
    -- set_toolchains("@vcs")

    -- 3. add files, including verilog and lua files(or C/C++ files)
    add_files(
        "./Design.v",
        "./LuaMain.lua"
    )

    -- 4. set configuration
    set_values("cfg.top", "Design") -- MANDATORY, set top module name
    set_values("cfg.lua_main", "./LuaMain.lua") -- MANDATORY, set lua main file

    -- 5. set the corresponding toolchain flags if required
    -- for iverilog
    -- set_values("iverilog.flags", "") -- build phase flags
    -- set_values("iverilog.run_options", "")
    -- set_values("iverilog.run_plusargs", "")
    -- set_values("iverilog.run_prefix", "")

    -- for verilator
    -- set_values("verilator.flags", "") -- build phase flags
    -- set_values("verilator.run_flags", "")
    -- set_values("verilator.run_prefix", "")

    -- for vcs
    -- set_values("vcs.flags", "") -- build phase flags
    -- set_values("vcs.run_flags", "")
    -- set_values("vcs.run_prefix", "")

    -- 6. build the testbench by `xmake build -P . TestDesign` where `-P .` is used to specify the project directory because the default project directory is the parent directory
    -- 7. run the simulation by `xmake run -P . TestDesign`
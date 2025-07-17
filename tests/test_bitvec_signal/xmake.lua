---@diagnostic disable

target("test_iverilog")
    add_rules("verilua")
    on_config(function (target)
        import("lib.detect.find_file")
        if find_file("iverilog", {"$(env PATH)"}) then
            target:set("toolchains", "@iverilog")
        end
    end)
    add_files("./Design.v")
    set_values("cfg.top", "Design")
    set_values("cfg.lua_main", "main.lua")

target("test_vcs")
    add_rules("verilua")
    on_config(function (target)
        import("lib.detect.find_file")
        if find_file("vcs", {"$(env PATH)"}) then
            target:set("toolchains", "@vcs")
        end
    end)
    add_files("./Design.v")
    set_values("cfg.top", "Design")
    set_values("cfg.lua_main", "main.lua")

target("test_verilator")
    add_rules("verilua")
    on_config(function (target)
        import("lib.detect.find_file")
        if find_file("verilator", {"$(env PATH)"}) then
            target:set("toolchains", "@verilator")
        end
    end)
    add_files("./Design.v")
    set_values("cfg.top", "Design")
    set_values("cfg.lua_main", "main.lua")

target("test_all")
    set_kind("phony")
    on_run(function (target)
        os.tryrm(path.join(os.scriptdir(), "build"))

        import("lib.detect.find_file")
        if find_file("verilator", {"$(env PATH)"}) then
            os.exec("xmake b -P . test_verilator")
            os.exec("xmake r -P . test_verilator")
        end
        if find_file("iverilog", {"$(env PATH)"}) then
            os.exec("xmake b -P . test_iverilog")
            os.exec("xmake r -P . test_iverilog")
        end
        if find_file("vcs", {"$(env PATH)"}) then
            os.exec("xmake b -P . test_vcs")
            os.exec("xmake r -P . test_vcs")
        end
    end)
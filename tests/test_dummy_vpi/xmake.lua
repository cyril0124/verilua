---@diagnostic disable: undefined-global, undefined-field

local prj_dir = os.scriptdir()

local function sim_name()
    return os.getenv("SIM") or "verilator"
end

target("test", function()
    set_kind("phony")

    on_build(function()
        import("lib.detect.find_file")

        local sim = sim_name()
        local dpi_exporter = find_file("dpi_exporter", { "$(env PATH)" })
        assert(dpi_exporter, "dpi_exporter not in PATH; build: xmake b dpi_exporter")

        local dpi_od = path.join(prj_dir, "build", "dpi_export")
        os.mkdir(dpi_od)
        os.execv(dpi_exporter, {
            "-c", path.join(prj_dir, "dpi_cfgs", "export.lua"),
            "--top", "tb_top",
            "--im", "top",
            "--tc", "clock",
            "--od", dpi_od,
            "--wd", dpi_od,
            "--no-cache",
            "-q",
            path.join(prj_dir, "tb_top.sv"),
            path.join(prj_dir, "top.sv"),
        })

        local dpi_func = path.join(dpi_od, "dpi_func.cpp")
        local tb = path.join(dpi_od, "tb_top.sv")
        local top = path.join(dpi_od, "top.sv")
        assert(os.isfile(dpi_func), "dpi_exporter did not write dpi_func.cpp")
        assert(os.isfile(tb), "dpi_exporter did not rewrite tb_top.sv")
        assert(os.isfile(top), "dpi_exporter did not rewrite top.sv")

        if sim == "verilator" then
            local vl_dpi = find_file("vl-verilator-dpi", { "$(env PATH)" })
            assert(vl_dpi, "vl-verilator-dpi not in PATH")
            os.execv(vl_dpi, {
                "--cc",
                "--exe",
                "--build",
                "-Mdir", path.join(prj_dir, "build", "sim_build_dpi"),
                "-j", "0",
                "-CFLAGS", "-std=c++20 -DDPI",
                "--Wno-WIDTHEXPAND",
                path.join(prj_dir, "verilator_main.cpp"),
                tb,
                top,
                dpi_func,
                "-o", "tb_top",
            })
        elseif sim == "vcs" then
            local vl_dpi = find_file("vl-vcs-dpi", { "$(env PATH)" })
            assert(vl_dpi, "vl-vcs-dpi not in PATH")
            local outdir = path.join(prj_dir, "build", "vcs")
            os.mkdir(outdir)
            local old = os.curdir()
            os.cd(outdir)
            os.execv(vl_dpi, {
                "-full64",
                "-sverilog",
                tb,
                top,
                dpi_func,
                "-o", "simv_dpi",
            })
            os.cd(old)
        else
            raise("test_dummy_vpi supports SIM=verilator|vcs, got: " .. sim)
        end
    end)

    on_run(function()
        local sim = sim_name()
        local bin
        if sim == "verilator" then
            bin = path.join(prj_dir, "build", "sim_build_dpi", "tb_top")
        elseif sim == "vcs" then
            bin = path.join(prj_dir, "build", "vcs", "simv_dpi")
        else
            raise("test_dummy_vpi supports SIM=verilator|vcs, got: " .. sim)
        end
        if not os.isfile(bin) then
            os.execv("xmake", { "build", "-P", prj_dir, "test" })
        end
        os.setenv("VL_CFG_FILE", path.join(prj_dir, "cfg.lua"))
        os.setenv("SIM", sim)
        if sim == "verilator" then
            os.setenv("VL_DUT_TOP", "TOP.tb_top")
        else
            os.setenv("VL_DUT_TOP", "tb_top")
        end
        assert(os.isfile(bin), "missing " .. bin)
        os.execv(bin, {})
    end)
end)

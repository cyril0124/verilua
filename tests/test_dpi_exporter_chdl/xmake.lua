---@diagnostic disable: undefined-global, undefined-field

local prj_dir = os.scriptdir()

target("test", function()
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "iverilog" then
            target:set("toolchains", "@iverilog")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    add_files("top.sv")
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "main.lua")

    -- Run dpi_exporter after tb_top is generated; swap rewritten RTL + dpi_func.cpp.
    set_values("before_build", function(target)
        import("lib.detect.find_file")

        local build_dir = assert(target:get("build_dir"), "build_dir missing")
        local dpi_cfg = path.join(prj_dir, "dpi_cfgs", "export.lua")
        assert(os.isfile(dpi_cfg), "dpi cfg not found: " .. dpi_cfg)

        local dpi_exporter = find_file("dpi_exporter", { "$(env PATH)" })
        assert(dpi_exporter, "dpi_exporter not in PATH; build: xmake b dpi_exporter")

        local dpi_od = path.join(build_dir, "dpi_export")
        os.mkdir(dpi_od)

        local rtl = path.absolute(path.join(prj_dir, "top.sv"))
        local argv = {
            "-c", dpi_cfg,
            "--top", "top",
            "--tc", "clock",
            "--od", dpi_od,
            "--wd", dpi_od,
            "--no-cache",
            "-q",
            rtl,
        }
        cprint("[test_dpi_exporter_chdl] running dpi_exporter...")
        os.execv(dpi_exporter, argv)

        local dpi_func = path.join(dpi_od, "dpi_func.cpp")
        local dpi_meta = path.join(dpi_od, "dpi_exporter.meta.json")
        assert(os.isfile(dpi_func), "dpi_exporter did not write dpi_func.cpp")
        assert(os.isfile(dpi_meta), "dpi_exporter did not write dpi_exporter.meta.json")

        -- Meta must use exportedSignalInfos (not old exportedSignals list).
        local meta = io.readfile(dpi_meta)
        assert(meta:find('"exportedSignalInfos"', 1, true), "meta missing exportedSignalInfos")
        assert(not meta:find('"exportedSignals"', 1, true), "meta still has exportedSignals")

        -- meta_only group (meta16) must be marked in meta and pinned via the
        -- generated public vlt (not needed by this flow -- the verilua rule
        -- defaults to public-flat-rw -- but the artifact must exist).
        assert(meta:find('"metaOnly": true', 1, true), "meta missing metaOnly:true entry")
        local dpi_vlt = path.join(dpi_od, "dpi_exporter.public.vlt")
        assert(os.isfile(dpi_vlt), "dpi_exporter did not write dpi_exporter.public.vlt")
        local vlt = io.readfile(dpi_vlt)
        assert(vlt:find('public_flat_rd -module "top" -var "meta16"', 1, true), "public vlt missing meta16 pin")

        local snapshot = {}
        for _, sourcefile in ipairs(target:sourcefiles()) do
            snapshot[#snapshot + 1] = sourcefile
        end
        for _, sourcefile in ipairs(snapshot) do
            local ext = path.extension(sourcefile)
            if ext == ".v" or ext == ".sv" or ext == ".svh" then
                local newfile = path.join(dpi_od, path.filename(sourcefile))
                if os.isfile(newfile) and path.absolute(sourcefile) ~= path.absolute(newfile) then
                    target:remove("files", sourcefile)
                    target:add("files", newfile)
                end
            end
        end

        target:add("files", dpi_func)
        cprint("[test_dpi_exporter_chdl] dpi export ready: ${green}%s${clear}", dpi_od)
    end)
end)

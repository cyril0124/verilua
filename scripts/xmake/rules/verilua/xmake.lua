
rule("verilua")
    set_extensions(".v", ".sv", ".lua", ".vlt", ".vcd", ".fst")
    
    on_load(function (target)
        local f = string.format

        -- Check if any of the valid toolchains is set. If not, raise an error.
        local sim
        if target:toolchain("verilator") ~= nil then
            sim = "verilator"
        elseif target:toolchain("iverilog") ~= nil then
            sim = "iverilog"
        elseif target:toolchain("vcs") ~= nil then
            sim = "vcs"
        elseif target:toolchain("wave_vpi") ~= nil then
            sim = "wave_vpi"
        else
            raise("[on_load] Unknown toolchain! Please use set_toolchains([\"verilator\", \"iverilog\", \"vcs\", \"wave_vpi\"]) to set a proper toolchain.") 
        end
        target:add("sim", sim)
        cprint("${✅} [verilua-xmake] simulator is ${green underline}%s${reset}", sim)

        -- Check if VERILUA_HOME is set.
        local verilua_home = assert(os.getenv("VERILUA_HOME"), "[on_load] please set VERILUA_HOME")
        target:add("verilua_home", verilua_home)
        target:add("includedirs", verilua_home .. "/src/include")
        target:add("links", "luajit-5.1", "fmt")
        if sim == "verilator" then
            target:add("links", "lua_vpi")
            target:add("files", verilua_home .. "/src/verilator/*.cpp")
        elseif sim == "vcs" then
            target:add("links", "lua_vpi_vcs", "stdc++")
        end

        -- Generate build directory 
        local top = assert(target:values("cfg.top"), "[on_load] You should set \'top\' by set_values(\"cfg.top\", \"<your_top_module>\")")
        local build_dir = path.absolute("build/" .. target:get("sim") .. "/" .. top)
        local sim_build_dir = build_dir .. "/sim_build"
        target:add("top", top)
        target:add("build_dir", build_dir)
        target:add("sim_build_dir", sim_build_dir)
        cprint("${✅} [verilua-xmake] top module is ${green underline}%s${reset}", top)

        if not os.isfile(sim_build_dir) then
            os.mkdir(sim_build_dir)
        end

        -- Copy lua main file into build_dir
        local lua_main
        local _lua_main = os.getenv("LUA_SCRIPT")
        if _lua_main ~= nil then
            lua_main = _lua_main
        else
            lua_main = assert(target:values("cfg.lua_main"), "[on_load] You should set \'cfg.lua_main\' by set_values(\"lua_main\", \"<your_lua_main_script>\")")
        end
        lua_main = path.absolute(lua_main)
        cprint("${✅} [verilua-xmake] lua main is ${green underline}%s${reset}", lua_main)

        os.cp(lua_main, build_dir)

        -- Copy other lua files into build_dir
        local sourcefiles = target:sourcefiles()
        for _, sourcefile in ipairs(sourcefiles) do
            if sourcefile:endswith(".lua") then
                os.cp(sourcefile, build_dir)
            end
        end

        -- Check verilua mode
        local mode = "normal"
        if sim ~= "wave_vpi" then
            local _mode = target:values("cfg.mode")
            if _mode ~= nil then
                assert(_mode == "normal" or _mode == "step" or _mode == "dominant", "[on_load] mode should be `normal`, `step` or `dominant`")
                mode = _mode
            end
            target:add("mode", mode)
        end
        cprint("${✅} [verilua-xmake] verilua mode is ${green underline}%s${reset}", mode)


        -- Generate verilua cfg file
        local tb_top = target:values("cfg.tb_top")
        local other_cfg = target:values("cfg.other_cfg")
        local other_cfg_path = "nil"
        local shutdown_cycles = target:values("cfg.shutdown_cycles")
        local deps = target:values("cfg.deps")
        local deps_str = ""

        if tb_top == nil then
            tb_top = "tb_top"
        end

        target:add("tb_top", tb_top)

        if other_cfg == nil or other_cfg == "" then
            other_cfg = "nil" 
        else
            local _other_cfg = other_cfg
            other_cfg = "\"" .. path.basename(other_cfg) .. "\""
            other_cfg_path = "\"" .. path.absolute(path.directory(_other_cfg)) .. "\""
            cprint("${✅} [verilua-xmake] other_cfg is ${green underline}%s${reset}", other_cfg)
        end

        if shutdown_cycles == nil then 
            shutdown_cycles = "10000 * 10" 
        end
        cprint("${✅} [verilua-xmake] shutdown_cycles is ${green underline}%s${reset}", shutdown_cycles)

        if deps ~= nil then
            if type(deps) == "table" then
                for _, dep in ipairs(deps) do
                    deps_str = deps_str .. "\"" .. path.absolute(dep) .. "\"" .. ",\n"
                    cprint("${✅} [verilua-xmake] deps is ${green underline}%s${reset}", dep)
                end
            else
                deps_str = "\"" .. path.absolute(deps) .. "\""
                cprint("${✅} [verilua-xmake] deps is ${green underline}%s${reset}", deps)
            end
        end

        local cfg_file = path.absolute(target:get("build_dir") .. "/verilua_cfg.lua")
        local cfg_file_str = f([[
local LuaSimConfig = require "LuaSimConfig"
local cfg = require "LuaBasicConfig"

local VeriluaMode = LuaSimConfig.VeriluaMode

cfg.top = os.getenv("DUT_TOP") or "%s"
cfg.prj_dir = os.getenv("PRJ_DIR") or "%s"
cfg.simulator = os.getenv("SIM") or "%s"
cfg.mode = VeriluaMode.%s
cfg.clock = cfg.top .. ".clock"
cfg.reset = cfg.top .. ".reset"
cfg.seed = os.getenv("SEED") or 101
cfg.attach = false
cfg.script = os.getenv("LUA_SCRIPT") or "%s"
cfg.srcs = {"./?.lua"}
cfg.deps = {
%s
}
cfg.other_cfg = %s
cfg.other_cfg_path = %s
cfg.period = 10
cfg.unit = "ns"
cfg.enable_shutdown = true
cfg.shutdown_cycles = os.getenv("SHUTDOWN_CYCLES") or %s
cfg.luapanda_debug = false
cfg.vpi_learn = false

-- Mix with other config
if cfg.other_cfg ~= nil then
    package.path = package.path .. ";" .. cfg.other_cfg_path .. "/?.lua"
    local _cfg = require(cfg.other_cfg)
    LuaSimConfig.CONNECT_CONFIG(_cfg, cfg)
end

return cfg
]], tb_top, os.getenv("PWD"), sim, mode:upper(), path.absolute(build_dir .. "/" .. path.basename(lua_main) .. ".lua"), deps_str, other_cfg, other_cfg_path, shutdown_cycles)
        io.writefile(cfg_file, cfg_file_str)
        target:add("cfg_file", cfg_file)

        if sim == "verilator" then
            -- Verilator flagsx
            local public_flat_rw = true
            
            -- Check if there is a verilator config file(*.vlt)
            for _, sourcefile in ipairs(sourcefiles) do
                if sourcefile:endswith(".vlt") then
                    public_flat_rw = false
                end
            end

            target:add(
                "values",
                "verilator.flags",
                "--vpi",
                "--cc",
                "--exe",
                "--build",
                "--MMD",
                "--no-timing",
                "-Mdir", sim_build_dir,
                "--x-assign", "unique",
                "-O3",
                "--Wno-PINMISSING", "--Wno-MODDUP", "--Wno-WIDTHEXPAND", "--Wno-WIDTHTRUNC", "--Wno-UNOPTTHREADS", "--Wno-IMPORTSTAR",
                "--timescale-override", "1ns/1ns",
                "+define+SIM_VERILATOR",
                "-CFLAGS \"-std=c++20 -O2 -funroll-loops -march=native\"",
                "-LDFLAGS \"-flto\"",
                "--top", tb_top
            )

            if public_flat_rw then
                target:add("values", "verilator.flags", "--public-flat-rw")
            end
        elseif sim == "iverilog" then
            target:add(
                "values",
                "iverilog.flags",
                "-g2012",
                "-DSIM_IVERILOG",
                "-D" .. mode:upper() .. "_MODE",
                "-s", tb_top,
                "-o", sim_build_dir .. "/simv.vvp"
            )
        elseif sim == "vcs" then
            local libpath = verilua_home .. "/shared"
            target:add(
                "values",
                "vcs.flags",
                "-sverilog",
                "-full64",
                "-debug_access+all",
                "-top", tb_top,
                "-Mdir=" .. sim_build_dir,
                "+v2k",
                "-lca",
                "-kdb",
                "-timescale=1ns/1ns",
                "+vcs+initreg+random",
                "+define+SIM_VCS",
                "+define+VCS",
                "+define+" .. mode:upper() .. "_MODE",
                "-q",
                "-CFLAGS \"-Ofast -march=native -loop-unroll\"",
                "-LDFLAGS \"-Wl,--no-as-needed -flto\"",
                "-load", libpath .. "/liblua_vpi_vcs.so",
                "-cc", "gcc",
                "-o", sim_build_dir .. "/simv"
            )
        elseif sim == "wave_vpi" then
            local get_waveform = false
            local waveform_file = ""
            for _, sourcefile in ipairs(sourcefiles) do
                if sourcefile:endswith(".vcd") or sourcefile:endswith(".fst") then
                    assert(get_waveform == false, "[on_load] Multiple waveform files are not supported")
                    get_waveform = true
                    waveform_file = path.absolute(sourcefile)
                end
            end
            assert(get_waveform, "[on_load] No waveform file found! Please use add_files to add waveform files (.vcd, .fst)")
            target:add("waveform_file", waveform_file)
        end

        target:set("kind", "binary")
    end)

    on_config(function (target)
        -- print("on_config")
    end)

    on_build(function (target)
        -- print("on_build")
        local f = string.format
        local verilua_home = assert(os.getenv("VERILUA_HOME"), "[on_build] please set VERILUA_HOME")
        local top = target:get("top")
        local build_dir = target:get("build_dir")
        local sim = target:get("sim")
        local tb_top = target:get("tb_top")
        local argv = {}
        local toolchain = ""
        local buildcmd = ""
        
        local flags = target:values(sim .. ".flags")
        if flags then
            table.join2(argv, flags)
        end

        -- Generate <tb_top>.sv
        local _not_gen_tb = target:values("cfg.not_gen_tb") -- Do not automatically generate testbench top
        local not_gen_tb = false
        if _not_gen_tb == "1" then
            not_gen_tb = true
        end
        if sim ~= "wave_vpi" and not not_gen_tb then
            local vfiles = {}
            local top_file = target:values("cfg.top_file") -- Top of the design, not the testbench top
            local file_str = ""
            if top_file == nil then
                for _, sourcefile in ipairs(target:sourcefiles()) do
                    if sourcefile:endswith(top .. ".v") or sourcefile:endswith(top .. ".sv") then
                        assert(top_file == nil, "[on_build] duplicate top_file! " .. sourcefile)
                        top_file = path.absolute(sourcefile)
                    end
                    if sourcefile:endswith(".v") or sourcefile:endswith(".sv") then
                        if sourcefile:endswith(tb_top .. ".sv") then
                            raise("<%s.sv> is already exist! %s", tb_top, path.absolute(sourcefile))
                        end
                        table.insert(vfiles, sourcefile)
                        file_str = file_str .. "-f " .. path.absolute(sourcefile) .. " "
                    end
                end
            end

            assert(top_file ~= nil, "[on_build] Cannot find top module file! top is " .. top .. " You should set \'top_file\' by set_values(\"cfg.top_file\", \"<your_top_module_file>\")")
            assert(os.isfile(top_file), "[on_build] Cannot find top module file! top_file is " .. top_file .. " You should set \'top_file\' by set_values(\"cfg.top_file\", \"<your_top_module_file>\")")
            assert(file_str ~= "", "[on_build] Cannot find any .v/.sv files!")
            print("top_file is " .. top_file)

            -- Only the vfiles are needed to be checked
            local tb_gen_flags = {"--top", top, "--tbtop", tb_top, "--nodpi", "--verbose", "--dir", build_dir}
            local _tb_gen_flags = target:values("cfg.tb_gen_flags")
            if _tb_gen_flags then
                tb_gen_flags = table.join2(tb_gen_flags, _tb_gen_flags)
            end
            local gen_cmd = f("python3 " .. verilua_home .. "/scripts/testbench_gen.py" .. " " .. table.concat(tb_gen_flags, " ") .. " " .. file_str)
            local is_generated = false
            local should_regenerate = true
            local input_tb_top_file = target:values("cfg.tb_top_file")
            if input_tb_top_file ~= nil then
                if os.isfile(input_tb_top_file) then
                    should_regenerate = false
                    input_tb_top_file = path.absolute(input_tb_top_file)
                else
                    raise("cfg.tb_top_file = " .. input_tb_top_file .. " is not a valid file!")
                end
            end

            if should_regenerate then
                for _, file in ipairs(vfiles) do
                    -- If any of the vfiles are changed, we should re-generate the testbench
                    if os.isfile(file) and os.mtime(file) > os.mtime(target:targetfile()) then
                        cprint("tb_gen_cmd: ${dim}%s${reset}", gen_cmd)
                        os.exec(gen_cmd)
                        is_generated = true
                        break
                    end
                end
                if not os.isfile(build_dir .. "/" .. tb_top ..".sv") and not is_generated then
                    cprint("tb_gen_cmd: ${dim}%s${reset}", gen_cmd)
                    os.exec(gen_cmd)
                    is_generated = true
                end
                target:add("files", build_dir .. "/" .. tb_top ..".sv", build_dir .. "/others.sv")
            else
                target:add("files", input_tb_top_file)
            end
        end


        if sim == "verilator" then
            toolchain = assert(target:toolchain("verilator"), '[on_build] we need to set_toolchains("@verilator") in target("%s")', target:name())
            buildcmd = try {
                function ()
                    return os.iorun("which verilator") 
                end
            }
            if not buildcmd then
                local has_which_cmd = try {
                    function ()
                        return os.iorun("command -v which")
                    end
                }

                if not has_which_cmd then
                    cprint("${❌} [verilua-xmake] [%s] ${color.error underline}which${reset color.error} command not found!${reset clear}", target:name())
                end

                cprint("${❌} [verilua-xmake] [%s] ${color.error underline}verilator${reset color.error} not found using `which`. Try getting ${underline}verilator${reset color.error} from toolchain... ${reset clear}", target:name())
                buildcmd = assert(toolchain:config("verilator"), "[on_build] verilator not found!")
            end

            local mode = target:get("mode")
            if mode == "normal" then
                table.insert(argv, "-CFLAGS")
                table.insert(argv, "-DNORMAL_MODE")
            elseif mode == "step" then
                table.insert(argv, "-CFLAGS")
                table.insert(argv, "-DSTEP_MODE")
            elseif mode == "dominant" then
                table.insert(argv, "-CFLAGS")
                table.insert(argv, "-DDOMINANT_MODE")
            end

            local includedirs = target:get("includedirs")
            for _, dir in ipairs(includedirs) do
                table.insert(argv, "-CFLAGS")
                table.insert(argv, "-I" .. path.absolute(dir))
            end

            local linkdirs = target:get("linkdirs")
            for _, dir in ipairs(linkdirs) do
                table.insert(argv, "-LDFLAGS")
                table.insert(argv, "-L" .. path.absolute(dir))
            end

            local links = target:get("links")
            for _, link in ipairs(links) do
                table.insert(argv, "-LDFLAGS")
                table.insert(argv, "-l" .. link)
            end
        elseif sim == "iverilog" then
            toolchain = assert(target:toolchain("iverilog"), '[on_build] we need to set_toolchains("@iverilog") in target("%s")', target:name())
            buildcmd = assert(toolchain:config("iverilog"), "[on_build] iverilog not found!")
            
            -- raise("TODO: iverilog")
        elseif sim == "vcs" then
            toolchain = assert(target:toolchain("vcs"), '[on_build] we need to set_toolchains("@vcs") in target("%s")', target:name())
            buildcmd = assert(toolchain:config("vcs"), "[on_build] vcs not found!")

            local includedirs = target:get("includedirs")
            for _, dir in ipairs(includedirs) do
                table.insert(argv, "-CFLAGS")
                table.insert(argv, "-I" .. path.absolute(dir))
            end

            local linkdirs = target:get("linkdirs")
            for _, dir in ipairs(linkdirs) do
                table.insert(argv, "-LDFLAGS")
                table.insert(argv, "-L" .. path.absolute(dir))
            end

            local links = target:get("links")
            for _, link in ipairs(links) do
                table.insert(argv, "-LDFLAGS")
                table.insert(argv, "-l" .. link)
            end
        elseif sim == "wave_vpi" then
            -- Do nothing
        else
            raise("Unknown simulator! => " .. tostring(sim))
        end

        cprint("${✅} [verilua-xmake] [%s] buildcmd is ${green underline}%s${reset}", target:name(), buildcmd)

        local sourcefiles = target:sourcefiles()
        local filelist_dut = {} -- only v/sv files
        local filelist_sim = {} -- including c/c++ files
        if sim ~= "wave_vpi" then
            for _, sourcefile in ipairs(sourcefiles) do
                cprint("${📄} read file ${green dim}%s${reset}", path.absolute(sourcefile))
                if not sourcefile:endswith(".lua") then
                    if sourcefile:endswith(".v") or sourcefile:endswith(".sv") then
                        table.insert(filelist_dut, path.absolute(sourcefile))                    
                    end
                    if sourcefile:endswith(".vlt") then
                        -- Ignore "*.vlt" file if current simulator is not verilator
                        if sim == "verilator" then
                            table.insert(filelist_sim, path.absolute(sourcefile))
                            table.insert(argv, path.absolute(sourcefile))
                        end
                    else
                        table.insert(filelist_sim, path.absolute(sourcefile))
                        table.insert(argv, path.absolute(sourcefile))
                    end
                end
            end

            -- Write filelist of this build
            io.writefile(build_dir .."/dut_file.f", table.concat(filelist_dut, '\n'))
            io.writefile(build_dir .."/sim_file.f", table.concat(filelist_sim, '\n'))
            -- table.insert(argv, "-f")
            -- table.insert(argv,  build_dir .. "/sim_file.f")

            -- Run the verilator command to generate target binary
            os.vrun(buildcmd .. " " .. table.concat(argv, " "))
        end

        -- Create a clean.sh + build.sh + run.sh that can be used by user to manually run the simulation
        local _runenvs = target:get("runenvs")
        local extra_runenvs = ""
        if _runenvs ~= nil then
          for key, value in pairs(_runenvs) do
            if key == "LD_LIBRARY_PATH" or key == "PATH" then
              extra_runenvs = extra_runenvs .. "export " .. key .. "=" .. value .. ":$" .. key .. "\n"
            else
              extra_runenvs = extra_runenvs .. "export " .. key .. "=" .. value .. "\n"
            end
          end
        end
        local setvars_sh = f([[#!/usr/bin/env bash
export VERILUA_CFG=%s
export SIM=%s
%s
]], target:get("cfg_file"), sim, extra_runenvs)
        io.writefile(build_dir .. "/setvars.sh", setvars_sh)

        local sim_build_dir = target:get("sim_build_dir")
        local clean_sh = f([[#!/usr/bin/env bash
source setvars.sh
rm -rf %s
]], sim_build_dir)
        io.writefile(build_dir .. "/clean.sh", clean_sh)

        local buildcmd_str = sim == "wave_vpi" and "# wave_vpi did not support build.sh \n#" or buildcmd:sub(1, -2) .. " " .. table.concat(argv, " ")
        local build_sh = f([[#!/usr/bin/env bash
source setvars.sh
%s 2>&1 | tee build.log
]], buildcmd_str)
        io.writefile(build_dir .. "/build.sh", build_sh)

        local run_sh = ""
        if sim == "verilator" then
            run_sh = f([[numactl -m 0 -C 0-7 %s/V%s 2>&1 | tee run.log]], sim_build_dir, tb_top)
        elseif sim == "vcs" then
            run_sh = f([[%s/simv +vcs+initreg+0 +notimingcheck 2>&1 | tee run.log]], sim_build_dir)
        elseif sim == "iverilog" then
            run_sh = f([[vvp_wrapper -M %s -m lua_vpi %s/simv.vvp | tee run.log]], verilua_home .. "/shared", sim_build_dir)
        elseif sim == "wave_vpi" then
            local waveform_file = assert(target:get("waveform_file"), "[on_build] waveform_file not found!")
            run_sh = f([[wave_vpi_main --wave-file %s 2>&1 | tee run.log]], waveform_file)
        end
        io.writefile(build_dir .. "/run.sh",       "#!/usr/bin/env bash\nsource setvars.sh\n" .. run_sh)
        io.writefile(build_dir .. "/debug_run.sh", "#!/usr/bin/env bash\nsource setvars.sh\n" .. "gdb --args " .. run_sh)

        local verdi_sh = [[#!/usr/bin/env bash
verdi -f filelist.f -sv -nologo $@
]]
        io.writefile(build_dir .. "/verdi.sh", verdi_sh)
        
        -- Copy the generated binary to targetdir
        local sim_build_dir = target:get("sim_build_dir")
        os.mkdir(target:targetdir())
        if sim == "verilator" then
            os.cp(sim_build_dir .. "/V" .. tb_top, target:targetdir())
            os.cp(sim_build_dir .. "/V" .. tb_top, target:targetdir() .. "/" .. target:name()) -- make xmake happy, otherwise it would fail to find the binary
        elseif sim == "iverilog" then
            os.cp(sim_build_dir .. "/simv.vvp", target:targetdir())
            os.cp(sim_build_dir .. "/simv.vvp", target:targetdir() .. "/" .. target:name()) -- make xmake happy, otherwise it would fail to find the binary
        elseif sim == "vcs" then
            os.cp(sim_build_dir .. "/simv", target:targetdir())
            os.cp(sim_build_dir .. "/simv", target:targetdir() .. "/" .. target:name()) -- make xmake happy, otherwise it would fail to find the binary
        elseif sim == "wave_vpi" then
            os.touch(target:targetdir() .. "/" .. target:name()) -- make xmake happy, otherwise it would fail to find the binary
        end
    end)

    on_clean(function (target)
        local build_dir = target:get("build_dir")
        if not os.isfile(build_dir) then
            os.rmdir(build_dir)
        end

        try {
            function ()
                if not os.isfile(target:targetdir()) then
                    os.rmdir(target:targetdir())
                end
            end
        }
    end)

    on_run(function (target)
        local sim = target:get("sim")
        local tb_top = target:get("tb_top")
        local build_dir = target:get("build_dir")
        local sim_build_dir = target:get("sim_build_dir")

        -- Set runtime envs
        local runenvs = target:get("runenvs")
        for k, env in pairs(runenvs) do
            local _env = {}
            if k == "LD_LIBRARY_PATH" or k == "PATH" then
                _env[k] = path.absolute(env)
            else
                _env[k] = env
            end
            os.addenvs(_env)
        end

        -- Set VERILUA_CFG for verilua
        os.setenv("VERILUA_CFG", target:get("cfg_file"))

        -- Move into build dircectory to execute our simulation
        os.cd(build_dir)
        if sim == "verilator" then
            local run_flags = {""}
            local _run_flags = target:values("verilator.run_flags")
            if _run_flags then
                table.join2(run_flags, _run_flags)
            end

            local run_prefix = {""}
            local _run_prefix = target:values("verilator.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end
            
            os.exec(table.concat(run_prefix, " ") .. " " .. sim_build_dir .. "/V" .. tb_top .. " " .. table.concat(run_flags, " "))
        elseif sim == "iverilog" then
            local verilua_home = os.getenv("VERILUA_HOME")
            local vvpcmd = verilua_home .. "/tools/vvp_wrapper"

            local run_flags = {"-M", verilua_home .. "/shared", "-m", "lua_vpi"}
            local _run_options = target:values("iverilog.run_options")
            local _run_plusargs = target:values("iverilog.run_plusargs")
            if _run_options then
                table.join2(run_flags, _run_options)
            end
            if _run_plusargs then
                table.join2(run_flags, _run_plusargs)
            end

            local run_prefix = {""}
            local _run_prefix = target:values("iverilog.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end

            assert(os.isfile(vvpcmd), "[on_run] verilua vvp_wrapper not found!")
            os.exec(table.concat(run_prefix, " ") .. " " .. vvpcmd .. " " .. table.concat(run_flags, " ") .. " " .. sim_build_dir .. "/simv.vvp")
        elseif sim == "vcs" then
            local run_flags = {"+vcs+initreg+0", "+notimingcheck"}
            local _run_flags = target:values("vcs.run_flags")
            if _run_flags then
                table.join2(run_flags, _run_flags)
            end

            local run_prefix = {""}
            local _run_prefix = target:values("vcs.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end
            
            os.exec(table.concat(run_prefix, " ") .. " " .. sim_build_dir .. "/simv " .. table.concat(run_flags, " "))
        elseif sim == "wave_vpi" then
            local toolchain = assert(target:toolchain("wave_vpi"), '[on_run] we need to set_toolchains("@wave_vpi") in target("%s")', target:name())
            local wave_vpi_main = assert(toolchain:config("wave_vpi"), "[on_run] wave_vpi_main not found!")
            local waveform_file = assert(target:get("waveform_file"), "[on_run] waveform_file not found!")

            local run_flags = {"--wave-file", waveform_file}
            local _run_flags = target:values("wave_vpi.run_flags")
            if _run_flags then
                table.join2(run_flags, _run_flags)
            end

            local run_prefix = {""}
            local _run_prefix = target:values("wave_vpi.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end

            os.exec(table.concat(run_prefix, " ") .. " " .. wave_vpi_main .. " " .. table.concat(run_flags, " "))
        else
            raise("TODO: on_run unknown simulaotr => " .. sim)
        end
    end)

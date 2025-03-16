---@diagnostic disable

local verilua_use_nix = os.getenv("VERILUA_USE_NIX") == "1" or false
local verilua_home = os.getenv("VERILUA_HOME") or "" -- verilua source code home
local verilua_tools_home = os.getenv("VERILUA_TOOLS_HOME") or (verilua_home .. "/tools")
local verilua_libs_home = os.getenv("VERILUA_LIBS_HOME") or (verilua_home .. "/shared")
local verilua_extra_cflags = os.getenv("VERILUA_EXTRA_CFLAGS") or ""
local verilua_extra_ldflags = os.getenv("VERILUA_EXTRA_LDFLAGS") or ""
local verilua_extra_vcs_ldflags = os.getenv("VERILUA_EXTRA_VCS_LDFLAGS") or ""
local luajitpro_home = os.getenv("LUAJITPRO_HOME") or (verilua_home .. "/luajit-pro/luajit2.1")

local function get_command_path(os, command)
    local command_path = os.iorun("which %s", command):gsub("[\r\n]", "")
    return command_path
end

local function before_build_or_run(target)
    local f = string.format
    local no_copy_lua = os.getenv("NO_COPY_LUA") ~= nil -- do not copy the lua files into the build directory, this is helpful for thread safety.

    -- Check if any of the valid toolchains is set. If not, raise an error.
    local sim
    if target:toolchain("verilator") ~= nil then
        sim = "verilator"
    elseif target:toolchain("iverilog") ~= nil then
        sim = "iverilog"
    elseif target:toolchain("vcs") ~= nil then
        sim = "vcs"
        
        local vcs_no_initreg = target:values("cfg.vcs_no_initreg") == "1"
        if vcs_no_initreg then
            target:add("vcs_no_initreg", true)
        end
    elseif target:toolchain("wave_vpi") ~= nil then
        sim = "wave_vpi"
    else
        raise("[before_build_or_run] Unknown toolchain! Please use set_toolchains([\"verilator\", \"iverilog\", \"vcs\", \"wave_vpi\"]) to set a proper toolchain.") 
    end

    target:add("sim", sim)
    cprint("${✅} [verilua-xmake] [%s] simulator is ${green underline}%s${reset}", target:name(), sim)

    -- Check if VERILUA_HOME is set.
    assert(verilua_home ~= "", "[before_build_or_run] [%s] please set VERILUA_HOME", target:name())

    -- Generate build directory 
    local top = assert(target:values("cfg.top"), "[before_build_or_run] You should set \'top\' by set_values(\"cfg.top\", \"<your_top_module>\")")
    local build_dir_name = target:values("cfg.build_dir_name") or top
    local build_dir_path = target:values("cfg.build_dir_path") or ("build/" .. target:get("sim"))
    local build_dir = target:values("cfg.build_dir") or path.absolute(build_dir_path .. "/" .. build_dir_name)
    local sim_build_dir = build_dir .. "/sim_build"
    target:add("top", top)
    target:add("build_dir", build_dir)
    target:add("sim_build_dir", sim_build_dir)
    cprint("${✅} [verilua-xmake] [%s] top module is ${green underline}%s${reset}", target:name(), top)
    cprint("${✅} [verilua-xmake] [%s] build directory is ${green underline}%s${reset}", target:name(), build_dir)

    if not os.isfile(sim_build_dir) then
        os.mkdir(sim_build_dir)
    end

    -- Extract dependencies from sourcefiles
    local deps_path_map = {}
    local deps_str = ""
    local sourcefiles = target:sourcefiles()
    for _, sourcefile in ipairs(sourcefiles) do
        if sourcefile:endswith(".lua") or sourcefile:endswith(".luau") or sourcefile:endswith(".tl") or sourcefile:endswith(".d.tl") then
            local dir = path.directory(path.absolute(sourcefile))
            if deps_path_map[dir] == nil then
                deps_path_map[dir] = true
                deps_str = deps_str .. dir .. "/?.lua;"
            end
        end
    end

    -- Save lua_main directory into deps_str
    local lua_main = path.absolute(os.getenv("LUA_SCRIPT") or assert(target:values("cfg.lua_main"), "[before_build_or_run] You should set \'cfg.lua_main\' by set_values(\"lua_main\", \"<your_lua_main_script>\")"))
    cprint("${✅} [verilua-xmake] [%s] lua main is ${green underline}%s${reset}", target:name(), lua_main)
    deps_str = deps_str .. path.directory(lua_main) .. "/?.lua;"

    -- Check verilua mode
    local mode = "normal"
    if sim ~= "wave_vpi" then
        local _mode = target:values("cfg.mode")
        if _mode ~= nil then
            assert(_mode == "normal" or _mode == "step" or _mode == "dominant", "[before_build_or_run] mode should be `normal`, `step` or `dominant`")
            mode = _mode
        end
        target:add("mode", mode)
    end
    cprint("${✅} [verilua-xmake] [%s] verilua mode is ${green underline}%s${reset}", target:name(), mode)


    -- Generate verilua cfg file
    local tb_top = target:values("cfg.tb_top") or "tb_top"
    local user_cfg = target:values("cfg.user_cfg") or target:values("cfg.other_cfg")
    local user_cfg_path = "nil"
    local shutdown_cycles = target:values("cfg.shutdown_cycles")

    target:add("tb_top", tb_top)

    if user_cfg == nil or user_cfg == "" then
        user_cfg = "nil" 
    else
        local _user_cfg = user_cfg
        user_cfg = "\"" .. path.basename(user_cfg) .. "\""
        user_cfg_path = "\"" .. path.absolute(path.directory(_user_cfg)) .. "\""
        cprint("${✅} [verilua-xmake] [%s] user_cfg is ${green underline}%s${reset}", target:name(), user_cfg)
    end

    if shutdown_cycles == nil then 
        shutdown_cycles = "10000 * 10" 
    end
    cprint("${✅} [verilua-xmake] [%s] shutdown_cycles is ${green underline}%s${reset}", target:name(), shutdown_cycles)


    local cfg_file = path.absolute(target:get("build_dir") .. "/verilua_cfg.lua")
    local cfg_file_str = f([[
local lua_cfg = require "LuaSimConfig"

local SchedulerMode = lua_cfg.SchedulerMode
local cfg = {}

cfg.top = os.getenv("DUT_TOP") or "%s"
cfg.prj_dir = os.getenv("PRJ_DIR") or "%s"
cfg.simulator = os.getenv("SIM") or "%s"
cfg.mode = SchedulerMode.%s
cfg.seed = os.getenv("SEED") or 101
cfg.script = os.getenv("LUA_SCRIPT") or "%s"
cfg.deps = {"%s"}
cfg.user_cfg = %s
cfg.user_cfg_path = %s
cfg.enable_shutdown = true
cfg.shutdown_cycles = os.getenv("SHUTDOWN_CYCLES") or %s

-- Mix with other config
if cfg.user_cfg ~= nil then
    _G.package.path = _G.package.path .. ";" .. cfg.user_cfg_path .. "/?.lua"
    local _cfg = require(cfg.user_cfg)
    assert(type(_cfg) == "table", "cfg is not a table! => type(cfg): " .. type(_cfg) .. " cfg: " .. tostring(_cfg) .. " cfg_path: " .. tostring(cfg.user_cfg_path) .. " cfg_name: " .. tostring(cfg.user_cfg))

    lua_cfg.merge_config_1(cfg, _cfg, "[xmake.lua -> verilua_cfg.lua]")
end

return cfg
]], tb_top, os.getenv("PWD"), sim, mode:upper(), lua_main, deps_str, user_cfg, user_cfg_path, shutdown_cycles)
    if os.isfile(cfg_file) and io.readfile(cfg_file) == cfg_file_str then
        cprint("${✅} [verilua-xmake] [%s] verilua_cfg.lua is up-to-date", target:name())
    else
        io.writefile(cfg_file, cfg_file_str)
    end

    target:add("cfg_file", cfg_file)

    if sim == "wave_vpi" then
        local get_waveform = false
        local waveform_file = ""
        for _, sourcefile in ipairs(sourcefiles) do
            if sourcefile:endswith(".vcd") or sourcefile:endswith(".fst") or sourcefile:endswith(".fsdb") then
                assert(get_waveform == false, "[before_build_or_run] Multiple waveform files are not supported")
                get_waveform = true
                waveform_file = path.absolute(sourcefile)
            end
        end
        if waveform_file ~= "" then
            target:add("waveform_file", waveform_file)
        end
    end

    target:set("kind", "binary")
end

rule("verilua")
    set_extensions(".v", ".sv", ".svh", ".lua", ".luau", ".tl", ".d.tl", ".vlt", ".vcd", ".fst", ".fsdb")

    before_build(before_build_or_run)
    
    before_run(before_build_or_run)

    on_build(function (target)
        assert(verilua_home ~= "", "[on_build] [%s] please set VERILUA_HOME", target:name())

        local f = string.format
        local top = target:get("top")
        local build_dir = target:get("build_dir")
        local sim_build_dir = build_dir .. "/sim_build"
        local sim = target:get("sim")
        local mode = target:get("mode")
        local tb_top = target:get("tb_top")
        local sourcefiles = target:sourcefiles()
        local argv = {}
        local toolchain = ""
        local buildcmd = ""

        if sim == "verilator" then
            -- Verilator flags
            local public_flat_rw = true
            
            -- Check if there is a verilator config file(*.vlt)
            for _, sourcefile in ipairs(sourcefiles) do
                if sourcefile:endswith(".vlt") then
                    public_flat_rw = false
                end
            end

            local verilator_opt = "-O3" -- Enables slow optimizations for the code Verilator itself generates. -O3 may improve simulation performance at the cost of compile time.
            for _, flag in ipairs(target:values("verilator.flags")) do
                if flag == "-O0" then
                    verilator_opt = "-O0"
                    break
                end
            end

            local debug_cflags = "" -- "-O0 -g" -- for debug, but slower
            verilua_extra_cflags = debug_cflags .. " " ..  verilua_extra_cflags

            target:add(
                "values",
                "verilator.flags",
                "--vpi",
                "--cc",
                "--exe",
                -- "--build", -- Verilator will call make itself. This is we don’t need to manually call make as a separate step.
                "--MMD",
                "--no-timing",
                "-Mdir", sim_build_dir,
                "--x-assign unique",
                verilator_opt,
                "-j 0", -- Verilate using use as many CPU threads as the machine has.
                "--Wno-PINMISSING", "--Wno-MODDUP", "--Wno-WIDTHEXPAND", "--Wno-WIDTHTRUNC", "--Wno-UNOPTTHREADS", "--Wno-IMPORTSTAR",
                "--timescale-override", "1ns/1ns",
                "+define+SIM_VERILATOR",
                f("-CFLAGS \"-std=c++20 %s\"", verilua_extra_cflags),
                "-LDFLAGS \"-flto " .. verilua_extra_ldflags .. "\"",
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
            local has_which_cmd = try { function () return os.iorun("which which") end }
            local vcs_cc = has_which_cmd and get_command_path(os, "gcc") or ""
            local vcs_cpp = has_which_cmd and get_command_path(os, "g++") or ""
            local vcs_ld = has_which_cmd and get_command_path(os, "g++") or ""

            local custom_toolchain_str = ""
            if vcs_cc ~= "" then
                custom_toolchain_str = custom_toolchain_str .. " -cc " .. vcs_cc
            end
            if vcs_cpp ~= "" then
                custom_toolchain_str = custom_toolchain_str .. " -cpp " .. vcs_cpp
            end
            if vcs_ld ~= "" then
                custom_toolchain_str = custom_toolchain_str .. " -ld " .. vcs_ld
            end

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
                "-j" .. tostring((os.cpuinfo().ncpu or 128)),
                "-timescale=1ns/1ns",
                (function () if target:get("vcs_no_initreg") then return "" else return "+vcs+initreg+random" end end)(),
                "+define+SIM_VCS",
                "+define+VCS",
                "+define+" .. mode:upper() .. "_MODE",
                "-q",

                custom_toolchain_str,

                "-CFLAGS \"-Ofast -march=native -loop-unroll " .. verilua_extra_cflags .. "\"",
                "-LDFLAGS \"-flto -Wl,--no-as-needed\"",
                "-LDFLAGS \"" .. verilua_extra_vcs_ldflags .. "\"",
                (verilua_extra_ldflags == "") and "" or "-LDFLAGS \"" .. verilua_extra_ldflags .. "\"",
                f("-LDFLAGS \"-Wl,-rpath,%s\"", verilua_libs_home), -- for libverilua_vcs.so
                f("-LDFLAGS \"-Wl,-rpath,%s/luajit-pro/luajit2.1/lib\"", verilua_home), -- for libluajit-5.1.so
                f("-LDFLAGS \"-L%s/luajit-pro/luajit2.1/lib -lluajit-5.1 -lverilua_vcs\"", verilua_home),
                "-LDFLAGS \"-lz\"", -- libz is used by VERDI
               
                -- These flags are provided by `default.nix`
                -- "-LDFLAGS \"-Wl,-rpath,/nix/store/pkl664rrz6vb95piixzfm7qy1yc2xzgc-zlib-1.3.1/lib\"",
                -- "-LDFLAGS\"-Wl,-rpath,/nix/store/c10zhkbp6jmyh0xc5kd123ga8yy2p4hk-glibc-2.39-52/lib -Wl,-rpath,/nix/store/c10zhkbp6jmyh0xc5kd123ga8yy2p4hk-glibc-2.39-52/lib64 -Wl,-rpath,/nix/store/swcl0ynnia5c57i6qfdcrqa72j7877mg-gcc-13.2.0-lib/lib\"",

                "-load " .. verilua_libs_home .. "/libverilua_vcs.so",
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
            if waveform_file ~= "" then
                target:add("waveform_file", waveform_file)
            end
        end
        
        local flags = target:values(sim .. ".flags")
        if flags then
            table.join2(argv, flags)
        end

        -- Add extra includedirs and link flags
        target:add("includedirs", 
            luajitpro_home .. "/include",
            luajitpro_home .. "/include/luajit-2.1",
            verilua_home .. "/src/include"
        )
        target:add("links", "luajit-5.1")
        target:add("linkdirs", luajitpro_home .. "/lib", verilua_libs_home)
        
        if not verilua_use_nix then
            target:add("linkdirs", verilua_home .. "/vcpkg_installed/x64-linux/lib")
            target:add("includedirs", verilua_home .. "/vcpkg_installed/x64-linux/include")
        end

        if sim == "verilator" then
            target:add("links", "verilua_verilator")
            target:add("files", verilua_home .. "/src/verilator/*.cpp")
        elseif sim == "vcs" then
            -- If you are entering a C++ file or an object file compiled from a C++ file on 
            -- the vcs command line, you must tell VCS to use the standard C++ library for 
            -- linking. To do this, enter the -lstdc++ linker flag with the -LDFLAGS elaboration 
            -- option.
            target:add("links", "verilua_vcs", "stdc++")
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
            local has_top_file_cfg = top_file ~= nil
            local file_str = ""
            for _, sourcefile in ipairs(target:sourcefiles()) do
                if sourcefile:endswith(top .. ".v") or sourcefile:endswith(top .. ".sv") then
                    if not has_top_file_cfg then
                        assert(top_file == nil, "[on_build] duplicate top_file! " .. sourcefile)
                        top_file = path.absolute(sourcefile)
                    end
                end
                if sourcefile:endswith(".v") or sourcefile:endswith(".sv") or sourcefile:endswith(".svh") then
                    if sourcefile:endswith(tb_top .. ".sv") then
                        raise("<%s.sv> is already exist! %s", tb_top, path.absolute(sourcefile))
                    end
                    table.insert(vfiles, sourcefile)
                    file_str = file_str .. " " .. path.absolute(sourcefile)
                end
            end

            assert(top_file ~= nil, "[on_build] Cannot find top module file! top is %s You should set \'top_file\' by set_values(\"cfg.top_file\", \"<your_top_module_file>\")", top)
            assert(os.isfile(top_file), "[on_build] Cannot find top module file! top_file is " .. top_file .. " You should set \'top_file\' by set_values(\"cfg.top_file\", \"<your_top_module_file>\")")
            assert(file_str ~= "", "[on_build] Cannot find any .v/.sv files!")
            print("top_file is " .. top_file)

            -- Only the vfiles are needed to be checked
            local tb_gen_flags = {"--top", top, "--tbtop", tb_top, "--nodpi", "--verbose", "--out-dir", build_dir}
            local _tb_gen_flags = target:values("cfg.tb_gen_flags")
            if _tb_gen_flags then
                tb_gen_flags = table.join2(tb_gen_flags, _tb_gen_flags)
            end
            local gen_cmd = f(verilua_tools_home .. "/testbench_gen" .. " " .. table.concat(tb_gen_flags, " ") .. " " .. file_str)
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
                local has_testbench_gen = try { function () return os.iorun("which testbench_gen") end }
                if not has_testbench_gen then
                    raise("[on_build] Cannot find `testbench_gen`! You should build `testbench_gen` in `verilua` root directory via `xmake build testbench_gen`")
                end

                for _, file in ipairs(vfiles) do
                    -- If any of the vfiles are changed, we should re-generate the testbench
                    if os.isfile(file) and os.mtime(file) > os.mtime(target:targetfile()) then
                        cprint("testbench_gen cmd: ${dim}%s${reset}", gen_cmd)
                        os.exec(gen_cmd)
                        is_generated = true
                        break
                    end
                end
                if not os.isfile(build_dir .. "/" .. tb_top ..".sv") and not is_generated then
                    cprint("testbench_gen cmd: ${dim}%s${reset}", gen_cmd)
                    os.exec(gen_cmd)
                    is_generated = true
                end
                target:add("files", build_dir .. "/" .. tb_top ..".sv", build_dir .. "/others.sv")
            else
                target:add("files", input_tb_top_file)
            end
        end

        local has_which_cmd = try { function () return os.iorun("which which") end }
        if not has_which_cmd then
            cprint("${❌} [verilua-xmake] [%s] ${color.error underline}which${reset color.error} command not found!${reset clear}", target:name())
        end

        if sim == "verilator" then
            toolchain = assert(target:toolchain("verilator"), '[on_build] we need to set_toolchains("@verilator") in target("%s")', target:name())
            buildcmd = try { function () return os.iorun("which verilator") end } or assert(toolchain:config("verilator"), "[on_build] verilator not found!")

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

            local linkdirs, rpathdirs = target:get("linkdirs"), target:get("rpathdirs")
            for _, dir in ipairs(linkdirs) do
                table.insert(argv, "-LDFLAGS \"-L" .. path.absolute(dir) .. "\"")
            end
            for _, dir in ipairs(rpathdirs) do
                table.insert(argv, "-LDFLAGS \"-Wl,-rpath," .. path.absolute(dir) .. "\"")
            end

            local links = target:get("links")
            for _, link in ipairs(links) do
                table.insert(argv, "-LDFLAGS")
                table.insert(argv, "-l" .. link)
            end
        elseif sim == "iverilog" then
            toolchain = assert(target:toolchain("iverilog"), '[on_build] we need to set_toolchains("@iverilog") in target("%s")', target:name())
            buildcmd = try { function () return os.iorun("which iverilog")  end } or assert(toolchain:config("iverilog"), "[on_build] iverilog not found!")

        elseif sim == "vcs" then
            toolchain = assert(target:toolchain("vcs"), '[on_build] we need to set_toolchains("@vcs") in target("%s")', target:name())
            buildcmd = try { function () return os.iorun("which vcs")  end } or assert(toolchain:config("vcs"), "[on_build] vcs not found!")

            local includedirs = target:get("includedirs")
            for _, dir in ipairs(includedirs) do
                table.insert(argv, "-CFLAGS")
                table.insert(argv, "-I" .. path.absolute(dir))
            end

            local linkdirs, rpathdirs = target:get("linkdirs"), target:get("rpathdirs")
            for _, dir in ipairs(linkdirs) do
                table.insert(argv, "-LDFLAGS \"-L" .. path.absolute(dir) .. "\"")
            end
            for _, dir in ipairs(rpathdirs) do
                table.insert(argv, "-LDFLAGS \"-Wl,-rpath," .. path.absolute(dir) .. "\"")
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
                local abs_sourcefile = path.absolute(sourcefile)
                cprint("${📄} read file ${green dim}%s${reset}", abs_sourcefile)
                if not sourcefile:endswith(".lua") and not sourcefile:endswith(".luau") and not sourcefile:endswith(".tl") and not sourcefile:endswith(".d.tl") then
                    if sourcefile:endswith(".vlt") then
                        -- Ignore "*.vlt" file if current simulator is not verilator
                        if sim == "verilator" then
                            table.insert(filelist_sim, abs_sourcefile)
                            table.insert(argv, abs_sourcefile)
                        end
                    elseif sourcefile:endswith(".v") or sourcefile:endswith(".sv") or sourcefile:endswith(".svh") then
                        table.insert(filelist_dut, abs_sourcefile)
                        table.insert(filelist_sim, abs_sourcefile)
                    else
                        table.insert(filelist_sim, abs_sourcefile)
                        table.insert(argv, abs_sourcefile)
                    end
                end
            end

            if #filelist_dut >= 200 then
                -- filelist_dut is too long, pass a filelist to simulator 
                table.insert(argv, "-f " .. build_dir .. "/dut_file.f")
            else
                table.join2(argv, filelist_dut) 
            end

            -- Write filelist of this build
            io.writefile(build_dir .."/dut_file.f", table.concat(filelist_dut, '\n'))
            io.writefile(build_dir .."/sim_file.f", table.concat(filelist_sim, '\n'))

            -- Run the build command to generate target binary
            os.vrun(buildcmd .. " " .. table.concat(argv, " ")) -- , {envs = {LD_LIBRARY_PATH = "/nix/store/c10zhkbp6jmyh0xc5kd123ga8yy2p4hk-glibc-2.39-52/lib:/nix/store/c10zhkbp6jmyh0xc5kd123ga8yy2p4hk-glibc-2.39-52/lib64"}})
            if sim == "verilator" then
                local user_opt_slow = target:values("verilator.opt_slow")
                local user_opt_fast = target:values("verilator.opt_fast")
                assert(type(user_opt_slow) == "nil" or type(user_opt_slow) == "string", "verilator.opt_slow must be a string")
                assert(type(user_opt_fast) == "nil" or type(user_opt_fast) == "string", "verilator.opt_fast must be a string")

                local nproc = os.cpuinfo().ncpu or 128
                local sim_build_dir = build_dir .. "/sim_build"
                local tb_top_mk = sim_build_dir .. "/V" .. tb_top .. ".mk"

                local opt_slow = user_opt_slow or "-O0" -- OPT_SLOW applies to slow-path code, which rarely executes, often only once at the beginning or end of the simulation.
                local opt_fast = user_opt_fast or "-O3 -march=native" -- OPT_FAST specifies optimization options for those parts of the model on the fast path.
                                                                      -- This is mostly code that is executed every cycle.
                
                -- TODO: consider PGO optimization
                os.cd(sim_build_dir)
                os.vrun("make -j%d VM_PARALLEL_BUILDS=1 OPT_SLOW=\"%s\" OPT_FAST=\"%s\" -C %s -f %s", nproc, opt_slow, opt_fast, sim_build_dir, tb_top_mk)
                os.cd(os.curdir())
            end
        end

        -- 
        -- Create a clean.sh + build.sh + run.sh + prebuild.sh that can be used by user to manually run the simulation
        -- 
        -- Save the current environment variables
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
        
        io.printf(build_dir .. "/setvars.sh", 
[[#!/usr/bin/env bash
export VERILUA_CFG=%s
export SIM=%s
%s]], target:get("cfg_file"), sim, extra_runenvs)

        local sim_build_dir = target:get("sim_build_dir")
        io.printf(build_dir .. "/clean.sh", 
[[#!/usr/bin/env bash
source setvars.sh
rm -rf %s]], sim_build_dir)

        local buildcmd_str = sim == "wave_vpi" and "# wave_vpi did not support build.sh \n#" or buildcmd:sub(1, -2) .. " " .. table.concat(argv, " ")
        io.printf(build_dir .. "/build.sh", 
[[#!/usr/bin/env bash
source setvars.sh
%s 2>&1 | tee build.log]], buildcmd_str)

        local run_sh = ""
        if sim == "verilator" then
            run_sh = f([[numactl -m 0 -C 0-7 %s/V%s 2>&1 | tee run.log]], sim_build_dir, tb_top)
        elseif sim == "vcs" then
            run_sh = f([[%s/simv %s +notimingcheck 2>&1 | tee run.log]], sim_build_dir, (function() if target:get("vcs_no_initreg") then return "" else return "+vcs+initreg+0" end end)())
        elseif sim == "iverilog" then
            run_sh = f([[vvp_wrapper -M %s -m libverilua_iverilog %s/simv.vvp | tee run.log]], verilua_libs_home, sim_build_dir)
        elseif sim == "wave_vpi" then
            local waveform_file = assert(target:get("waveform_file"), "[on_build] waveform_file not found! Please use add_files to add waveform files (.vcd, .fst)")
            run_sh = f([[wave_vpi_main --wave-file %s 2>&1 | tee run.log]], waveform_file)
        end
        io.writefile(build_dir .. "/run.sh",       "#!/usr/bin/env bash\nsource setvars.sh\n" .. run_sh)
        io.writefile(build_dir .. "/debug_run.sh", "#!/usr/bin/env bash\nsource setvars.sh\n" .. "gdb --args " .. run_sh)

        io.printf(build_dir .. "/prebuild.sh",
[[#!/usr/bin/env bash
source setvars.sh
verilua_prebuild -f %s]], build_dir .."/dut_file.f")

        io.writefile(build_dir .. "/verdi.sh", 
[[#!/usr/bin/env bash
verdi -f filelist.f -sv -nologo $@]])
        
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
            if verilua_use_nix then
                -- Bug: undefined symbol: __tunable_is_initialized, version GLIBC_PRIVATE ==> patchelf --set-interpreter /nix/store/c10zhkbp6jmyh0xc5kd123ga8yy2p4hk-glibc-2.39-52/lib64/ld-linux-x86-64.so.2 simv
                local vl_patchelf_full_path = os.iorun("which vl-patchelf"):gsub("[\r\n]", "")
                local ld_linux_so = os.iorun("vl-patchelf --print-interpreter %s", vl_patchelf_full_path):gsub("[\r\n]", "")
                os.exec("vl-patchelf --set-interpreter %s %s", ld_linux_so, sim_build_dir .. "/simv") 
            end

            os.cp(sim_build_dir .. "/simv", target:targetdir())
            os.cp(sim_build_dir .. "/simv", target:targetdir() .. "/" .. target:name()) -- make xmake happy, otherwise it would fail to find the binary
        elseif sim == "wave_vpi" then
            os.touch(target:targetdir() .. "/" .. target:name()) -- make xmake happy, otherwise it would fail to find the binary
        end
    end) -- on_build

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
    end) -- on_clean

    on_run(function (target)
        assert(verilua_home ~= "", "[on_run] [%s] please set VERILUA_HOME", target:name())

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
            local vvpcmd = verilua_tools_home .. "/vvp_wrapper"

            local run_flags = {"-M", verilua_libs_home, "-m", "libverilua_iverilog"}
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
            local run_flags = {(function() if target:get("vcs_no_initreg") then return "" else return "+vcs+initreg+0" end end)(), "+notimingcheck"}
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
            local waveform_file = assert(target:get("waveform_file"), "[on_run] waveform_file not found! Please use add_files to add waveform files (.vcd, .fst)")

            local wave_vpi_main 
            do 
                if waveform_file:endswith(".fsdb") then
                    wave_vpi_main = try{ function() return os.iorun("which wave_vpi_main_fsdb") end }
                    assert(wave_vpi_main, "[on_run] wave_vpi_main_vcs is not defined!")
                else
                    wave_vpi_main = try{ function() return os.iorun("which wave_vpi_main") end }
                    if not wave_vpi_main then
                        local toolchain = assert(target:toolchain("wave_vpi"), '[on_run] we need to set_toolchains("@wave_vpi") in target("%s")', target:name())
                        wave_vpi_main = assert(toolchain:config("wave_vpi"), "[on_run] wave_vpi_main not found!")
                    end
                end
            end

            print("[%s] wave_vpi_main: %s", target:name(), wave_vpi_main)

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
            raise("TODO: [on_run] unknown simulaotr => " .. sim)
        end
    end) -- on_run

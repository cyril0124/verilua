---@diagnostic disable: undefined-global, undefined-field

local prj_dir  = os.curdir()
local libs_dir = path.join(prj_dir, "conan_installed")

includes(path.join(prj_dir, "libverilua", "xmake.lua"))
includes(path.join(prj_dir, "src", "cov_exporter", "xmake.lua"))
includes(path.join(prj_dir, "src", "dpi_exporter", "xmake.lua"))
includes(path.join(prj_dir, "src", "signal_db_gen", "xmake.lua"))
includes(path.join(prj_dir, "src", "testbench_gen", "xmake.lua"))
includes(path.join(prj_dir, "src", "wave_vpi", "xmake.lua"))

target("update_submodules", function()
    set_kind("phony")
    on_run(function(target)
        os.exec("git submodule update --init --recursive")
    end)
end)

target("install_luajit", function()
    set_kind("phony")
    on_run(function(target)
        local curr_dir = os.projectdir()
        local luajit_pro_dir = path.join(curr_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")
        local luarocks_version = "3.12.2"

        -- Remove existing luajit-pro directory
        os.exec("rm -rf " .. luajit_pro_dir)
        os.exec("git clone https://github.com/cyril0124/luajit-pro.git " .. luajit_pro_dir)

        -- Build luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("git submodule update --init")
        os.exec("cargo build --release")

        -- Build luajit
        os.exec("bash init.sh")
        os.trycp(path.join(luajit_dir, "bin", "luajit"), path.join(luajit_dir, "bin", "lua"))

        -- Add luajit to PATH
        os.addenvs({ PATH = path.join(luajit_dir, "bin") })

        -- Build luarocks
        do
            os.exec(
                "wget -P %s https://luarocks.github.io/luarocks/releases/luarocks-%s.tar.gz",
                luajit_pro_dir,
                luarocks_version
            )
            os.exec("tar -zxvf luarocks-%s.tar.gz", luarocks_version)
            os.cd("luarocks-" .. luarocks_version)

            os.exec("make clean")
            os.exec("./configure --with-lua=%s --prefix=%s", luajit_dir, luajit_dir)
            os.exec("make")
            os.exec("make install")
        end

        -- Rebuild luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("cargo build --release")

        os.cd(curr_dir)
    end)
end)

target("reinstall_luajit", function()
    set_kind("phony")
    on_run(function(target)
        local curr_dir = os.workingdir()
        local luajit_pro_dir = path.join(curr_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")

        -- build luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("cargo build --release")

        -- execute("git reset --hard origin/master")
        -- execute("git pull origin master")
        os.exec("bash init.sh")
        os.trycp(path.join(luajit_dir, "bin", "luajit"), path.join(luajit_dir, "bin", "lua"))

        os.cd(curr_dir)
    end)
end)

target("install_other_libs", function()
    set_kind("phony")
    on_run(function(target)
        -- Environment variable `CI_USE_CONAN_CACHE` is set by `.github/workflows/regression.yml`(Check conan libs)
        if os.getenv("CI_USE_CONAN_CACHE") then
            print("[xmake.lua] [install_other_libs] Using cached conan libs...")
            return
        end

        local conan_cmd = "conan"
        local has_conan = try { function() return os.iorun("conan --version") end }

        if not has_conan then
            os.mkdir(path.join(prj_dir, "build"))
            os.cd(path.join(prj_dir, "build"))
            os.exec("wget https://github.com/conan-io/conan/releases/download/2.14.0/conan-2.14.0-linux-x86_64.tgz")
            os.mkdir("./conan")
            os.exec("tar -xvf conan-2.14.0-linux-x86_64.tgz -C ./conan")
            conan_cmd = path.join(prj_dir, "build", "conan", "bin", "conan")
        end

        os.cd(path.join(prj_dir, "scripts", "conan", "slang"))
        try {
            function()
                os.exec(conan_cmd .. " create . --build=missing")
            end,
            catch
            {
                function(errors)
                    os.exec(conan_cmd .. " profile detect --force")
                    os.exec(conan_cmd .. " create . --build=missing")
                end
            }
        }

        os.cd(prj_dir)
        os.exec(conan_cmd .. " install . --output-folder=%s --build=missing", libs_dir)
    end)
end)

target("install_lua_modules", function()
    set_kind("phony")
    on_run(function(target)
        local curr_dir = os.workingdir()
        local luajit_pro_dir = path.join(curr_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")
        local libs = {
            "penlight",
            "luasocket",
            -- "lsqlite3",
            "linenoise",
            "argparse", -- Used by teal-language
            "cluacov"
        }

        os.addenvs({ PATH = path.join(luajit_dir, "bin") })
        for i, lib in ipairs(libs) do
            cprint("\t${💥} ${yellow}[5.%d]${reset} install ${green}%s${reset}", i, lib)
            os.exec("luarocks install --force-lock %s", lib)
        end

        -- Workaround install failure for lsqlite3 on 2025.8.16
        os.cd("/tmp")
        os.tryrm("/tmp/lsqlite-src")
        os.exec("git clone https://github.com/cyril0124/lsqlite-src.git")
        os.cd("lsqlite-src")
        os.exec("unzip lsqlite3_v096.zip")
        os.cd("lsqlite3_v096")
        os.exec("luarocks make --force-lock lsqlite3complete-0.9.6-1.rockspec")
        os.exec("luarocks make --force-lock lsqlite3-0.9.6-1.rockspec")

        os.exec("luarocks list")
    end)
end)

target("install_tinycc", function()
    set_kind("phony")
    on_run(function(target)
        os.cd(path.join(prj_dir, "extern", "luajit_tcc"))
        os.exec("make init")
        os.exec("make")
        os.cd(os.workingdir())
    end)
end)

target("build_all_tools", function()
    set_kind("phony")
    on_run(function()
        local tools_target = {
            "testbench_gen",
            "dpi_exporter",
            "cov_exporter",
            "signal_db_gen",
            "wave_vpi_main",
            "verilua_prebuild" -- TODO: Remove this?
        }
        for _, target in ipairs(tools_target) do
            os.exec("xmake build -y -v %s", target)
        end

        import("lib.detect.find_file")
        if find_file("verdi", { "$(env PATH)" }) and os.getenv("VERDI_HOME") then
            os.exec("xmake build -y -v wave_vpi_main_fsdb")
        end
    end)
end)

target("setup_verilua", function()
    set_kind("phony")
    on_run(function(target)
        local shell_rc = path.join(os.getenv("HOME"), "." .. os.shell() .. "rc")
        local has_match = false

        for line in io.lines(shell_rc) do
            if line:match("^[^#]*export VERILUA_HOME=") then
                has_match = true
            end
        end
        if not has_match then
            local file = io.open(shell_rc, "a")
            if file then
                file:print("")
                file:print("# >>> verilua setup >>>")
                file:print("export VERILUA_HOME=$(curdir)")
                file:print("source $VERILUA_HOME/activate_verilua.sh")
                file:print("# <<< verilua setup <<<")
                file:close()
            end
        end

        cprint("[setup_verilua] shell_rc: ${green underline}%s${reset}, has_match: %s", shell_rc, tostring(has_match))

        os.exec("xmake run -y -v build_libverilua")
        os.exec("xmake run -y -v build_all_tools")
        os.exec("xmake build -y -v libsignal_db_gen")

        import("lib.detect.find_file")
        if find_file("iverilog", { "$(env PATH)" }) then
            os.exec("xmake build -y -v iverilog_vpi_module")
        end
    end)
end)

target("apply_xmake_patch", function()
    set_kind("phony")
    on_run(function(target)
        os.exec("bash apply_xmake_patch.sh")
    end)
end)

target("verilua", function()
    set_kind("phony")
    on_install(function(target)
        cprint("${💥} ${yellow}[1/7]${reset} Update git submodules...")
        os.exec("xmake run update_submodules")

        cprint("${💥} ${yellow}[2/7]${reset} Install other libs...")
        os.exec("xmake run install_other_libs")

        cprint("${💥} ${yellow}[3/7]${reset} Install LuaJIT-2.1...")
        os.exec("xmake run install_luajit")

        cprint("${💥} ${yellow}[4/7]${reset} Install lua modules...")
        os.exec("xmake run install_lua_modules")

        cprint("${💥} ${yellow}[5/7]${reset} Install tinycc...")
        os.exec("xmake run install_tinycc")

        cprint("${💥} ${yellow}[6/7]${reset} Setup verilua home on ${green}%s${reset}...", os.shell())
        os.exec("xmake run setup_verilua")

        cprint("${💥} ${yellow}[7/7]${reset} Applying verilua patch for xmake...")
        os.exec("xmake run apply_xmake_patch")
    end)
end)

target("test", function()
    set_kind("phony")
    on_run(function(target)
        import("lib.detect.find_file")

        local old_env = os.getenvs()

        local simulators = {}
        local has_vcs = false

        if find_file("iverilog", { "$(env PATH)" }) then
            table.insert(simulators, "iverilog")
        end
        if find_file("verilator", { "$(env PATH)" }) then
            table.insert(simulators, "verilator")
        end
        if find_file("vcs", { "$(env PATH)" }) then
            has_vcs = true
            table.insert(simulators, "vcs")
        end

        assert(#simulators > 0, "No simulators found!")

        do
            os.cd(path.join(prj_dir, "examples", "tutorial_example"))

            for _, sim in ipairs(simulators) do
                os.setenv("SIM", sim)
                os.exec("rm build -rf")
                os.exec("xmake build -v -P .")
                if sim == "vcs" then
                    -- ignore error
                    try { function() os.exec("xmake run -v -P .") end }
                else
                    os.exec("xmake run -v -P .")
                end
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "WAL"))
            os.setenv("SIM", "iverilog")
            os.exec("rm build -rf")
            os.exec("xmake build -v -P . gen_wave")
            os.exec("xmake run -v -P . gen_wave")
            os.exec("xmake build -v -P . sim_wave")
            os.exec("xmake run -v -P . sim_wave")
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE"))
            os.tryrm("csrc")
            os.tryrm("simv*")
            os.tryrm("sim_build*")
            os.execv(os.shell(), { "run_verilator.sh" })
            os.execv(os.shell(), { "run_verilator_p.sh" })

            if has_vcs then
                os.execv(os.shell(), { "run_vcs.sh" })
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE_dummy_vpi"))
            os.tryrm("csrc")
            os.tryrm("simv*")
            os.tryrm("sim_build*")
            os.execv(os.shell(), { "run_verilator.sh" })
            os.execv(os.shell(), { "run_verilator_dpi.sh" })

            if has_vcs then
                os.execv(os.shell(), { "run_vcs.sh" })
                os.execv(os.shell(), { "run_vcs_dpi.sh" })
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE_virtual_rtl"))
            os.tryrm("sim_build_dpi")
            os.execv(os.shell(), { "run_verilator_dpi.sh" })

            if has_vcs then
                os.tryrm("csrc")
                os.tryrm("simv_dpi")
                os.tryrm("simv_dpi.daidir")
                os.execv(os.shell(), { "run_vcs_dpi.sh" })
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "simple_ut_env"))
            os.tryrm("build")
            os.exec("xmake build -P . test_counter")
            os.exec("xmake run -v -P . test_counter")
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "wave_vpi_padding_issue"))
            os.exec("rm build -rf")
            os.exec("xmake build -v -P . test")
            os.exec("xmake run -v -P . test")
            os.exec("xmake build -v -P . test_wave")
            os.exec("xmake run -v -P . test_wave")
        end

        do
            local test_dirs = {
                path.join(prj_dir, "tests", "test_edge"),
                path.join(prj_dir, "tests", "test_set_value"),
                path.join(prj_dir, "tests", "test_basic_signal"),
                path.join(prj_dir, "tests", "test_bitvec_signal"),
                path.join(prj_dir, "tests", "test_no_internal_clock"),
                path.join(prj_dir, "examples", "guided_tour"),
            }
            os.setenvs(old_env)
            for _, test_dir in ipairs(test_dirs) do
                os.cd(test_dir)
                local test = function(_simulators)
                    for _, sim in ipairs(_simulators) do
                        cprint("")
                        cprint(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
                        cprint("> sim: ${green underline}%s${reset}", sim)
                        cprint("> test_dir: ${green underline}%s${reset}", test_dir)
                        cprint(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")

                        os.setenv("SIM", sim)
                        os.tryrm("build")
                        os.exec("xmake build -v -P .")
                        -- if sim == "vcs" then
                        --     -- ignore error
                        --     try { function () os.exec("xmake run -v -P .") end }
                        -- else
                        os.exec("xmake run -v -P .")
                        -- end

                        cprint("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")
                        cprint("< sim: ${green underline}%s${reset}", sim)
                        cprint("< test_dir: ${green underline}%s${reset}", test_dir)
                        cprint("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")
                        cprint("")
                    end
                end
                test(simulators)

                if table.contains(simulators, "verilator") then
                    os.setenv("CFG_USE_INERTIAL_PUT", "1")
                    assert(os.getenv("CFG_USE_INERTIAL_PUT") == "1")
                    test({ "verilator" })
                    os.setenv("CFG_USE_INERTIAL_PUT", nil)
                    assert(os.getenv("CFG_USE_INERTIAL_PUT") == nil)
                end
            end
        end

        do
            os.cd(path.join(prj_dir, "tests", "test_basic_signal"))
            for _, sim in ipairs(simulators) do
                os.setenv("SIM", sim)
                os.setenv("NO_INTERNAL_CLOCK", "1")
                os.tryrm("build")
                os.exec("xmake build -v -P .")
                os.exec("xmake run -v -P .")
            end
            os.setenv("NO_INTERNAL_CLOCK", nil)
        end

        do
            local benchmark_cases = {
                "signal_operation",
                "multitasking",
                "matrix_multiplier",
                "matrix_multiplier_no_internal_clock",
            }
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "benchmarks"))
            for _, case in ipairs(benchmark_cases) do
                local test = function(_simulators)
                    for _, sim in ipairs(_simulators) do
                        os.setenv("SIM", sim)
                        os.tryrm("build")
                        os.exec("xmake build -P . %s", case)
                        os.exec("xmake run -P . %s", case)
                    end
                end
                test(simulators)

                if table.contains(simulators, "verilator") then
                    os.setenv("CFG_USE_INERTIAL_PUT", "1")
                    test({ "verilator" })
                    os.setenv("CFG_USE_INERTIAL_PUT", nil)
                end
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "test_testbench_gen"))
            os.exec("xmake run -P .")
            for _, sim in ipairs(simulators) do
                if sim ~= "iverilog" then
                    os.setenv("SIM", sim)
                    os.tryrm("./build")
                    os.exec("xmake b -P . test_run_ansi")
                    os.exec("xmake r -P . test_run_ansi")

                    -- TODO: testbench_gen for non-ansi port declaration
                    -- os.exec("xmake b -P . test_run_non_ansi")
                    -- os.exec("xmake r -P . test_run_non_ansi")
                end
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests"))
            os.exec("xmake run -P . test_all")
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "test_dpi_exporter"))
            os.exec("xmake run -P .")
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "test_signal_db"))
            os.exec("xmake build -P .")
            os.exec("xmake run -P .")
        end

        cprint([[${green}
  _____         _____ _____
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___
 |  ___/ /\ \  \___ \\___ \
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/
${reset}]])
    end)
end)

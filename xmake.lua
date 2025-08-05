---@diagnostic disable

local prj_dir    = os.curdir()
local libs_dir   = path.join(prj_dir, "conan_installed")

includes(path.join(prj_dir, "libverilua", "xmake.lua"))
includes(path.join(prj_dir, "src", "cov_exporter", "xmake.lua"))
includes(path.join(prj_dir, "src", "dpi_exporter", "xmake.lua"))
includes(path.join(prj_dir, "src", "signal_db_gen", "xmake.lua"))
includes(path.join(prj_dir, "src", "testbench_gen", "xmake.lua"))
includes(path.join(prj_dir, "src", "wave_vpi", "xmake.lua"))

target("update_submodules")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        execute("git submodule update --init --recursive")
    end)

target("install_luajit")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        local curr_dir = os.workingdir()
        local luajit_pro_dir = curr_dir .. "/luajit-pro"
        local luajit_dir = luajit_pro_dir .. "/luajit2.1"
        local luarocks_version = "3.12.2"

        -- Remove existing luajit-pro directory
        execute("rm -rf " .. luajit_pro_dir)
        execute("git clone https://github.com/cyril0124/luajit-pro.git " .. luajit_pro_dir)

        -- Build luajit_pro_helper
        os.cd(luajit_pro_dir)
        execute("cargo build --release")

        -- Build luajit
        execute("bash init.sh")
        os.trycp(luajit_dir .. "/bin/luajit", luajit_dir .. "/bin/lua")

        -- Add luajit to PATH
        os.addenvs({PATH = luajit_dir .. "/bin"})

        -- Build luarocks
        do
            execute("wget -P %s https://luarocks.github.io/luarocks/releases/luarocks-%s.tar.gz", luajit_pro_dir, luarocks_version)
            execute("tar -zxvf luarocks-%s.tar.gz", luarocks_version)
            os.cd("luarocks-" .. luarocks_version)

            execute("make clean")
            execute("./configure --with-lua=%s --prefix=%s", luajit_dir, luajit_dir)
            execute("make")
            execute("make install")
        end

        -- Rebuild luajit_pro_helper
        os.cd(luajit_pro_dir)
        execute("cargo build --release")

        os.cd(curr_dir)
    end)

target("reinstall_luajit")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        local curr_dir = os.workingdir()
        local luajit_pro_dir = curr_dir .. "/luajit-pro"
        local luajit_dir = luajit_pro_dir .. "/luajit2.1"

        -- build luajit_pro_helper
        os.cd(luajit_pro_dir)
        execute("cargo build --release")

        -- execute("git reset --hard origin/master")
        -- execute("git pull origin master")
        execute("bash init.sh")
        os.trycp(path.join(luajit_dir, "bin", "luajit"), path.join(luajit_dir, "bin", "lua"))

        os.cd(curr_dir)
    end)


target("install_other_libs")
    set_kind("phony")
    on_run(function (target)
        -- Environment variable `CI_USE_CONAN_CACHE` is set by `.github/workflows/regression.yml`(Check conan libs)
        if os.getenv("CI_USE_CONAN_CACHE") then
            print("[xmake.lua] [install_other_libs] Using cached conan libs...")
            return
        end

        local conan_cmd = "conan"
        local has_conan = try { function () return os.iorun("conan --version") end }

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
            function ()
                os.exec(conan_cmd .. " create . --build=missing")
            end,
            catch
            {
                function (errors)
                    os.exec(conan_cmd .. " profile detect --force")
                    os.exec(conan_cmd .. " create . --build=missing")
                end
            }
        }

        os.cd(prj_dir)
        os.exec(conan_cmd .. " install . --output-folder=%s --build=missing", libs_dir)
    end)

target("install_lua_modules")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        local curr_dir = os.workingdir()
        local luajit_pro_dir = path.join(curr_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")
        local libs = {
            "penlight",
            "luasocket",
            "lsqlite3",
            "linenoise",
            "argparse", -- Used by teal-language
        }

        os.addenvs({PATH = path.join(luajit_dir, "bin")})
        for i, lib in ipairs(libs) do
            cprint("\t${💥} ${yellow}[5.%d]${reset} install ${green}%s${reset}", i, lib)
            execute("luarocks install --force-lock %s", lib)
        end
        execute("luarocks list")
    end)

target("install_tinycc")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        os.cd(path.join(prj_dir, "extern", "luajit_tcc"))
        execute("make init")
        execute("make")
        os.cd(os.workingdir())
    end)

target("setup_verilua")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
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

        -- generate libwwave_vpi_wellen_impl
        os.cd("wave_vpi")
        execute("cargo build --release")
        os.cd(os.workingdir())

        execute("xmake run -y -v build_libverilua")
        execute("xmake build -y -v testbench_gen")
        execute("xmake build -y -v dpi_exporter")
        execute("xmake build -y -v cov_exporter")
        execute("xmake build -y -v signal_db_gen")
        execute("xmake build -y -v libsignal_db_gen")
        execute("xmake build -y -v wave_vpi_main")
        execute("xmake build -y -v verilua_prebuild")

        import("lib.detect.find_file")
        if find_file("verdi", {"$(env PATH)"}) and os.getenv("VERDI_HOME") then
            execute("xmake build -y -v wave_vpi_main_fsdb")
        end
        if find_file("iverilog", {"$(env PATH)"}) then
            execute("xmake build -y -v iverilog_vpi_module")
        end
    end)

target("apply_xmake_patch")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        execute("bash apply_xmake_patch.sh")
    end)

target("verilua")
    set_kind("phony")
    on_install(function (target)
        local execute = os.exec
        cprint("${💥} ${yellow}[1/7]${reset} Update git submodules...") do
            execute("xmake run update_submodules")
        end

        cprint("${💥} ${yellow}[2/7]${reset} Install other libs...") do
            execute("xmake run install_other_libs")
        end
        
        cprint("${💥} ${yellow}[3/7]${reset} Install LuaJIT-2.1...") do
            execute("xmake run install_luajit")
        end

        cprint("${💥} ${yellow}[4/7]${reset} Install lua modules...") do
            execute("xmake run install_lua_modules")
        end

        cprint("${💥} ${yellow}[5/7]${reset} Install tinycc...") do
            execute("xmake run install_tinycc")
        end

        cprint("${💥} ${yellow}[6/7]${reset} Setup verilua home on ${green}%s${reset}...", os.shell()) do
            execute("xmake run setup_verilua")
        end

        cprint("${💥} ${yellow}[7/7]${reset} Applying verilua patch for xmake...") do
            execute("xmake run apply_xmake_patch")
        end
    end)

target("test")
    set_kind("phony")
    on_run(function (target)
        import("lib.detect.find_file")

        local old_env = os.getenvs()

        local simulators = {}
        local has_vcs = false

        if find_file("iverilog", {"$(env PATH)"}) then
            table.insert(simulators, "iverilog")
        end
        if find_file("verilator", {"$(env PATH)"}) then
            table.insert(simulators, "verilator")
        end
        if find_file("vcs", {"$(env PATH)"}) then
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
                    try { function () os.exec("xmake run -v -P .") end }
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
            os.execv(os.shell(), {"run_verilator.sh"})
            os.execv(os.shell(), {"run_verilator_p.sh"})

            if has_vcs then
                os.execv(os.shell(), {"run_vcs.sh"})
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE_dummy_vpi"))
            os.tryrm("csrc")
            os.tryrm("simv*")
            os.tryrm("sim_build*")
            os.execv(os.shell(), {"run_verilator.sh"})
            os.execv(os.shell(), {"run_verilator_dpi.sh"})

            if has_vcs then
                os.execv(os.shell(), {"run_vcs.sh"})
                os.execv(os.shell(), {"run_vcs_dpi.sh"})
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE_virtual_rtl"))
            os.tryrm("sim_build_dpi")
            os.execv(os.shell(), {"run_verilator_dpi.sh"})

            if has_vcs then
                os.tryrm("csrc")
                os.tryrm("simv_dpi")
                os.tryrm("simv_dpi.daidir")
                os.execv(os.shell(), {"run_vcs_dpi.sh"})
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
                path.join(prj_dir, "tests", "test_bitvec_signal"),
            }
            os.setenvs(old_env)
            for _, test_dir in ipairs(test_dirs) do
                os.cd(test_dir)
                for _, sim in ipairs(simulators) do
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
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests"))
            os.exec("xmake run -P . test_all")
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

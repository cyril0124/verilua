---@diagnostic disable: undefined-global, undefined-field, unnecessary-if

local prj_dir  = os.projectdir()
local libs_dir = path.join(prj_dir, "conan_installed")

includes(path.join(prj_dir, "libverilua", "xmake.lua"))
includes(path.join(prj_dir, "src", "cov_exporter", "xmake.lua"))
includes(path.join(prj_dir, "src", "dpi_exporter", "xmake.lua"))
includes(path.join(prj_dir, "src", "signal_db_gen", "xmake.lua"))
includes(path.join(prj_dir, "src", "testbench_gen", "xmake.lua"))
includes(path.join(prj_dir, "src", "wave_vpi", "xmake.lua"))
includes(path.join(prj_dir, "src", "nosim", "xmake.lua"))

local CC = os.getenv("CC")
local CXX = os.getenv("CXX")
if CC then
    set_toolset("cc", CC)
end
if CXX then
    set_toolset("cxx", CXX)
    set_toolset("ld", CXX)
end

target("update_submodules", function()
    set_kind("phony")
    on_run(function(target)
        os.exec("git submodule update --init --recursive")
    end)
end)

target("install_luarocks", function()
    set_kind("phony")
    on_run(function(target)
        local luajit_pro_dir = path.join(prj_dir, "luajit-pro")
        local luarocks_version = "3.12.2"

        -- Add luajit to PATH
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")
        os.addenvs({ PATH = path.join(luajit_dir, "bin") })

        -- Build luarocks
        do
            os.cd(luajit_pro_dir)
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

        os.cd(prj_dir)
    end)
end)

target("install_luajit", function()
    set_kind("phony")
    on_run(function(target)
        local luajit_pro_dir = path.join(prj_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")

        -- Build luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("git submodule update --init")
        os.exec("cargo build --release")
        -- Build luajit
        os.exec("bash init.sh")
        os.trycp(path.join(luajit_dir, "bin", "luajit"), path.join(luajit_dir, "bin", "lua"))

        -- Add luajit to PATH
        os.addenvs({ PATH = path.join(luajit_dir, "bin") })

        -- Install luarocks
        os.exec("xmake run install_luarocks")

        -- Rebuild luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("cargo build --release")

        os.cd(prj_dir)
    end)
end)

target("reinstall_luajit", function()
    set_kind("phony")
    on_run(function(target)
        local luajit_pro_dir = path.join(prj_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")

        -- build luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("cargo build --release")

        -- execute("git reset --hard origin/master")
        -- execute("git pull origin master")
        os.exec("bash init.sh")
        os.trycp(path.join(luajit_dir, "bin", "luajit"), path.join(luajit_dir, "bin", "lua"))

        -- Add luajit to PATH
        os.addenvs({ PATH = path.join(luajit_dir, "bin") })

        os.cd(prj_dir)
    end)
end)

target("install_libgmp", function()
    set_kind("phony")
    on_run(function(target)
        if os.getenv("CI_USE_CONAN_CACHE") and os.isfile(libs_dir, "lib", "libgmp.so") then
            print("[xmake.lua] [install_libgmp] Using cached libgmp...")
            return
        end

        local build_dir = path.join(prj_dir, "build")
        local shared_dir = path.join(prj_dir, "shared")
        if not os.isdir(build_dir) then
            os.mkdir(build_dir)
        end
        if not os.isdir(shared_dir) then
            os.mkdir(shared_dir)
        end

        local libgmp_dir = path.join(build_dir, "gmp-6.3.0")
        os.cd(build_dir)
        os.exec("wget https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz")
        os.exec("tar xJf gmp-6.3.0.tar.xz")
        os.cd(libgmp_dir)
        os.exec("./configure --prefix=%s --disable-static", libs_dir)
        os.exec("make -j" .. os.cpuinfo().ncpu)
        os.exec("make install")

        -- Copy libgmp into shared dir
        os.cp(path.join(libs_dir, "lib", "libgmp.so*"), shared_dir)
    end)
end)

target("install_other_libs", function()
    set_kind("phony")
    on_run(function(target)
        local shared_dir = path.join(prj_dir, "shared")

        -- Environment variable `CI_USE_CONAN_CACHE` is set by `.github/workflows/regression.yml`(Check conan libs)
        if os.getenv("CI_USE_CONAN_CACHE") then
            print("[xmake.lua] [install_other_libs] Using cached conan libs...")

            os.mkdir(shared_dir)
            os.cp(path.join(libs_dir, "lib", "libgmp.so*"), shared_dir)
            return
        end

        local conan_cmd = "conan"
        local build_dir = path.join(prj_dir, "build")
        local has_conan = try { function() return os.iorun("conan --version") end }

        if not os.isdir(build_dir) then
            os.mkdir(build_dir)
        end

        if not has_conan then
            os.cd(build_dir)
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

        -- Install libgmp
        os.exec("xmake run install_libgmp")
    end)
end)

target("install_lua_modules", function()
    set_kind("phony")
    on_run(function(target)
        local luajit_pro_dir = path.join(prj_dir, "luajit-pro")
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
            "nosim"
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

target("format", function()
    set_kind("phony")
    on_run(function(target)
        cprint("${💥} ${yellow}Formatting C++ files...${reset}")

        -- Find all C++ source and header files in src directory
        local cpp_patterns = { "*.cpp", "*.hpp", "*.h", "*.cc", "*.cxx", "*.hxx" }
        local files = {}

        -- Try to use fd first, fallback to find
        local use_fd = os.iorun("which fd") ~= nil

        for _, pattern in ipairs(cpp_patterns) do
            local found
            if use_fd then
                found = os.iorunv("fd", { "--glob", pattern, "src" })
            else
                found = os.iorunv("find", { "src", "-name", pattern, "-type", "f" })
            end

            if found then
                for file in found:gmatch("[^\r\n]+") do
                    table.insert(files, file)
                end
            end
        end

        -- Format each file with clang-format
        for _, file in ipairs(files) do
            cprint("${blue}Formatting: ${green}%s${reset}", file)
            os.exec("clang-format -i %s", file)
        end

        cprint("${green}All C++ files have been formatted!${reset}")
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
        os.exec("xmake build -y -v libsignal_db_gen")
        os.exec("xmake run -y -v build_all_tools")

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

        --
        -- Configuration
        --
        local verbose = os.getenv("VERBOSE") == "1" or os.getenv("V") == "1"
        local stop_on_fail = os.getenv("STOP_ON_FAIL") == "1"
        local old_env = os.getenvs()

        --
        -- Test statistics tracking
        --
        local test_stats = {
            total = 0,
            passed = 0,
            failed = 0,
            start_time = os.time(),
            results = {}
        }

        --
        -- Utility functions for beautified output
        --
        local function get_time_str()
            return os.date("%H:%M:%S")
        end

        local function format_duration(seconds)
            if seconds < 60 then
                return string.format("%.1fs", seconds)
            elseif seconds < 3600 then
                local min = math.floor(seconds / 60)
                local sec = seconds % 60
                return string.format("%dm %ds", min, sec)
            else
                local hr = math.floor(seconds / 3600)
                local min = math.floor((seconds % 3600) / 60)
                return string.format("%dh %dm", hr, min)
            end
        end

        local function print_header()
            cprint("")
            cprint("${bright}╔══════════════════════════════════════════════════════════════════════════════╗${reset}")
            cprint("${bright}║                                                                              ║${reset}")
            cprint(
                "${bright}║${reset}                     ${cyan}V E R I L U A${reset}   ${white}T E S T   S U I T E${reset}                      ${bright}║${reset}")
            cprint("${bright}║                                                                              ║${reset}")
            cprint("${bright}╚══════════════════════════════════════════════════════════════════════════════╝${reset}")
            cprint("")
        end

        local function print_section(section_num, total_sections, title)
            cprint("")
            cprint("${bright}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${reset}")
            cprint("${bright}┃${reset} ${yellow}[%d/%d]${reset} ${cyan}%s${reset}", section_num, total_sections, title)
            cprint("${bright}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${reset}")
        end

        local function print_test_start(test_name, simulator, extra_info)
            test_stats.total = test_stats.total + 1
            local info_str = extra_info and string.format(" ${dim}(%s)${reset}", extra_info) or ""
            if verbose then
                cprint("  ${bright}├─${reset} ${white}[%s]${reset} Running: ${green}%s${reset} @ ${magenta}%s${reset}%s",
                    get_time_str(), test_name, simulator, info_str)
            else
                cprint("  ${bright}├─${reset} ${white}[%d]${reset} ${green}%s${reset} @ ${magenta}%s${reset}%s",
                    test_stats.total, test_name, simulator, info_str)
            end
        end

        local function print_test_result(test_name, simulator, success, duration, extra_info)
            if success then
                test_stats.passed = test_stats.passed + 1
            else
                test_stats.failed = test_stats.failed + 1
            end

            table.insert(test_stats.results, {
                name = test_name,
                simulator = simulator,
                success = success,
                duration = duration,
                extra = extra_info
            })

            local info_str = extra_info and string.format(" ${dim}(%s)${reset}", extra_info) or ""
            local duration_str = format_duration(duration)
            if success then
                if verbose then
                    cprint("  ${bright}└─${reset} ${white}[%s]${reset} ${green}✓ PASSED${reset} ${dim}(%s)${reset}%s",
                        get_time_str(), duration_str, info_str)
                else
                    cprint("  ${bright}└─${reset} ${green}✓ PASSED${reset} ${dim}(%s)${reset}%s",
                        duration_str, info_str)
                end
            else
                if verbose then
                    cprint("  ${bright}└─${reset} ${white}[%s]${reset} ${red}✗ FAILED${reset} ${dim}(%s)${reset}%s",
                        get_time_str(), duration_str, info_str)
                else
                    cprint("  ${bright}└─${reset} ${red}✗ FAILED${reset} ${dim}(%s)${reset}%s",
                        duration_str, info_str)
                end

                if stop_on_fail then
                    cprint("")
                    cprint("${red}${bright}✗ Test failed: %s @ %s${reset}", test_name, simulator)
                    cprint("${red}Stopping test suite due to STOP_ON_FAIL=1${reset}")
                    os.exit(1)
                end
            end
        end

        local function print_summary()
            local total_duration = os.time() - test_stats.start_time
            local pass_rate = test_stats.total > 0 and (test_stats.passed / test_stats.total * 100) or 0

            cprint("")
            cprint("${bright}╔══════════════════════════════════════════════════════════════════════════════╗${reset}")
            cprint(
                "${bright}║${reset}                           ${cyan}TEST SUMMARY${reset}                                     ${bright}║${reset}")
            cprint("${bright}╠══════════════════════════════════════════════════════════════════════════════╣${reset}")
            cprint(
                "${bright}║${reset}                                                                              ${bright}║${reset}")
            cprint(
                "${bright}║${reset}   ${white}Total Tests:${reset}  ${bright}%d${reset}                                                            ${bright}║${reset}",
                test_stats.total)
            cprint(
                "${bright}║${reset}   ${green}Passed:${reset}       ${green}%d${reset}                                                            ${bright}║${reset}",
                test_stats.passed)
            if test_stats.failed > 0 then
                cprint(
                    "${bright}║${reset}   ${red}Failed:${reset}       ${red}%d${reset}                                                            ${bright}║${reset}",
                    test_stats.failed)
            else
                cprint(
                    "${bright}║${reset}   ${dim}Failed:${reset}       ${dim}%d${reset}                                                            ${bright}║${reset}",
                    test_stats.failed)
            end
            cprint(
                "${bright}║${reset}   ${white}Pass Rate:${reset}    ${bright}%.1f%%${reset}                                                        ${bright}║${reset}",
                pass_rate)
            cprint(
                "${bright}║${reset}   ${white}Duration:${reset}     ${bright}%s${reset}                                                         ${bright}║${reset}",
                format_duration(total_duration))
            cprint(
                "${bright}║${reset}                                                                              ${bright}║${reset}")
            cprint("${bright}╚══════════════════════════════════════════════════════════════════════════════╝${reset}")
        end

        local function print_final_result()
            cprint("")
            if test_stats.failed == 0 then
                cprint([[${green}
    ██████╗  █████╗ ███████╗███████╗███████╗██████╗
    ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗
    ██████╔╝███████║███████╗███████╗█████╗  ██║  ██║
    ██╔═══╝ ██╔══██║╚════██║╚════██║██╔══╝  ██║  ██║
    ██║     ██║  ██║███████║███████║███████╗██████╔╝
    ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═════╝
${reset}]])
                cprint("${green}              ✓ All tests passed successfully!${reset}")
            else
                cprint([[${red}
    ███████╗ █████╗ ██╗██╗     ███████╗██████╗
    ██╔════╝██╔══██╗██║██║     ██╔════╝██╔══██╗
    █████╗  ███████║██║██║     █████╗  ██║  ██║
    ██╔══╝  ██╔══██║██║██║     ██╔══╝  ██║  ██║
    ██║     ██║  ██║██║███████╗███████╗██████╔╝
    ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═════╝
${reset}]])
                cprint("${red}              ✗ %d test(s) failed!${reset}", test_stats.failed)
            end
            cprint("")
        end

        -- Wrapper for executing commands with optional verbose output
        local function run_cmd(cmd)
            if verbose then
                os.exec(cmd)
            else
                os.execv(os.shell(), { "-c", cmd .. " > /dev/null 2>&1" })
            end
        end

        local function run_cmd_allow_fail(cmd)
            try {
                function()
                    if verbose then
                        os.exec(cmd)
                    else
                        os.execv(os.shell(), { "-c", cmd .. " > /dev/null 2>&1" })
                    end
                end
            }
        end

        -- Wrapper for executing shell scripts with optional verbose output
        local function run_shell_script(script)
            if verbose then
                os.execv(os.shell(), { script })
            else
                os.execv(os.shell(), { "-c", "." .. "/" .. script .. " > /dev/null 2>&1" })
            end
        end

        --
        -- Detect available simulators
        --
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

        --
        -- Print header and configuration
        --
        print_header()
        cprint("${white}Configuration:${reset}")
        cprint("  ${dim}•${reset} Simulators: ${cyan}%s${reset}", table.concat(simulators, ", "))
        cprint("  ${dim}•${reset} Verbose: ${cyan}%s${reset}", verbose and "yes" or "no (set VERBOSE=1 to enable)")
        cprint("  ${dim}•${reset} Stop on fail: ${cyan}%s${reset}",
            stop_on_fail and "yes" or "no (set STOP_ON_FAIL=1 to enable)")
        cprint("  ${dim}•${reset} Started at: ${cyan}%s${reset}", os.date("%Y-%m-%d %H:%M:%S"))

        local total_sections = 12

        --
        -- Section: Tutorial Example
        --
        print_section(1, total_sections, "Tutorial Example")
        do
            os.cd(path.join(prj_dir, "examples", "tutorial_example"))
            for _, sim in ipairs(simulators) do
                local start_time = os.time()
                print_test_start("tutorial_example", sim)
                os.setenv("SIM", sim)
                os.tryrm("build")
                local success = true
                try {
                    function()
                        run_cmd("xmake build -v -P .")
                        if sim == "vcs" then
                            run_cmd_allow_fail("xmake run -v -P .")
                        else
                            run_cmd("xmake run -v -P .")
                        end
                    end,
                    catch {
                        function(e)
                            success = false
                        end
                    }
                }
                print_test_result("tutorial_example", sim, success, os.time() - start_time)
            end
        end

        --
        -- Section: WAL Example
        --
        print_section(2, total_sections, "WAL (Waveform Analysis Library)")
        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "WAL"))
            os.setenv("SIM", "iverilog")
            local start_time = os.time()
            print_test_start("WAL/gen_wave", "iverilog")
            os.tryrm("build")
            local success = true
            try {
                function()
                    run_cmd("xmake build -v -P . gen_wave")
                    run_cmd("xmake run -v -P . gen_wave")
                end,
                catch { function(e) success = false end }
            }
            print_test_result("WAL/gen_wave", "iverilog", success, os.time() - start_time)

            start_time = os.time()
            print_test_start("WAL/sim_wave", "iverilog")
            success = true
            try {
                function()
                    run_cmd("xmake build -v -P . sim_wave")
                    run_cmd("xmake run -v -P . sim_wave")
                end,
                catch { function(e) success = false end }
            }
            print_test_result("WAL/sim_wave", "iverilog", success, os.time() - start_time)
        end

        --
        -- Section: HSE Example
        --
        print_section(3, total_sections, "HSE (Hardware Script Engine)")
        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE"))
            os.tryrm("csrc")
            os.tryrm("simv*")
            os.tryrm("sim_build*")

            local start_time = os.time()
            print_test_start("HSE/verilator", "verilator")
            local success = true
            try {
                function() run_shell_script("run_verilator.sh") end,
                catch { function(e) success = false end }
            }
            print_test_result("HSE/verilator", "verilator", success, os.time() - start_time)

            start_time = os.time()
            print_test_start("HSE/verilator_p", "verilator")
            success = true
            try {
                function() run_shell_script("run_verilator_p.sh") end,
                catch { function(e) success = false end }
            }
            print_test_result("HSE/verilator_p", "verilator", success, os.time() - start_time)

            if has_vcs then
                start_time = os.time()
                print_test_start("HSE/vcs", "vcs")
                success = true
                try {
                    function() run_shell_script("run_vcs.sh") end,
                    catch { function(e) success = false end }
                }
                print_test_result("HSE/vcs", "vcs", success, os.time() - start_time)
            end
        end

        --
        -- Section: HSE Dummy VPI
        --
        print_section(4, total_sections, "HSE Dummy VPI")
        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE_dummy_vpi"))
            os.tryrm("csrc")
            os.tryrm("simv*")
            os.tryrm("sim_build*")

            local start_time = os.time()
            print_test_start("HSE_dummy_vpi/verilator", "verilator")
            local success = true
            try {
                function() run_shell_script("run_verilator.sh") end,
                catch { function(e) success = false end }
            }
            print_test_result("HSE_dummy_vpi/verilator", "verilator", success, os.time() - start_time)

            start_time = os.time()
            print_test_start("HSE_dummy_vpi/verilator_dpi", "verilator")
            success = true
            try {
                function() run_shell_script("run_verilator_dpi.sh") end,
                catch { function(e) success = false end }
            }
            print_test_result("HSE_dummy_vpi/verilator_dpi", "verilator", success, os.time() - start_time)

            if has_vcs then
                start_time = os.time()
                print_test_start("HSE_dummy_vpi/vcs", "vcs")
                success = true
                try {
                    function() run_shell_script("run_vcs.sh") end,
                    catch { function(e) success = false end }
                }
                print_test_result("HSE_dummy_vpi/vcs", "vcs", success, os.time() - start_time)

                start_time = os.time()
                print_test_start("HSE_dummy_vpi/vcs_dpi", "vcs")
                success = true
                try {
                    function() run_shell_script("run_vcs_dpi.sh") end,
                    catch { function(e) success = false end }
                }
                print_test_result("HSE_dummy_vpi/vcs_dpi", "vcs", success, os.time() - start_time)
            end
        end

        --
        -- Section: HSE Virtual RTL
        --
        print_section(5, total_sections, "HSE Virtual RTL")
        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE_virtual_rtl"))
            os.tryrm("sim_build_dpi")

            local start_time = os.time()
            print_test_start("HSE_virtual_rtl/verilator_dpi", "verilator")
            local success = true
            try {
                function() run_shell_script("run_verilator_dpi.sh") end,
                catch { function(e) success = false end }
            }
            print_test_result("HSE_virtual_rtl/verilator_dpi", "verilator", success, os.time() - start_time)

            if has_vcs then
                os.tryrm("csrc")
                os.tryrm("simv_dpi")
                os.tryrm("simv_dpi.daidir")
                start_time = os.time()
                print_test_start("HSE_virtual_rtl/vcs_dpi", "vcs")
                success = true
                try {
                    function() run_shell_script("run_vcs_dpi.sh") end,
                    catch { function(e) success = false end }
                }
                print_test_result("HSE_virtual_rtl/vcs_dpi", "vcs", success, os.time() - start_time)
            end
        end

        --
        -- Section: Simple UT Environment
        --
        print_section(6, total_sections, "Simple UT Environment")
        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "simple_ut_env"))
            os.tryrm("build")

            local start_time = os.time()
            print_test_start("simple_ut_env/test_counter", "verilator")
            local success = true
            try {
                function()
                    run_cmd("xmake build -P . test_counter")
                    run_cmd("xmake run -v -P . test_counter")
                end,
                catch { function(e) success = false end }
            }
            print_test_result("simple_ut_env/test_counter", "verilator", success, os.time() - start_time)
        end

        --
        -- Section: Wave VPI Padding Issue
        --
        print_section(7, total_sections, "Wave VPI Padding Issue Test")
        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "wave_vpi_padding_issue"))
            os.tryrm("build")

            local start_time = os.time()
            print_test_start("wave_vpi_padding/test", "verilator")
            local success = true
            try {
                function()
                    run_cmd("xmake build -v -P . test")
                    run_cmd("xmake run -v -P . test")
                end,
                catch { function(e) success = false end }
            }
            print_test_result("wave_vpi_padding/test", "verilator", success, os.time() - start_time)

            start_time = os.time()
            print_test_start("wave_vpi_padding/test_wave", "verilator")
            success = true
            try {
                function()
                    run_cmd("xmake build -v -P . test_wave")
                    run_cmd("xmake run -v -P . test_wave")
                end,
                catch { function(e) success = false end }
            }
            print_test_result("wave_vpi_padding/test_wave", "verilator", success, os.time() - start_time)
        end

        --
        -- Section: Core Tests
        --
        print_section(8, total_sections, "Core Tests (Multi-Simulator)")
        do
            local test_dirs = {
                { path.join(prj_dir, "tests", "test_edge"),              "test_edge" },
                { path.join(prj_dir, "tests", "test_set_value"),         "test_set_value" },
                { path.join(prj_dir, "tests", "test_basic_signal"),      "test_basic_signal" },
                { path.join(prj_dir, "tests", "test_scheduler"),         "test_scheduler" },
                { path.join(prj_dir, "tests", "test_comb"),              "test_comb" },
                { path.join(prj_dir, "tests", "test_bitvec_signal"),     "test_bitvec_signal" },
                { path.join(prj_dir, "tests", "test_no_internal_clock"), "test_no_internal_clock" },
                { path.join(prj_dir, "examples", "guided_tour"),         "guided_tour" },
                { path.join(prj_dir, "examples", "simple_mux"),          "simple_mux" },
            }
            os.setenvs(old_env)

            for _, test_info in ipairs(test_dirs) do
                local test_dir, test_name = test_info[1], test_info[2]
                os.cd(test_dir)

                -- Regular simulator tests
                for _, sim in ipairs(simulators) do
                    local start_time = os.time()
                    print_test_start(test_name, sim)
                    os.setenv("SIM", sim)
                    os.tryrm("build")
                    local success = true
                    try {
                        function()
                            run_cmd("xmake build -v -P .")
                            run_cmd("xmake run -v -P .")
                        end,
                        catch { function(e) success = false end }
                    }
                    print_test_result(test_name, sim, success, os.time() - start_time)
                end

                -- Inertial put test for verilator
                if table.contains(simulators, "verilator") then
                    local start_time = os.time()
                    print_test_start(test_name, "verilator", "inertial_put")
                    os.setenv("SIM", "verilator")
                    os.setenv("CFG_USE_INERTIAL_PUT", "1")
                    os.tryrm("build")
                    local success = true
                    try {
                        function()
                            run_cmd("xmake build -v -P .")
                            run_cmd("xmake run -v -P .")
                        end,
                        catch { function(e) success = false end }
                    }
                    os.setenv("CFG_USE_INERTIAL_PUT", nil)
                    print_test_result(test_name, "verilator", success, os.time() - start_time, "inertial_put")
                end
            end
        end

        --
        -- Section: No Internal Clock Tests
        --
        print_section(9, total_sections, "No Internal Clock Tests")
        do
            local test_dirs = {
                { path.join(prj_dir, "tests", "test_basic_signal"), "test_basic_signal" },
                { path.join(prj_dir, "tests", "test_comb"),         "test_comb" },
            }
            os.setenvs(old_env)

            for _, test_info in ipairs(test_dirs) do
                local test_dir, test_name = test_info[1], test_info[2]
                os.cd(test_dir)

                for _, sim in ipairs(simulators) do
                    local start_time = os.time()
                    print_test_start(test_name, sim, "no_internal_clock")
                    os.setenv("SIM", sim)
                    os.setenv("NO_INTERNAL_CLOCK", "1")
                    os.tryrm("build")
                    local success = true
                    try {
                        function()
                            run_cmd("xmake build -v -P .")
                            run_cmd("xmake run -v -P .")
                        end,
                        catch { function(e) success = false end }
                    }
                    print_test_result(test_name, sim, success, os.time() - start_time, "no_internal_clock")
                end
                os.setenv("NO_INTERNAL_CLOCK", nil)
            end
        end

        --
        -- Section: Benchmarks
        --
        print_section(10, total_sections, "Performance Benchmarks")
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
                for _, sim in ipairs(simulators) do
                    local start_time = os.time()
                    print_test_start("benchmark/" .. case, sim)
                    os.setenv("SIM", sim)
                    os.tryrm("build")
                    local success = true
                    try {
                        function()
                            run_cmd(string.format("xmake build -P . %s", case))
                            run_cmd(string.format("xmake run -P . %s", case))
                        end,
                        catch { function(e) success = false end }
                    }
                    print_test_result("benchmark/" .. case, sim, success, os.time() - start_time)
                end

                -- Inertial put test for verilator
                if table.contains(simulators, "verilator") then
                    local start_time = os.time()
                    print_test_start("benchmark/" .. case, "verilator", "inertial_put")
                    os.setenv("SIM", "verilator")
                    os.setenv("CFG_USE_INERTIAL_PUT", "1")
                    os.tryrm("build")
                    local success = true
                    try {
                        function()
                            run_cmd(string.format("xmake build -P . %s", case))
                            run_cmd(string.format("xmake run -P . %s", case))
                        end,
                        catch { function(e) success = false end }
                    }
                    os.setenv("CFG_USE_INERTIAL_PUT", nil)
                    print_test_result("benchmark/" .. case, "verilator", success, os.time() - start_time, "inertial_put")
                end
            end
        end

        --
        -- Section: Testbench Generator
        --
        print_section(11, total_sections, "Testbench Generator")
        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "test_testbench_gen"))

            local start_time = os.time()
            print_test_start("testbench_gen/gen", "--")
            local success = true
            try {
                function() run_cmd("xmake run -P .") end,
                catch { function(e) success = false end }
            }
            print_test_result("testbench_gen/gen", "--", success, os.time() - start_time)

            for _, sim in ipairs(simulators) do
                if sim ~= "iverilog" then
                    start_time = os.time()
                    print_test_start("testbench_gen/run_ansi", sim)
                    os.setenv("SIM", sim)
                    os.tryrm("./build")
                    success = true
                    try {
                        function()
                            run_cmd("xmake b -P . test_run_ansi")
                            run_cmd("xmake r -P . test_run_ansi")
                        end,
                        catch { function(e) success = false end }
                    }
                    print_test_result("testbench_gen/run_ansi", sim, success, os.time() - start_time)
                end
            end
        end

        --
        -- Section: Lua Unit Tests & Tools
        --
        print_section(12, total_sections, "Lua Unit Tests & Tools")
        do
            os.setenvs(old_env)

            -- Lua unit tests
            os.cd(path.join(prj_dir, "tests"))
            local start_time = os.time()
            print_test_start("lua_unit_tests", "luajit")
            local success = true
            try {
                function() run_cmd("xmake run -P . test_all") end,
                catch { function(e) success = false end }
            }
            print_test_result("lua_unit_tests", "luajit", success, os.time() - start_time)

            -- DPI exporter
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "test_dpi_exporter"))
            start_time = os.time()
            print_test_start("dpi_exporter", "--")
            success = true
            try {
                function() run_cmd("xmake run -P .") end,
                catch { function(e) success = false end }
            }
            print_test_result("dpi_exporter", "--", success, os.time() - start_time)

            -- Signal DB
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "test_signal_db"))
            start_time = os.time()
            print_test_start("signal_db", "--")
            success = true
            try {
                function()
                    run_cmd("xmake build -P .")
                    run_cmd("xmake run -P .")
                end,
                catch { function(e) success = false end }
            }
            print_test_result("signal_db", "--", success, os.time() - start_time)
        end

        --
        -- Print summary and final result
        --
        print_summary()
        print_final_result()
    end)
end)
